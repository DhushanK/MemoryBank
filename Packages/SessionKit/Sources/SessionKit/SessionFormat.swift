import Foundation
import NeuralCore

public enum SessionFormat {
    public static let magic: UInt32 = 0x544C5031 // "TLP1"
    public static let version: UInt16 = 1
    public static let fileExtension = "telepathy"

    public struct Header: Codable, Sendable {
        public var magic: UInt32
        public var version: UInt16
        public var channelCount: UInt16
        public var sampleRate: Double
        public var displayRate: Double
        public var startedAt: Date
        public var stages: [String]

        public init(
            channelCount: Int,
            sampleRate: Double,
            displayRate: Double,
            startedAt: Date = Date(),
            stages: [DSPStageID] = DSPStageID.allCases
        ) {
            self.magic = SessionFormat.magic
            self.version = SessionFormat.version
            self.channelCount = UInt16(channelCount)
            self.sampleRate = sampleRate
            self.displayRate = displayRate
            self.startedAt = startedAt
            self.stages = stages.map(\.rawValue)
        }
    }

    public enum EventKind: String, Codable, Sendable {
        case decoder
        case prediction
        case accept
        case reject
        case marker
    }

    public struct Event: Codable, Sendable {
        public var kind: EventKind
        public var hostTimeNs: UInt64
        public var text: String
        public var detail: String?

        public init(kind: EventKind, hostTimeNs: UInt64, text: String, detail: String? = nil) {
            self.kind = kind
            self.hostTimeNs = hostTimeNs
            self.text = text
            self.detail = detail
        }
    }

    public struct TapChunk: Codable, Sendable {
        public var stage: String
        public var hostTimeNs: UInt64
        public var channelCount: Int
        public var frameCount: Int
        public var sampleRate: Double
        public var samples: [Float]

        public init(from snapshot: StageTapSnapshot) {
            stage = snapshot.stage.rawValue
            hostTimeNs = snapshot.hostTimeNs
            channelCount = snapshot.channelCount
            frameCount = snapshot.frameCount
            sampleRate = snapshot.sampleRate
            samples = snapshot.samples
        }

        public func asSnapshot() -> StageTapSnapshot? {
            guard let id = DSPStageID(rawValue: stage) else { return nil }
            return StageTapSnapshot(
                stage: id,
                sampleRate: sampleRate,
                channelCount: channelCount,
                frameCount: frameCount,
                hostTimeNs: hostTimeNs,
                samples: samples
            )
        }
    }
}
