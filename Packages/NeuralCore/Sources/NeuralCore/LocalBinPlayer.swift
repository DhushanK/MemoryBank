import Foundation

/// Plays an interleaved int16 .bin into a FrameSink at a target sample rate (no network).
public final class LocalBinPlayer: @unchecked Sendable {
    private let samples: [Int16]
    private let channelCount: Int
    private let sampleRate: Double
    private let frameCount: Int
    private weak var sink: FrameSink?
    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "neural.local.player", qos: .userInteractive)
    private var frameIdx: Int = 0
    private var seq: UInt32 = 0
    private var scratch: UnsafeMutablePointer<Int16>
    public var injectIntents: Bool = true

    public init(url: URL, channelCount: Int = WireProtocol.defaultChannelCount, sampleRate: Double = WireProtocol.defaultSampleRate) throws {
        let data = try Data(contentsOf: url)
        let count = data.count / MemoryLayout<Int16>.size
        self.samples = data.withUnsafeBytes { raw in
            Array(UnsafeBufferPointer(start: raw.bindMemory(to: Int16.self).baseAddress!, count: count))
        }
        self.channelCount = channelCount
        self.sampleRate = sampleRate
        self.frameCount = max(1, count / channelCount)
        scratch = .allocate(capacity: channelCount)
        scratch.initialize(repeating: 0, count: channelCount)
    }

    deinit {
        stop()
        scratch.deallocate()
    }

    public func start(sink: FrameSink) {
        self.sink = sink
        let timer = DispatchSource.makeTimerSource(queue: queue)
        // Batch frames per tick to keep CPU sane while approximating rate.
        let batch = max(1, Int(sampleRate / 200)) // 200 Hz timer ≈ full rate via batches
        let interval = Double(batch) / sampleRate
        timer.schedule(deadline: .now(), repeating: interval)
        timer.setEventHandler { [weak self] in
            self?.emit(batch: batch)
        }
        self.timer = timer
        timer.resume()
    }

    public func stop() {
        timer?.cancel()
        timer = nil
    }

    private func emit(batch: Int) {
        guard let sink else { return }
        for _ in 0..<batch {
            let base = frameIdx * channelCount
            for c in 0..<channelCount {
                scratch[c] = samples[base + c]
            }
            var flags: UInt16 = 0
            if injectIntents, seq > 0, seq % 25000 == 0 {
                flags = WireProtocol.Flags.acceptIntent.rawValue
            } else if injectIntents, seq > 0, seq % 25000 == 12500 {
                flags = WireProtocol.Flags.rejectIntent.rawValue
            }
            sink.receiveFrame(
                samples: UnsafePointer(scratch),
                channelCount: channelCount,
                seq: seq,
                hostTimeNs: DispatchTime.now().uptimeNanoseconds,
                flags: flags
            )
            seq &+= 1
            frameIdx += 1
            if frameIdx >= frameCount { frameIdx = 0 }
        }
    }
}
