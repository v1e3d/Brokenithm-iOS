using System;
using System.IO.MemoryMappedFiles;

namespace BrokenithmLan
{
    internal sealed class SharedMemoryState : IDisposable
    {
        public const string DefaultName = "Local\\BROKENITHM_SHARED_BUFFER";
        public const int AirCount = 6;
        private readonly object gate = new object();
        private readonly MemoryMappedFile mapping;
        private readonly MemoryMappedViewAccessor accessor;
        // AIR bytes 0-5 are the OR of the iPad touch AIR and the camera AIR, so neither source overwrites the other.
        private readonly byte[] deviceAir = new byte[AirCount];
        private readonly byte[] cameraAir = new byte[AirCount];
        private bool disposed;

        public SharedMemoryState(string name)
        {
            mapping = MemoryMappedFile.CreateOrOpen(name, 1024, MemoryMappedFileAccess.ReadWrite);
            try
            {
                accessor = mapping.CreateViewAccessor(0, 150, MemoryMappedFileAccess.ReadWrite);
            }
            catch
            {
                mapping.Dispose();
                throw;
            }
        }

        public void ClearInputs()
        {
            lock (gate)
            {
                if (disposed) return;
                Array.Clear(deviceAir, 0, AirCount);
                WriteAir();
                for (int i = AirCount; i < 38; i++) accessor.Write(i, (byte)0);
                for (int i = 134; i < 138; i++) accessor.Write(i, (byte)0);
            }
        }

        public void ClearAir()
        {
            lock (gate)
            {
                if (disposed) return;
                Array.Clear(deviceAir, 0, AirCount);
                WriteAir();
            }
        }

        public void ApplyInput(byte[] payload, bool airEnabled)
        {
            lock (gate)
            {
                if (disposed) return;
                for (int i = 0; i < AirCount; i++) deviceAir[i] = airEnabled ? payload[3 + i] : (byte)0;
                WriteAir();
                accessor.WriteArray(6, payload, 9, 32);
                for (int i = 41; i < payload.Length; i++) accessor.Write(134 + i - 41, payload[i]);
            }
        }

        /// <summary>Sets the camera AIR state. Values are raw shared-memory bytes (0 or 128) in shared-memory order.</summary>
        public void SetCameraAir(byte[] air)
        {
            if (air == null || air.Length != AirCount) throw new ArgumentException("Camera AIR must contain six bytes.");
            lock (gate)
            {
                if (disposed) return;
                Buffer.BlockCopy(air, 0, cameraAir, 0, AirCount);
                WriteAir();
            }
        }

        public void ClearCameraAir()
        {
            lock (gate)
            {
                if (disposed) return;
                Array.Clear(cameraAir, 0, AirCount);
                WriteAir();
            }
        }

        public byte[] ReadAir()
        {
            byte[] air = new byte[AirCount];
            lock (gate)
            {
                accessor.ReadArray(0, air, 0, AirCount);
            }
            return air;
        }

        public void TriggerFunction(byte function)
        {
            lock (gate)
            {
                if (disposed) return;
                accessor.Write(function == 1 ? 136 : 137, (byte)1);
            }
        }

        public byte[] ReadLeds()
        {
            byte[] leds = new byte[96];
            lock (gate)
            {
                accessor.ReadArray(38, leds, 0, leds.Length);
            }
            return leds;
        }

        private void WriteAir()
        {
            for (int i = 0; i < AirCount; i++) accessor.Write(i, (byte)(deviceAir[i] | cameraAir[i]));
        }

        public void Dispose()
        {
            lock (gate)
            {
                if (disposed) return;
                Array.Clear(cameraAir, 0, AirCount);
                Array.Clear(deviceAir, 0, AirCount);
                WriteAir();
                for (int i = AirCount; i < 38; i++) accessor.Write(i, (byte)0);
                for (int i = 134; i < 138; i++) accessor.Write(i, (byte)0);
                disposed = true;
                accessor.Dispose();
                mapping.Dispose();
            }
        }
    }
}
