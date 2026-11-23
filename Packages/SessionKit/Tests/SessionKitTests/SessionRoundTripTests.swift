import XCTest
import NeuralCore
@testable import SessionKit

final class SessionRoundTripTests: XCTestCase {
    func testRecordAndReplay() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-\(UUID().uuidString).telepathy")
        let header = SessionFormat.Header(channelCount: 4, sampleRate: 1000, displayRate: 100)
        let recorder = try SessionRecorder(url: url, header: header)
        let snap = StageTapSnapshot(
            stage: .bandpass,
            sampleRate: 100,
            channelCount: 4,
            frameCount: 2,
            hostTimeNs: 100,
            samples: [0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8]
        )
        recorder.record(taps: [snap])
        recorder.record(event: .init(kind: .decoder, hostTimeNs: 100, text: "Mting a 4"))
        try recorder.close()

        let replayer = try SessionReplayer(url: url)
        replayer.seek(to: 100)
        let taps = replayer.tapsAtCursor()
        XCTAssertEqual(taps.count, 1)
        XCTAssertEqual(taps[0].stage, .bandpass)
        XCTAssertEqual(replayer.eventsAtCursor().first?.text, "Mting a 4")
        try? FileManager.default.removeItem(at: url)
    }
}
