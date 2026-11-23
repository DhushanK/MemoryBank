import Foundation
import os

public protocol PipelineEngineDelegate: AnyObject {
    func engineDidEmit(_ emission: DecoderEmission)
    func engineDidDetect(_ intent: IntentEvent)
    func engineDidUpdateTaps(_ taps: [StageTapSnapshot])
    func engineDidIngest(seq: UInt32, hostTimeNs: UInt64)
}

/// Orchestrates ring → DSP → decoder → intent on a dedicated processing queue.
public final class PipelineEngine: FrameSink {
    public let ring: FrameRingBuffer
    public let dsp: DSPPipeline
    public let decoder: NoisyDecoder
    public let intentDetector: IntentDetector

    public weak var delegate: PipelineEngineDelegate?

    private let processQueue = DispatchQueue(label: "neural.dsp", qos: .userInteractive)
    private var running = false
    private var scratch: UnsafeMutablePointer<Int16>
    private let channelCount: Int
    private var lastTapPublish = DispatchTime.now()
    private let tapPublishInterval: Double = 1.0 / 30.0

    public private(set) var framesProcessed: UInt64 = 0
    public private(set) var lastLatencyNs: UInt64 = 0

    public init(
        channelCount: Int = WireProtocol.defaultChannelCount,
        ringCapacity: Int = 4096
    ) {
        self.channelCount = channelCount
        ring = FrameRingBuffer(channelCount: channelCount, capacityFrames: ringCapacity)
        dsp = DSPPipeline(channelCount: channelCount)
        decoder = NoisyDecoder()
        intentDetector = IntentDetector()
        scratch = .allocate(capacity: channelCount)
        scratch.initialize(repeating: 0, count: channelCount)
    }

    deinit {
        stop()
        scratch.deallocate()
    }

    public func start() {
        running = true
        processQueue.async { [weak self] in self?.drainLoop() }
    }

    public func stop() {
        running = false
    }

    public func receiveFrame(
        samples: UnsafePointer<Int16>,
        channelCount: Int,
        seq: UInt32,
        hostTimeNs: UInt64,
        flags: UInt16
    ) {
        _ = ring.push(samples: samples, seq: seq, hostTimeNs: hostTimeNs, flags: flags)
        delegate?.engineDidIngest(seq: seq, hostTimeNs: hostTimeNs)
    }

    /// Inject a synthetic frame (unit tests / local file playback).
    public func inject(
        samples: [Int16],
        seq: UInt32,
        hostTimeNs: UInt64,
        flags: UInt16 = 0
    ) {
        samples.withUnsafeBufferPointer { buf in
            guard let base = buf.baseAddress else { return }
            receiveFrame(
                samples: base,
                channelCount: channelCount,
                seq: seq,
                hostTimeNs: hostTimeNs,
                flags: flags
            )
        }
    }

    private func drainLoop() {
        while running {
            var worked = false
            while let meta = ring.pop(into: scratch) {
                worked = true
                let now = DispatchTime.now().uptimeNanoseconds
                if meta.hostTimeNs > 0, now > meta.hostTimeNs {
                    lastLatencyNs = now &- meta.hostTimeNs
                }
                if let rates = dsp.processFrame(samples: UnsafePointer(scratch), hostTimeNs: meta.hostTimeNs) {
                    let emission = decoder.decode(rates: rates, hostTimeNs: meta.hostTimeNs)
                    DispatchQueue.main.async { [weak self] in
                        self?.delegate?.engineDidEmit(emission)
                    }
                }
                if let intent = intentDetector.detect(flags: meta.flags, hostTimeNs: meta.hostTimeNs) {
                    DispatchQueue.main.async { [weak self] in
                        self?.delegate?.engineDidDetect(intent)
                    }
                }
                framesProcessed += 1
            }

            let elapsed = DispatchTime.now().uptimeNanoseconds &- lastTapPublish.uptimeNanoseconds
            if Double(elapsed) / 1e9 >= tapPublishInterval {
                lastTapPublish = .now()
                let snaps = dsp.taps.map { $0.snapshot() }
                DispatchQueue.main.async { [weak self] in
                    self?.delegate?.engineDidUpdateTaps(snaps)
                }
            }

            if !worked {
                Thread.sleep(forTimeInterval: 0.0005)
            }
        }
    }
}
