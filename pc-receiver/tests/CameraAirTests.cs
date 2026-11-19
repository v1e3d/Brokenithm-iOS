using System;
using System.Net;
using System.Net.Sockets;
using System.Net.WebSockets;
using System.Text;
using System.Threading;

namespace BrokenithmLan.Tests
{
    internal static class CameraAirTests
    {
        public static void RunAll()
        {
            OptionsParse();
            BeamDecoding();
            AirSourcesMerge();
            LiveWebSocket();
        }

        private static void OptionsParse()
        {
            Assert(BridgeOptions.Parse(new string[0]).CameraPort == 0, "camera is off by default");
            Assert(BridgeOptions.Parse(new string[] { "--camera" }).CameraPort == 8090, "--camera uses port 8090");
            Assert(BridgeOptions.Parse(new string[] { "--camera-port", "9123" }).CameraPort == 9123, "--camera-port");
            bool rejected = false;
            try { BridgeOptions.Parse(new string[] { "--camera-port", "80" }); }
            catch (ArgumentException) { rejected = true; }
            Assert(rejected, "privileged camera port rejected");
            BridgeOptions lan = BridgeOptions.Parse(new string[] { "--camera-lan", "--camera-cert", "c.pfx", "--camera-cert-password", "pw" });
            Assert(lan.CameraLan && lan.CameraPort == 8090 && lan.CameraCertificate == "c.pfx" && lan.CameraCertificatePassword == "pw", "--camera-lan with certificate");
            Assert(!BridgeOptions.Parse(new string[] { "--camera" }).CameraLan, "camera stays on loopback unless --camera-lan");
            bool certWithoutCamera = false;
            try { BridgeOptions.Parse(new string[] { "--camera-cert", "c.pfx" }); }
            catch (ArgumentException) { certWithoutCamera = true; }
            Assert(certWithoutCamera, "--camera-cert alone rejected");
        }

        private static void BeamDecoding()
        {
            byte[] bottom = CameraAirServer.DecodeBeams("100000");
            Assert(bottom[1] == 128 && Sum(bottom) == 128, "beam 1 (lowest) maps to AIR byte 1");
            byte[] top = CameraAirServer.DecodeBeams("000001");
            Assert(top[4] == 128 && Sum(top) == 128, "beam 6 (highest) maps to AIR byte 4");
            byte[] all = CameraAirServer.DecodeBeams("111111\n");
            Assert(Sum(all) == 128 * 6, "all beams");
            Assert(CameraAirServer.DecodeBeams("10000") == null, "short message rejected");
            Assert(CameraAirServer.DecodeBeams("10000x") == null, "invalid character rejected");
        }

        private static void AirSourcesMerge()
        {
            using (SharedMemoryState state = new SharedMemoryState("Local\\BROKENITHM_CAMERA_TEST_" + Guid.NewGuid().ToString("N")))
            {
                byte[] input = new byte[41];
                input[0] = (byte)'I'; input[1] = (byte)'N'; input[2] = (byte)'P';
                input[3] = 128; // iPad AIR byte 0
                state.ApplyInput(input, true);
                state.SetCameraAir(CameraAirServer.DecodeBeams("000001")); // camera AIR byte 4
                byte[] air = state.ReadAir();
                Assert(air[0] == 128 && air[4] == 128, "iPad and camera AIR are combined");

                input[3] = 0;
                state.ApplyInput(input, true);
                air = state.ReadAir();
                Assert(air[0] == 0 && air[4] == 128, "iPad frame does not erase camera AIR");

                state.ClearInputs();
                Assert(state.ReadAir()[4] == 128, "iPad disconnect keeps camera AIR");
                state.ClearCameraAir();
                Assert(Sum(state.ReadAir()) == 0, "camera AIR released");

                input[3] = 128;
                state.ApplyInput(input, true);
                state.ClearCameraAir();
                Assert(state.ReadAir()[0] == 128, "camera release keeps iPad AIR");
            }
        }

        private static void LiveWebSocket()
        {
            int port = FreePort();
            using (SharedMemoryState state = new SharedMemoryState("Local\\BROKENITHM_CAMERA_LIVE_" + Guid.NewGuid().ToString("N")))
            using (CancellationTokenSource stop = new CancellationTokenSource())
            using (CameraAirServer server = new CameraAirServer(state, port, delegate(string message) { }))
            {
                server.Start(stop.Token);
                using (WebClient web = new WebClient())
                {
                    string status = web.DownloadString("http://localhost:" + port + "/status");
                    Assert(status.Contains("\"air\":[0,0,0,0,0,0]"), "status endpoint");
                    if (System.IO.File.Exists(System.IO.Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "camera", "camera.html")))
                    {
                        Assert(web.DownloadString("http://localhost:" + port + "/").Contains("<title>Camera AIR</title>"), "camera page served");
                    }
                    bool notFound = false;
                    try { web.DownloadString("http://localhost:" + port + "/missing"); }
                    catch (WebException) { notFound = true; }
                    Assert(notFound, "unknown path returns an error");
                }

                using (ClientWebSocket socket = new ClientWebSocket())
                {
                    socket.ConnectAsync(new Uri("ws://localhost:" + port + "/ws"), CancellationToken.None).Wait(5000);
                    Assert(socket.State == WebSocketState.Open, "WebSocket connected");
                    Send(socket, "110000");
                    Assert(WaitFor(delegate { byte[] a = state.ReadAir(); return a[1] == 128 && a[0] == 128; }, 2000), "beams 1-2 reach shared memory");

                    // No further messages: the watchdog must release AIR so it never sticks.
                    Assert(WaitFor(delegate { return Sum(state.ReadAir()) == 0; }, 2000), "stale camera AIR released");

                    Send(socket, "000011");
                    Assert(WaitFor(delegate { byte[] a = state.ReadAir(); return a[5] == 128 && a[4] == 128; }, 2000), "beams 5-6 reach shared memory");
                    socket.CloseAsync(WebSocketCloseStatus.NormalClosure, "done", CancellationToken.None).Wait(3000);
                    Assert(WaitFor(delegate { return Sum(state.ReadAir()) == 0; }, 2000), "closing the page releases camera AIR");
                }
                stop.Cancel();
            }
        }

        private static void Send(ClientWebSocket socket, string message)
        {
            byte[] bytes = Encoding.ASCII.GetBytes(message);
            socket.SendAsync(new ArraySegment<byte>(bytes), WebSocketMessageType.Text, true, CancellationToken.None).Wait(3000);
        }

        private static bool WaitFor(Func<bool> condition, int timeoutMs)
        {
            DateTime deadline = DateTime.UtcNow.AddMilliseconds(timeoutMs);
            while (DateTime.UtcNow < deadline)
            {
                if (condition()) return true;
                Thread.Sleep(10);
            }
            return condition();
        }

        private static int FreePort()
        {
            TcpListener probe = new TcpListener(IPAddress.Loopback, 0);
            probe.Start();
            int port = ((IPEndPoint)probe.LocalEndpoint).Port;
            probe.Stop();
            return port;
        }

        private static int Sum(byte[] values)
        {
            int total = 0;
            foreach (byte value in values) total += value;
            return total;
        }

        private static void Assert(bool condition, string message)
        {
            if (!condition) throw new InvalidOperationException("Assertion failed: " + message);
        }
    }
}
