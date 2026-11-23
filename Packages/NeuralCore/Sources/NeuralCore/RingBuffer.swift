import Foundation
import os

/// Single-producer / single-consumer ring of fixed-size neural frames (Int16 samples).
/// Pre-allocated; push/pop never allocate after init.
public final class FrameRingBuffer: @unchecked Sendable {
    public let channelCount: Int
    public let capacityFrames: Int
    private let samples: UnsafeMutablePointer<Int16>
    private let seqs: UnsafeMutablePointer<UInt32>
    private let times: UnsafeMutablePointer<UInt64>
    private let flags: UnsafeMutablePointer<UInt16>
    private var writeIndex: Int = 0
    private var readIndex: Int = 0
    private let lock = OSAllocatedUnfairLock()

    public init(channelCount: Int, capacityFrames: Int) {
        self.channelCount = channelCount
        self.capacityFrames = capacityFrames
        samples = .allocate(capacity: channelCount * capacityFrames)
        samples.initialize(repeating: 0, count: channelCount * capacityFrames)
        seqs = .allocate(capacity: capacityFrames)
        seqs.initialize(repeating: 0, count: capacityFrames)
        times = .allocate(capacity: capacityFrames)
        times.initialize(repeating: 0, count: capacityFrames)
        flags = .allocate(capacity: capacityFrames)
        flags.initialize(repeating: 0, count: capacityFrames)
    }

    deinit {
        samples.deallocate()
        seqs.deallocate()
        times.deallocate()
        flags.deallocate()
    }

    public var count: Int {
        lock.lock()
        defer { lock.unlock() }
        let diff = writeIndex - readIndex
        return diff >= 0 ? diff : diff + capacityFrames
    }

    /// Returns false if full (frame dropped).
    @discardableResult
    public func push(
        samples frameSamples: UnsafePointer<Int16>,
        seq: UInt32,
        hostTimeNs: UInt64,
        flags frameFlags: UInt16
    ) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let next = (writeIndex + 1) % capacityFrames
        if next == readIndex { return false }
        let dest = samples.advanced(by: writeIndex * channelCount)
        dest.update(from: frameSamples, count: channelCount)
        seqs[writeIndex] = seq
        times[writeIndex] = hostTimeNs
        flags[writeIndex] = frameFlags
        writeIndex = next
        return true
    }

    public struct PoppedFrame {
        public let seq: UInt32
        public let hostTimeNs: UInt64
        public let flags: UInt16
        /// Caller must copy out before next pop; points into ring storage.
        public let samples: UnsafePointer<Int16>
    }

    public func pop(into destination: UnsafeMutablePointer<Int16>) -> (seq: UInt32, hostTimeNs: UInt64, flags: UInt16)? {
        lock.lock()
        defer { lock.unlock() }
        if readIndex == writeIndex { return nil }
        let src = samples.advanced(by: readIndex * channelCount)
        destination.update(from: src, count: channelCount)
        let result = (seqs[readIndex], times[readIndex], flags[readIndex])
        readIndex = (readIndex + 1) % capacityFrames
        return result
    }

    /// Copy latest N frames into a contiguous destination (channels interleaved per frame).
    public func copyLatest(frameCount: Int, into destination: UnsafeMutablePointer<Int16>) -> Int {
        lock.lock()
        defer { lock.unlock() }
        let available = writeIndex >= readIndex
            ? writeIndex - readIndex
            : capacityFrames - (readIndex - writeIndex)
        let n = min(frameCount, available)
        guard n > 0 else { return 0 }
        var idx = writeIndex - n
        if idx < 0 { idx += capacityFrames }
        for i in 0..<n {
            let src = samples.advanced(by: idx * channelCount)
            destination.advanced(by: i * channelCount).update(from: src, count: channelCount)
            idx = (idx + 1) % capacityFrames
        }
        return n
    }
}
