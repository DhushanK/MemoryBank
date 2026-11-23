import XCTest
@testable import NeuralCore

final class WireProtocolTests: XCTestCase {
    func testHeaderRoundTrip() {
        var buffer = [UInt8](repeating: 0, count: WireProtocol.Header.byteCount)
        let header = WireProtocol.Header(
            seq: 42,
            hostTimeNs: 1_234_567_890,
            channelCount: 64,
            flags: WireProtocol.Flags.acceptIntent.rawValue
        )
        header.encode(into: &buffer)
        let decoded = buffer.withUnsafeBytes { WireProtocol.Header.decode(from: $0) }
        XCTAssertEqual(decoded?.seq, 42)
        XCTAssertEqual(decoded?.channelCount, 64)
        XCTAssertEqual(decoded?.flags, WireProtocol.Flags.acceptIntent.rawValue)
    }

    func testRingPushPop() {
        let ring = FrameRingBuffer(channelCount: 4, capacityFrames: 8)
        var frame = [Int16](repeating: 0, count: 4)
        frame[0] = 7
        XCTAssertTrue(frame.withUnsafeBufferPointer { ring.push(samples: $0.baseAddress!, seq: 1, hostTimeNs: 10, flags: 0) })
        var out = [Int16](repeating: 0, count: 4)
        let meta = out.withUnsafeMutableBufferPointer { ring.pop(into: $0.baseAddress!) }
        XCTAssertEqual(meta?.seq, 1)
        XCTAssertEqual(out[0], 7)
    }

    func testNoisyDecoderCorrupt() {
        let noisy = NoisyDecoder.corrupt("Meeting at 4", seed: 99)
        XCTAssertFalse(noisy.isEmpty)
    }
}
