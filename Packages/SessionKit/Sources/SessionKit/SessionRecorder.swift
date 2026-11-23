import Foundation
import NeuralCore

/// Append-only session writer. Safe to call from a background I/O queue.
public final class SessionRecorder: @unchecked Sendable {
    public let url: URL
    private let ioQueue = DispatchQueue(label: "session.recorder.io", qos: .utility)
    private var tapChunks: [SessionFormat.TapChunk] = []
    private var events: [SessionFormat.Event] = []
    private let header: SessionFormat.Header
    private var closed = false
    private let lock = NSLock()

    public init(url: URL, header: SessionFormat.Header) throws {
        self.url = url
        self.header = header
        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        FileManager.default.createFile(atPath: url.path, contents: nil)
    }

    public func record(taps: [StageTapSnapshot]) {
        lock.lock()
        guard !closed else { lock.unlock(); return }
        let chunks = taps.map { SessionFormat.TapChunk(from: $0) }
        lock.unlock()
        ioQueue.async { [weak self] in
            self?.tapChunks.append(contentsOf: chunks)
        }
    }

    public func record(event: SessionFormat.Event) {
        ioQueue.async { [weak self] in
            self?.events.append(event)
        }
    }

    public func record(emission: DecoderEmission) {
        record(event: .init(
            kind: .decoder,
            hostTimeNs: emission.hostTimeNs,
            text: emission.noisyText,
            detail: emission.groundTruth
        ))
    }

    public func record(intent: IntentEvent) {
        let kind: SessionFormat.EventKind = intent.intent == .accept ? .accept : .reject
        record(event: .init(
            kind: kind,
            hostTimeNs: intent.hostTimeNs,
            text: intent.intent.rawValue,
            detail: intent.source
        ))
    }

    public func close() throws {
        lock.lock()
        closed = true
        lock.unlock()
        let payload = try ioQueue.sync { () -> Data in
            let envelope = Envelope(header: header, taps: tapChunks, events: events)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.sortedKeys]
            return try encoder.encode(envelope)
        }
        try payload.write(to: url, options: .atomic)
    }

    private struct Envelope: Codable {
        var header: SessionFormat.Header
        var taps: [SessionFormat.TapChunk]
        var events: [SessionFormat.Event]
    }
}
