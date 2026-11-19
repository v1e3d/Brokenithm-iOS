using System;
using System.Collections.Generic;
using System.IO;
using System.Net;
using System.Net.NetworkInformation;
using System.Net.Security;
using System.Net.Sockets;
using System.Security.Authentication;
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;
using System.Text;
using System.Threading;

namespace BrokenithmLan
{
    /// <summary>
    /// Minimal web server for camera AIR (loopback by default, optionally the LAN with HTTPS). Serves camera\camera.html at "/" and a WebSocket at "/ws".
    /// The page sends six characters ('0' or '1'), one per IR beam from the lowest beam (1) to the highest (6).
    /// Implemented on raw TCP so it needs no HttpListener URL ACL or administrator rights.
    /// </summary>
    internal sealed class CameraAirServer : IDisposable
    {
        // Beam order bottom-to-top mapped to shared-memory AIR bytes, matching Brokenithm-SwiftUI (airLanes = [4,5,2,3,0,1] top-to-bottom).
        internal static readonly int[] BeamToByte = { 1, 0, 3, 2, 5, 4 };
        private const byte Pressed = 128;
        private const int StaleMs = 500;
        private const int MaxHeaderBytes = 16384;
        private const string WebSocketGuid = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";

        private readonly SharedMemoryState state;
        private readonly Action<string> log;
        private readonly int port;
        private readonly string pagePath;
        private readonly bool lan;
        private readonly X509Certificate2 certificate;
        private readonly List<TcpListener> listeners = new List<TcpListener>();
        private readonly List<TcpClient> clients = new List<TcpClient>();
        private readonly object gate = new object();
        private long lastMessageTicks;
        private int activeSockets;
        private Timer watchdog;
        private bool disposed;

        public CameraAirServer(SharedMemoryState state, int port, Action<string> log)
            : this(state, port, log, false, null) { }

        /// <param name="lan">Listen on every interface instead of loopback only.</param>
        /// <param name="certificate">When set, serve HTTPS/WSS. Browsers only allow camera access on non-localhost pages over HTTPS.</param>
        public CameraAirServer(SharedMemoryState state, int port, Action<string> log, bool lan, X509Certificate2 certificate)
        {
            if (certificate != null && !certificate.HasPrivateKey) throw new ArgumentException("The camera HTTPS certificate has no private key.");
            this.state = state;
            this.port = port;
            this.log = log;
            this.lan = lan;
            this.certificate = certificate;
            pagePath = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "camera", "camera.html");
        }

        private string Scheme { get { return certificate == null ? "http" : "https"; } }

        public string Url { get { return Scheme + "://localhost:" + port + "/"; } }

        /// <summary>URLs other devices can open: one per active IPv4 address of this PC (LAN mode only).</summary>
        public IList<string> LanUrls()
        {
            List<string> urls = new List<string>();
            if (!lan) return urls;
            foreach (NetworkInterface adapter in NetworkInterface.GetAllNetworkInterfaces())
            {
                if (adapter.OperationalStatus != OperationalStatus.Up || adapter.NetworkInterfaceType == NetworkInterfaceType.Loopback) continue;
                foreach (UnicastIPAddressInformation address in adapter.GetIPProperties().UnicastAddresses)
                {
                    if (address.Address.AddressFamily != AddressFamily.InterNetwork) continue;
                    byte[] b = address.Address.GetAddressBytes();
                    if (b[0] == 169 && b[1] == 254) continue;
                    urls.Add(Scheme + "://" + address.Address + ":" + port + "/");
                }
            }
            return urls;
        }

        public static X509Certificate2 LoadCertificate(string path, string password)
        {
            if (!File.Exists(path)) throw new ArgumentException("Camera certificate not found: " + path);
            return new X509Certificate2(path, password ?? String.Empty, X509KeyStorageFlags.UserKeySet);
        }

        public void Start(CancellationToken token)
        {
            if (lan)
            {
                AddListener(IPAddress.Any, true);
                if (Socket.OSSupportsIPv6) AddListener(IPAddress.IPv6Any, false);
            }
            else
            {
                // Browsers may resolve "localhost" to either 127.0.0.1 or ::1, so listen on both loopback addresses.
                AddListener(IPAddress.Loopback, true);
                if (Socket.OSSupportsIPv6) AddListener(IPAddress.IPv6Loopback, false);
            }
            watchdog = new Timer(CheckStale, null, 100, 100);
            token.Register(Dispose);
        }

        private void AddListener(IPAddress address, bool required)
        {
            TcpListener listener = new TcpListener(address, port);
            try
            {
                listener.Start();
            }
            catch (SocketException error)
            {
                if (required) throw new InvalidOperationException("Camera AIR port " + port + " is unavailable: " + error.Message, error);
                return;
            }
            lock (gate) listeners.Add(listener);
            Thread thread = new Thread(delegate() { AcceptLoop(listener); });
            thread.IsBackground = true;
            thread.Name = "CameraAir accept " + address;
            thread.Start();
        }

        public static byte[] DecodeBeams(string message)
        {
            if (message == null) return null;
            message = message.Trim();
            if (message.Length != SharedMemoryState.AirCount) return null;
            byte[] air = new byte[SharedMemoryState.AirCount];
            for (int beam = 0; beam < message.Length; beam++)
            {
                char c = message[beam];
                if (c == '1') air[BeamToByte[beam]] = Pressed;
                else if (c != '0') return null;
            }
            return air;
        }

        internal static string ComputeAccept(string key)
        {
            using (SHA1 sha = SHA1.Create())
            {
                return Convert.ToBase64String(sha.ComputeHash(Encoding.ASCII.GetBytes(key.Trim() + WebSocketGuid)));
            }
        }

        private void AcceptLoop(TcpListener listener)
        {
            while (true)
            {
                TcpClient client;
                try
                {
                    client = listener.AcceptTcpClient();
                }
                catch (Exception error)
                {
                    if (error is SocketException || error is ObjectDisposedException || error is InvalidOperationException) return;
                    throw;
                }
                lock (gate)
                {
                    if (disposed) { client.Close(); return; }
                    clients.Add(client);
                }
                Thread thread = new Thread(delegate() { Handle(client); });
                thread.IsBackground = true;
                thread.Name = "CameraAir client";
                thread.Start();
            }
        }

        private void Handle(TcpClient client)
        {
            try
            {
                client.NoDelay = true;
                NetworkStream network = client.GetStream();
                network.ReadTimeout = 5000;
                network.WriteTimeout = 5000;
                Stream stream = network;
                if (certificate != null)
                {
                    SslStream secure = new SslStream(network, false);
                    secure.AuthenticateAsServer(certificate, false, SslProtocols.Tls12, false);
                    stream = secure;
                }
                string path;
                Dictionary<string, string> headers;
                if (!ReadRequest(stream, out path, out headers)) return;

                if (path == "/ws")
                {
                    string key, upgrade;
                    if (!headers.TryGetValue("sec-websocket-key", out key) || !headers.TryGetValue("upgrade", out upgrade) ||
                        !upgrade.Equals("websocket", StringComparison.OrdinalIgnoreCase))
                    {
                        Respond(stream, 400, "Bad Request", "text/plain", "WebSocket required.");
                        return;
                    }
                    string handshake = "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: " +
                        ComputeAccept(key) + "\r\n\r\n";
                    byte[] bytes = Encoding.ASCII.GetBytes(handshake);
                    stream.Write(bytes, 0, bytes.Length);
                    network.ReadTimeout = Timeout.Infinite;
                    RunSocket(stream);
                    return;
                }
                if (path == "/" || path == "/camera.html")
                {
                    if (!File.Exists(pagePath))
                    {
                        Respond(stream, 500, "Internal Server Error", "text/plain", "Missing " + pagePath);
                        return;
                    }
                    Respond(stream, 200, "OK", "text/html; charset=utf-8", File.ReadAllText(pagePath, Encoding.UTF8));
                    return;
                }
                if (path == "/camera-core.js")
                {
                    // Judging logic shared with the offline benchmark (tools/airbench).
                    string corePath = Path.Combine(Path.GetDirectoryName(pagePath), "camera-core.js");
                    if (!File.Exists(corePath))
                    {
                        Respond(stream, 500, "Internal Server Error", "text/plain", "Missing " + corePath);
                        return;
                    }
                    Respond(stream, 200, "OK", "text/javascript; charset=utf-8", File.ReadAllText(corePath, Encoding.UTF8));
                    return;
                }
                if (path == "/status")
                {
                    byte[] air = state.ReadAir();
                    Respond(stream, 200, "OK", "application/json", "{\"air\":[" + String.Join(",", Array.ConvertAll(air, b => b.ToString())) + "]}");
                    return;
                }
                Respond(stream, 404, "Not Found", "text/plain", "Not found.");
            }
            catch (Exception error)
            {
                if (!(error is IOException) && !(error is SocketException) && !(error is ObjectDisposedException) &&
                    !(error is InvalidDataException) && !(error is AuthenticationException))
                {
                    log("Camera server request failed: " + error.Message);
                }
            }
            finally
            {
                lock (gate) clients.Remove(client);
                client.Close();
            }
        }

        private static bool ReadRequest(Stream stream, out string path, out Dictionary<string, string> headers)
        {
            path = null;
            headers = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            MemoryStream buffer = new MemoryStream();
            int matched = 0;
            while (matched < 4)
            {
                int value = stream.ReadByte();
                if (value < 0) return false;
                buffer.WriteByte((byte)value);
                if (buffer.Length > MaxHeaderBytes) throw new InvalidDataException("Request header too large.");
                matched = (value == (matched % 2 == 0 ? '\r' : '\n')) ? matched + 1 : (value == '\r' ? 1 : 0);
            }
            string[] lines = Encoding.ASCII.GetString(buffer.ToArray()).Split(new string[] { "\r\n" }, StringSplitOptions.RemoveEmptyEntries);
            if (lines.Length == 0) return false;
            string[] requestLine = lines[0].Split(' ');
            if (requestLine.Length < 2 || requestLine[0] != "GET") throw new InvalidDataException("Only GET is supported.");
            path = requestLine[1];
            int query = path.IndexOf('?');
            if (query >= 0) path = path.Substring(0, query);
            for (int i = 1; i < lines.Length; i++)
            {
                int colon = lines[i].IndexOf(':');
                if (colon > 0) headers[lines[i].Substring(0, colon).Trim()] = lines[i].Substring(colon + 1).Trim();
            }
            return true;
        }

        private void RunSocket(Stream stream)
        {
            lock (gate) activeSockets++;
            log("Camera page connected.");
            try
            {
                while (true)
                {
                    int opcode;
                    byte[] payload = ReadFrame(stream, out opcode);
                    if (payload == null || opcode == 0x8)
                    {
                        WriteFrame(stream, 0x8, new byte[0]);
                        return;
                    }
                    if (opcode == 0x9)
                    {
                        WriteFrame(stream, 0xA, payload);
                        continue;
                    }
                    if (opcode != 0x1) continue;
                    byte[] air = DecodeBeams(Encoding.ASCII.GetString(payload));
                    if (air == null) continue;
                    Interlocked.Exchange(ref lastMessageTicks, DateTime.UtcNow.Ticks);
                    state.SetCameraAir(air);
                }
            }
            finally
            {
                bool last;
                lock (gate) last = --activeSockets == 0;
                if (last)
                {
                    Interlocked.Exchange(ref lastMessageTicks, 0);
                    state.ClearCameraAir();
                }
                log("Camera page disconnected; camera AIR released.");
            }
        }

        // Reads one client frame. Clients must mask; fragmented messages are not used by the page and are ignored.
        private static byte[] ReadFrame(Stream stream, out int opcode)
        {
            opcode = 0;
            byte[] head = ReadExact(stream, 2);
            if (head == null) return null;
            bool fin = (head[0] & 0x80) != 0;
            opcode = head[0] & 0x0F;
            bool masked = (head[1] & 0x80) != 0;
            long length = head[1] & 0x7F;
            if (length == 126)
            {
                byte[] ext = ReadExact(stream, 2);
                if (ext == null) return null;
                length = (ext[0] << 8) | ext[1];
            }
            else if (length == 127)
            {
                byte[] ext = ReadExact(stream, 8);
                if (ext == null) return null;
                length = 0;
                for (int i = 0; i < 8; i++) length = (length << 8) | ext[i];
            }
            if (!masked) throw new InvalidDataException("Client frames must be masked.");
            if (length > 4096) throw new InvalidDataException("Frame too large.");
            byte[] mask = ReadExact(stream, 4);
            if (mask == null) return null;
            byte[] payload = ReadExact(stream, (int)length);
            if (payload == null) return null;
            for (int i = 0; i < payload.Length; i++) payload[i] ^= mask[i % 4];
            if (!fin) opcode = 0; // ignore fragments
            return payload;
        }

        private static byte[] ReadExact(Stream stream, int count)
        {
            byte[] data = new byte[count];
            int offset = 0;
            while (offset < count)
            {
                int read = stream.Read(data, offset, count - offset);
                if (read <= 0) return null;
                offset += read;
            }
            return data;
        }

        private static void WriteFrame(Stream stream, int opcode, byte[] payload)
        {
            if (payload.Length > 125) throw new ArgumentException("Control frames are small.");
            byte[] frame = new byte[2 + payload.Length];
            frame[0] = (byte)(0x80 | opcode);
            frame[1] = (byte)payload.Length;
            Buffer.BlockCopy(payload, 0, frame, 2, payload.Length);
            try { stream.Write(frame, 0, frame.Length); }
            catch (IOException) { }
            catch (ObjectDisposedException) { }
        }

        private void CheckStale(object ignored)
        {
            long last = Interlocked.Read(ref lastMessageTicks);
            if (last != 0 && (DateTime.UtcNow.Ticks - last) > TimeSpan.FromMilliseconds(StaleMs).Ticks)
            {
                // The page stopped sending (window throttled, camera frozen): release AIR so it never sticks on.
                Interlocked.Exchange(ref lastMessageTicks, 0);
                state.ClearCameraAir();
            }
        }

        private static void Respond(Stream stream, int status, string reason, string contentType, string body)
        {
            byte[] content = Encoding.UTF8.GetBytes(body);
            string header = "HTTP/1.1 " + status + " " + reason + "\r\nContent-Type: " + contentType + "\r\nContent-Length: " + content.Length +
                "\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n";
            byte[] head = Encoding.ASCII.GetBytes(header);
            stream.Write(head, 0, head.Length);
            stream.Write(content, 0, content.Length);
            stream.Flush();
        }

        public void Dispose()
        {
            TcpListener[] stopListeners;
            TcpClient[] stopClients;
            lock (gate)
            {
                if (disposed) return;
                disposed = true;
                stopListeners = listeners.ToArray();
                stopClients = clients.ToArray();
            }
            if (watchdog != null) watchdog.Dispose();
            foreach (TcpListener listener in stopListeners)
            {
                try { listener.Stop(); }
                catch (SocketException) { }
            }
            foreach (TcpClient client in stopClients)
            {
                try { client.Close(); }
                catch (Exception) { }
            }
            state.ClearCameraAir();
        }
    }
}
