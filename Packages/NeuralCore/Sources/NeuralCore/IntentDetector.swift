import Foundation

public enum NeuralIntent: String, Sendable, Codable {
    case none
    case accept
    case reject
}

public struct IntentEvent: Sendable, Equatable {
    public let intent: NeuralIntent
    public let hostTimeNs: UInt64
    public let source: String

    public init(intent: NeuralIntent, hostTimeNs: UInt64, source: String) {
        self.intent = intent
        self.hostTimeNs = hostTimeNs
        self.source = source
    }
}

public final class IntentDetector: @unchecked Sendable {
    private var lastEmitted: NeuralIntent = .none

    public init() {}

    public func detect(flags: UInt16, hostTimeNs: UInt64) -> IntentEvent? {
        let f = WireProtocol.Flags(rawValue: flags)
        let intent: NeuralIntent
        if f.contains(.acceptIntent) {
            intent = .accept
        } else if f.contains(.rejectIntent) {
            intent = .reject
        } else {
            intent = .none
        }
        guard intent != .none, intent != lastEmitted else {
            if intent == .none { lastEmitted = .none }
            return nil
        }
        lastEmitted = intent
        return IntentEvent(intent: intent, hostTimeNs: hostTimeNs, source: "udp-flags")
    }

    public func manual(_ intent: NeuralIntent, hostTimeNs: UInt64 = DispatchTime.now().uptimeNanoseconds) -> IntentEvent {
        IntentEvent(intent: intent, hostTimeNs: hostTimeNs, source: "ui")
    }
}
