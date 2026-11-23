import Foundation
import NeuralCore

public final class SessionReplayer: @unchecked Sendable {
    public let header: SessionFormat.Header
    public let taps: [SessionFormat.TapChunk]
    public let events: [SessionFormat.Event]

    public private(set) var cursorNs: UInt64 = 0
    public var durationNs: UInt64 {
        let tapMax = taps.map(\.hostTimeNs).max() ?? 0
        let eventMax = events.map(\.hostTimeNs).max() ?? 0
        return max(tapMax, eventMax)
    }

    public init(url: URL) throws {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let envelope = try decoder.decode(Envelope.self, from: data)
        header = envelope.header
        taps = envelope.taps
        events = envelope.events
        cursorNs = taps.first?.hostTimeNs ?? 0
    }

    public func seek(to hostTimeNs: UInt64) {
        cursorNs = hostTimeNs
    }

    /// Latest tap snapshot per stage at or before cursor.
    public func tapsAtCursor() -> [StageTapSnapshot] {
        var latest: [DSPStageID: StageTapSnapshot] = [:]
        for chunk in taps where chunk.hostTimeNs <= cursorNs {
            if let snap = chunk.asSnapshot() {
                latest[snap.stage] = snap
            }
        }
        return DSPStageID.allCases.compactMap { latest[$0] }
    }

    public func eventsAtCursor() -> [SessionFormat.Event] {
        events.filter { $0.hostTimeNs <= cursorNs }
    }

    public func scrub(fraction: Double) {
        let f = min(1, max(0, fraction))
        let start = taps.first?.hostTimeNs ?? 0
        cursorNs = start + UInt64(Double(durationNs &- start) * f)
    }

    private struct Envelope: Codable {
        var header: SessionFormat.Header
        var taps: [SessionFormat.TapChunk]
        var events: [SessionFormat.Event]
    }
}
