import Foundation
import NeuralCore
import Network

struct StreamerConfig {
    var host: String = "127.0.0.1"
    var port: UInt16 = WireProtocol.defaultPort
    var channels: Int = WireProtocol.defaultChannelCount
    var sampleRate: Double = WireProtocol.defaultSampleRate
    var binPath: String = "Samples/synthetic_neural.bin"
    var injectIntents: Bool = true
}

func parseArgs() -> StreamerConfig {
    var cfg = StreamerConfig()
    var args = Array(CommandLine.arguments.dropFirst())
    while let arg = args.first {
        args.removeFirst()
        switch arg {
        case "--host": cfg.host = args.removeFirst()
        case "--port": cfg.port = UInt16(args.removeFirst()) ?? cfg.port
        case "--bin": cfg.binPath = args.removeFirst()
        case "--channels": cfg.channels = Int(args.removeFirst()) ?? cfg.channels
        case "--rate": cfg.sampleRate = Double(args.removeFirst()) ?? cfg.sampleRate
        case "--no-intents": cfg.injectIntents = false
        case "-h", "--help":
            print("""
            Streamer — Mac UDP neural implant simulator
              --bin PATH          Raw int16 .bin (interleaved channels)
              --host ADDR         Default 127.0.0.1
              --port N            Default \(WireProtocol.defaultPort)
              --channels N        Default \(WireProtocol.defaultChannelCount)
              --rate HZ           Default \(Int(WireProtocol.defaultSampleRate))
              --no-intents        Disable periodic Accept/Reject flag injection
            """)
            exit(0)
        default:
            fputs("Unknown arg: \(arg)\n", stderr)
            exit(2)
        }
    }
    return cfg
}

let cfg = parseArgs()
let url = URL(fileURLWithPath: cfg.binPath)
guard let data = try? Data(contentsOf: url), !data.isEmpty else {
    fputs("Failed to read \(cfg.binPath). Run: python3 DatasetPrep/generate_synthetic.py\n", stderr)
    exit(1)
}

let sampleCount = data.count / MemoryLayout<Int16>.size
let frameCount = sampleCount / cfg.channels
guard frameCount > 0 else {
    fputs("Bin too small for \(cfg.channels) channels\n", stderr)
    exit(1)
}

print("Streaming \(frameCount) frames × \(cfg.channels) ch @ \(cfg.sampleRate) Hz → \(cfg.host):\(cfg.port)")

let samples: [Int16] = data.withUnsafeBytes { raw in
    Array(UnsafeBufferPointer(
        start: raw.bindMemory(to: Int16.self).baseAddress!,
        count: sampleCount
    ))
}

let host = NWEndpoint.Host(cfg.host)
let port = NWEndpoint.Port(rawValue: cfg.port)!
let connection = NWConnection(host: host, port: port, using: .udp)
let startGroup = DispatchGroup()
startGroup.enter()
connection.stateUpdateHandler = { state in
    if case .ready = state { startGroup.leave() }
    if case .failed(let error) = state {
        fputs("Connection failed: \(error)\n", stderr)
        exit(1)
    }
}
connection.start(queue: .global(qos: .userInteractive))
_ = startGroup.wait(timeout: .now() + 5)

let packetSize = WireProtocol.packetByteCount(channels: cfg.channels)
var packet = [UInt8](repeating: 0, count: packetSize)
let intervalNs = UInt64(1_000_000_000.0 / cfg.sampleRate)
var seq: UInt32 = 0
var frameIdx = 0
var nextDeadline = DispatchTime.now().uptimeNanoseconds

print("Press Ctrl-C to stop.")

while true {
    let base = frameIdx * cfg.channels
    var flags: UInt16 = 0
    if cfg.injectIntents, seq > 0, seq % 25000 == 0 {
        flags = WireProtocol.Flags.acceptIntent.rawValue
    } else if cfg.injectIntents, seq > 0, seq % 25000 == 12500 {
        flags = WireProtocol.Flags.rejectIntent.rawValue
    }

    let header = WireProtocol.Header(
        seq: seq,
        hostTimeNs: DispatchTime.now().uptimeNanoseconds,
        channelCount: UInt16(cfg.channels),
        flags: flags
    )
    header.encode(into: &packet)

    for c in 0..<cfg.channels {
        var value = samples[base + c].littleEndian
        withUnsafeBytes(of: &value) { raw in
            for i in 0..<2 {
                packet[WireProtocol.Header.byteCount + c * 2 + i] = raw[i]
            }
        }
    }

    connection.send(content: Data(packet), completion: .contentProcessed { _ in })

    seq &+= 1
    frameIdx += 1
    if frameIdx >= frameCount { frameIdx = 0 }

    nextDeadline &+= intervalNs
    let now = DispatchTime.now().uptimeNanoseconds
    if nextDeadline > now {
        let sleepNs = nextDeadline - now
        // Coalesce sleeps for practicality; still aim for average rate.
        if sleepNs > 50_000 {
            nanosecondsSleep(sleepNs)
        }
    } else {
        // Behind schedule — catch up without sleeping.
        nextDeadline = now
    }
}

func nanosecondsSleep(_ ns: UInt64) {
    var ts = timespec(tv_sec: Int(ns / 1_000_000_000), tv_nsec: Int(ns % 1_000_000_000))
    nanosleep(&ts, nil)
}
