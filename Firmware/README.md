# ESP32 Implant Simulator (Deferred)

The Mac `Streamer` executable emits the same UDP wire protocol defined in `NeuralCore.WireProtocol`.

When hardware is available:

1. Flash ESP32 with a 2MB APP / 2MB LittleFS partition scheme.
2. Copy the prepared `.bin` onto LittleFS.
3. Pin Wi-Fi to Core 0; stream frames from Core 1 at 10 kHz.
4. Point the Telepathy app’s **Live (UDP)** mode at the ESP32 IP.

No application changes should be required if the packet layout remains:

`[u32 magic NRL1][u32 seq][u64 host_time_ns][u16 channels][u16 flags][i16 × channels]`
