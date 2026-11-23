import Foundation
import os

/// Direct-form I biquad (b0,b1,b2 / a1,a2) — avoids brittle vDSP.Biquad generics.
private struct BiquadState {
    var b0: Float, b1: Float, b2: Float, a1: Float, a2: Float
    var x1: Float = 0, x2: Float = 0, y1: Float = 0, y2: Float = 0

    static func bandEmphasis() -> BiquadState {
        // Mild band emphasis approximating action-potential band for demo pipelines.
        BiquadState(b0: 0.2929, b1: 0, b2: -0.2929, a1: 0, a2: 0.4142)
    }

    mutating func process(_ x: Float) -> Float {
        let y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2 = x1; x1 = x
        y2 = y1; y1 = y
        return y
    }
}

public enum DSPStageID: String, CaseIterable, Sendable, Codable {
    case raw
    case bandpass
    case pca
    case spikes
    case rates
}

/// Snapshot of a single DSP stage for UI / session recording (decimated).
public struct StageTapSnapshot: Sendable {
    public let stage: DSPStageID
    public let sampleRate: Double
    public let channelCount: Int
    public let frameCount: Int
    public let hostTimeNs: UInt64
    /// Row-major: frame-major, channel-minor floats.
    public let samples: [Float]

    public init(
        stage: DSPStageID,
        sampleRate: Double,
        channelCount: Int,
        frameCount: Int,
        hostTimeNs: UInt64,
        samples: [Float]
    ) {
        self.stage = stage
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.frameCount = frameCount
        self.hostTimeNs = hostTimeNs
        self.samples = samples
    }

    public func channelSeries(_ channel: Int) -> [Float] {
        guard channel >= 0, channel < channelCount else { return [] }
        var out = [Float](repeating: 0, count: frameCount)
        for f in 0..<frameCount {
            out[f] = samples[f * channelCount + channel]
        }
        return out
    }
}

/// Pre-allocated double-buffer tap published after each DSP stage.
public final class StageTap: @unchecked Sendable {
    public let stage: DSPStageID
    public let channelCount: Int
    public let capacityFrames: Int
    public let sampleRate: Double

    private var buffers: [UnsafeMutablePointer<Float>]
    private var active: Int = 0
    private var publishedFrames: Int = 0
    private var publishedTime: UInt64 = 0
    private let lock = OSAllocatedUnfairLock()

    public init(stage: DSPStageID, channelCount: Int, capacityFrames: Int, sampleRate: Double) {
        self.stage = stage
        self.channelCount = channelCount
        self.capacityFrames = capacityFrames
        self.sampleRate = sampleRate
        buffers = [
            .allocate(capacity: channelCount * capacityFrames),
            .allocate(capacity: channelCount * capacityFrames)
        ]
        buffers[0].initialize(repeating: 0, count: channelCount * capacityFrames)
        buffers[1].initialize(repeating: 0, count: channelCount * capacityFrames)
    }

    deinit {
        buffers[0].deallocate()
        buffers[1].deallocate()
    }

    /// Writer side: fill inactive buffer then publish.
    public func publish(frameCount: Int, hostTimeNs: UInt64, fill: (UnsafeMutablePointer<Float>) -> Void) {
        let writeIdx = 1 - active
        let count = min(frameCount, capacityFrames)
        fill(buffers[writeIdx])
        lock.lock()
        active = writeIdx
        publishedFrames = count
        publishedTime = hostTimeNs
        lock.unlock()
    }

    public func snapshot() -> StageTapSnapshot {
        lock.lock()
        let frames = publishedFrames
        let ptr = buffers[active]
        let total = frames * channelCount
        let array = Array(UnsafeBufferPointer(start: ptr, count: total))
        let time = publishedTime
        lock.unlock()
        return StageTapSnapshot(
            stage: stage,
            sampleRate: sampleRate,
            channelCount: channelCount,
            frameCount: frames,
            hostTimeNs: time,
            samples: array
        )
    }
}

/// Biquad bandpass + PCA-ish projection + simple spike/rate extraction.
public final class DSPPipeline: @unchecked Sendable {
    public let channelCount: Int
    public let sampleRate: Double
    public let displayRate: Double

    public let rawTap: StageTap
    public let bandpassTap: StageTap
    public let pcaTap: StageTap
    public let spikesTap: StageTap
    public let ratesTap: StageTap

    public var taps: [StageTap] { [rawTap, bandpassTap, pcaTap, spikesTap, ratesTap] }

    private let windowFrames: Int
    private let workRaw: UnsafeMutablePointer<Float>
    private let workBP: UnsafeMutablePointer<Float>
    private let workPCA: UnsafeMutablePointer<Float>
    private let workSpikes: UnsafeMutablePointer<Float>
    private let workRates: UnsafeMutablePointer<Float>
    private var filters: [BiquadState]
    private var frameCursor: Int = 0
    private let decimateEvery: Int

    public init(
        channelCount: Int = WireProtocol.defaultChannelCount,
        sampleRate: Double = WireProtocol.defaultSampleRate,
        windowSeconds: Double = 0.25,
        displayRate: Double = 1_000
    ) {
        self.channelCount = channelCount
        self.sampleRate = sampleRate
        self.displayRate = displayRate
        self.windowFrames = max(64, Int(sampleRate * windowSeconds))
        self.decimateEvery = max(1, Int(sampleRate / displayRate))

        let tapCapacity = max(64, Int(displayRate * windowSeconds))
        rawTap = StageTap(stage: .raw, channelCount: channelCount, capacityFrames: tapCapacity, sampleRate: displayRate)
        bandpassTap = StageTap(stage: .bandpass, channelCount: channelCount, capacityFrames: tapCapacity, sampleRate: displayRate)
        pcaTap = StageTap(stage: .pca, channelCount: min(8, channelCount), capacityFrames: tapCapacity, sampleRate: displayRate)
        spikesTap = StageTap(stage: .spikes, channelCount: channelCount, capacityFrames: tapCapacity, sampleRate: displayRate)
        ratesTap = StageTap(stage: .rates, channelCount: channelCount, capacityFrames: tapCapacity, sampleRate: displayRate)

        let total = channelCount * windowFrames
        workRaw = .allocate(capacity: total)
        workBP = .allocate(capacity: total)
        workPCA = .allocate(capacity: min(8, channelCount) * windowFrames)
        workSpikes = .allocate(capacity: total)
        workRates = .allocate(capacity: total)
        workRaw.initialize(repeating: 0, count: total)
        workBP.initialize(repeating: 0, count: total)
        workPCA.initialize(repeating: 0, count: min(8, channelCount) * windowFrames)
        workSpikes.initialize(repeating: 0, count: total)
        workRates.initialize(repeating: 0, count: total)

        filters = (0..<channelCount).map { _ in BiquadState.bandEmphasis() }
    }

    deinit {
        workRaw.deallocate()
        workBP.deallocate()
        workPCA.deallocate()
        workSpikes.deallocate()
        workRates.deallocate()
    }

    /// Ingest one Int16 frame; returns spike-rate feature vector for decoder when window advances.
    @discardableResult
    public func processFrame(
        samples: UnsafePointer<Int16>,
        hostTimeNs: UInt64
    ) -> [Float]? {
        let idx = frameCursor % windowFrames
        for c in 0..<channelCount {
            workRaw[idx * channelCount + c] = Float(samples[c]) / Float(Int16.max)
        }
        frameCursor += 1

        // Run bandpass on the newest sample per channel (streaming).
        for c in 0..<channelCount {
            let input = workRaw[idx * channelCount + c]
            workBP[idx * channelCount + c] = filters[c].process(input)
        }

        // Publish decimated taps periodically.
        if frameCursor % decimateEvery == 0 {
            publishDecimatedTaps(hostTimeNs: hostTimeNs)
        }

        // Emit features once per full window.
        guard frameCursor % windowFrames == 0 else { return nil }
        computePCAAndSpikes()
        return averageRates()
    }

    private func publishDecimatedTaps(hostTimeNs: UInt64) {
        let tapFrames = rawTap.capacityFrames
        let start = max(0, windowFrames - tapFrames * decimateEvery)

        rawTap.publish(frameCount: tapFrames, hostTimeNs: hostTimeNs) { dest in
            writeDecimated(from: workRaw, into: dest, start: start, tapFrames: tapFrames, channels: channelCount)
        }
        bandpassTap.publish(frameCount: tapFrames, hostTimeNs: hostTimeNs) { dest in
            writeDecimated(from: workBP, into: dest, start: start, tapFrames: tapFrames, channels: channelCount)
        }
        pcaTap.publish(frameCount: tapFrames, hostTimeNs: hostTimeNs) { dest in
            writeDecimated(from: workPCA, into: dest, start: start, tapFrames: tapFrames, channels: min(8, channelCount))
        }
        spikesTap.publish(frameCount: tapFrames, hostTimeNs: hostTimeNs) { dest in
            writeDecimated(from: workSpikes, into: dest, start: start, tapFrames: tapFrames, channels: channelCount)
        }
        ratesTap.publish(frameCount: tapFrames, hostTimeNs: hostTimeNs) { dest in
            writeDecimated(from: workRates, into: dest, start: start, tapFrames: tapFrames, channels: channelCount)
        }
    }

    private func writeDecimated(
        from source: UnsafeMutablePointer<Float>,
        into dest: UnsafeMutablePointer<Float>,
        start: Int,
        tapFrames: Int,
        channels: Int
    ) {
        for t in 0..<tapFrames {
            let srcFrame = min(windowFrames - 1, start + t * decimateEvery)
            for c in 0..<channels {
                dest[t * channels + c] = source[srcFrame * channels + c]
            }
        }
    }

    private func computePCAAndSpikes() {
        let comps = min(8, channelCount)
        // Demo PCA: project onto first `comps` channels after energy normalize (stable without LAPACK fit).
        for f in 0..<windowFrames {
            var energy: Float = 0
            for c in 0..<channelCount {
                let v = workBP[f * channelCount + c]
                energy += v * v
            }
            let norm = max(sqrt(energy), 1e-6)
            for k in 0..<comps {
                workPCA[f * comps + k] = workBP[f * channelCount + k] / norm
            }
            for c in 0..<channelCount {
                let v = abs(workBP[f * channelCount + c])
                let spike: Float = v > 0.35 ? 1.0 : 0.0
                workSpikes[f * channelCount + c] = spike
            }
        }
        // Rate: moving sum of spikes over ~20 ms.
        let bin = max(1, Int(sampleRate * 0.02))
        for c in 0..<channelCount {
            var running: Float = 0
            for f in 0..<windowFrames {
                running += workSpikes[f * channelCount + c]
                if f >= bin {
                    running -= workSpikes[(f - bin) * channelCount + c]
                }
                workRates[f * channelCount + c] = running / Float(bin)
            }
        }
    }

    private func averageRates() -> [Float] {
        var out = [Float](repeating: 0, count: channelCount)
        for c in 0..<channelCount {
            var sum: Float = 0
            for f in 0..<windowFrames {
                sum += workRates[f * channelCount + c]
            }
            out[c] = sum / Float(windowFrames)
        }
        return out
    }
}
