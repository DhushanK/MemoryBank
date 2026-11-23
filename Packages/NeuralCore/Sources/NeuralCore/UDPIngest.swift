import Foundation
import Network
import os

public protocol FrameSink: AnyObject {
    func receiveFrame(
        samples: UnsafePointer<Int16>,
        channelCount: Int,
        seq: UInt32,
        hostTimeNs: UInt64,
        flags: UInt16
    )
}

/// Zero-allocation steady-state UDP listener using Network.framework.
public final class UDPIngest: @unchecked Sendable {
    public let port: UInt16
    public let channelCount: Int

    private var listener: NWListener?
    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "neural.udp.ingest", qos: .userInteractive)
    private weak var sink: FrameSink?
    private var packetBuffer: UnsafeMutableRawPointer
    private let packetCapacity: Int
    private let log = Logger(subsystem: "TelepathyEngine", category: "UDPIngest")
    private var scratchSamples: UnsafeMutablePointer<Int16>

    public private(set) var packetsReceived: UInt64 = 0
    public private(set) var packetsDropped: UInt64 = 0

    public init(port: UInt16 = WireProtocol.defaultPort, channelCount: Int = WireProtocol.defaultChannelCount) {
        self.port = port
        self.channelCount = channelCount
        packetCapacity = WireProtocol.packetByteCount(channels: channelCount) + 64
        packetBuffer = .allocate(byteCount: packetCapacity, alignment: 8)
        scratchSamples = .allocate(capacity: channelCount)
        scratchSamples.initialize(repeating: 0, count: channelCount)
    }

    deinit {
        stop()
        packetBuffer.deallocate()
        scratchSamples.deallocate()
    }

    public func start(sink: FrameSink) throws {
        self.sink = sink
        let params = NWParameters.udp
        params.allowLocalEndpointReuse = true
        listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
        listener?.newConnectionHandler = { [weak self] conn in
            self?.handle(connection: conn)
        }
        listener?.stateUpdateHandler = { [weak self] state in
            self?.log.debug("listener state: \(String(describing: state))")
        }
        listener?.start(queue: queue)
    }

    public func stop() {
        connection?.cancel()
        connection = nil
        listener?.cancel()
        listener = nil
    }

    private func handle(connection: NWConnection) {
        self.connection?.cancel()
        self.connection = connection
        connection.start(queue: queue)
        receiveNext(on: connection)
    }

    private func receiveNext(on connection: NWConnection) {
        connection.receiveMessage { [weak self] data, _, _, error in
            guard let self else { return }
            if let data {
                self.parse(data)
            }
            if error == nil {
                self.receiveNext(on: connection)
            }
        }
    }

    private func parse(_ data: Data) {
        let needed = WireProtocol.Header.byteCount + channelCount * MemoryLayout<Int16>.size
        guard data.count >= needed else {
            packetsDropped += 1
            return
        }
        let parsed: WireProtocol.Header? = data.withUnsafeBytes { raw in
            WireProtocol.Header.decode(from: raw)
        }
        guard let header = parsed, Int(header.channelCount) == channelCount else {
            packetsDropped += 1
            return
        }
        data.withUnsafeBytes { raw in
            let sampleBytes = raw.baseAddress!.advanced(by: WireProtocol.Header.byteCount)
            let samplePtr = sampleBytes.assumingMemoryBound(to: Int16.self)
            // Copy into scratch to normalize endianness if needed (LE assumed).
            for i in 0..<channelCount {
                scratchSamples[i] = Int16(littleEndian: samplePtr[i])
            }
            packetsReceived += 1
            sink?.receiveFrame(
                samples: UnsafePointer(scratchSamples),
                channelCount: channelCount,
                seq: header.seq,
                hostTimeNs: header.hostTimeNs,
                flags: header.flags
            )
        }
    }
}
