import Foundation
import SwiftUI
import Combine
import NeuralCore
import SessionKit
import MemoryBankKit
import LLMBridge

@MainActor
final class EngineViewModel: ObservableObject {
    enum Mode: String, CaseIterable, Identifiable {
        case liveLocal = "Live (Local Bin)"
        case liveUDP = "Live (UDP)"
        case replay = "Replay Session"
        var id: String { rawValue }
    }

    @Published var mode: Mode = .liveLocal
    @Published var selectedStage: DSPStageID = .bandpass
    @Published var stageSnapshots: [DSPStageID: StageTapSnapshot] = [:]
    @Published var noisyText: String = ""
    @Published var prediction: PredictionPayload?
    @Published var committedText: String = ""
    @Published var status: String = "Idle"
    @Published var packets: UInt64 = 0
    @Published var latencyMs: Double = 0
    @Published var isRecording = false
    @Published var isStreaming = false
    @Published var flashAccept = false
    @Published var flashReject = false
    @Published var replayFraction: Double = 0
    @Published var availableChannels: Int = 8
    @Published var dataSourceLabel: String = "Synthetic (generated locally)"

    let engine = PipelineEngine()
    let suggestions = SuggestionEngine()
    private var ingest: UDPIngest?
    private var localPlayer: LocalBinPlayer?
    private var recorder: SessionRecorder?
    private var replayer: SessionReplayer?
    private var tapThrottle: Date = .distantPast

    func bootstrap() {
        loadSeedMemory()
        engine.delegate = self
        engine.start()
        status = "Ready — choose Live or Replay"
    }

    func loadSeedMemory() {
        let candidates = [
            Bundle.main.url(forResource: "seed_memory", withExtension: "json"),
            URL(fileURLWithPath: "Samples/context/seed_memory.json"),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("Samples/context/seed_memory.json")
        ]
        for url in candidates {
            guard let url, FileManager.default.fileExists(atPath: url.path) else { continue }
            do {
                try suggestions.memory.seedFromJSON(at: url)
                status = "Memory loaded from \(url.lastPathComponent)"
                return
            } catch {
                continue
            }
        }
        suggestions.memory.seed([
            ContextDocument(source: "Calendar", title: "Meeting at 4", body: "Design Review at 4:00 PM"),
            ContextDocument(source: "Notes", title: "Send the design notes", body: "Send architecture notes")
        ])
        status = "Memory seeded with built-in defaults"
    }

    func startLiveLocal() {
        stopSources()
        mode = .liveLocal
        do {
            let url = try resolveBinURL()
            let player = try LocalBinPlayer(url: url)
            localPlayer = player
            player.start(sink: engine)
            isStreaming = true
            dataSourceLabel = "Synthetic file: \(url.lastPathComponent)"
            status = "Playing \(url.lastPathComponent)"
        } catch {
            isStreaming = false
            status = "Local bin error: \(error.localizedDescription)"
        }
    }

    func startLiveUDP() {
        stopSources()
        mode = .liveUDP
        do {
            let udp = UDPIngest()
            try udp.start(sink: engine)
            ingest = udp
            isStreaming = true
            dataSourceLabel = "UDP stream (expect synthetic Streamer .bin)"
            status = "Listening UDP :\(WireProtocol.defaultPort)"
        } catch {
            isStreaming = false
            status = "UDP error: \(error.localizedDescription)"
        }
    }

    func stopLive() {
        if isRecording { stopRecording() }
        stopSources()
        isStreaming = false
        status = "Stopped"
    }

    func startRecording() {
        do {
            let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let url = dir.appendingPathComponent("session-\(Int(Date().timeIntervalSince1970)).telepathy")
            let header = SessionFormat.Header(
                channelCount: WireProtocol.defaultChannelCount,
                sampleRate: WireProtocol.defaultSampleRate,
                displayRate: 1000
            )
            recorder = try SessionRecorder(url: url, header: header)
            isRecording = true
            status = "Recording → \(url.lastPathComponent)"
        } catch {
            status = "Record failed: \(error.localizedDescription)"
        }
    }

    func stopRecording() {
        do {
            try recorder?.close()
            if let url = recorder?.url {
                status = "Saved \(url.lastPathComponent)"
            }
        } catch {
            status = "Save failed: \(error.localizedDescription)"
        }
        recorder = nil
        isRecording = false
    }

    func loadLatestReplay() {
        stopLive()
        mode = .replay
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        let sessions = files.filter { $0.pathExtension == SessionFormat.fileExtension }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
        guard let url = sessions.first else {
            status = "No .telepathy sessions in Documents"
            return
        }
        do {
            replayer = try SessionReplayer(url: url)
            dataSourceLabel = "Replay: \(url.lastPathComponent)"
            applyReplayCursor()
            status = "Replay \(url.lastPathComponent)"
        } catch {
            status = "Replay error: \(error.localizedDescription)"
        }
    }

    func scrubReplay(_ fraction: Double) {
        replayFraction = fraction
        replayer?.scrub(fraction: fraction)
        applyReplayCursor()
    }

    func accept() {
        if let payload = suggestions.acceptCurrent() {
            committedText += (committedText.isEmpty ? "" : " ") + payload.predictedText
            flash(accept: true)
            prediction = suggestions.current()
            recorder?.record(event: .init(kind: .accept, hostTimeNs: DispatchTime.now().uptimeNanoseconds, text: payload.predictedText))
        }
    }

    func reject() {
        if let next = suggestions.rejectCurrent() {
            prediction = next
            flash(accept: false)
            recorder?.record(event: .init(kind: .reject, hostTimeNs: DispatchTime.now().uptimeNanoseconds, text: next.predictedText))
        }
    }

    func stopSources() {
        localPlayer?.stop()
        localPlayer = nil
        ingest?.stop()
        ingest = nil
        replayer = nil
        isStreaming = false
    }

    var currentSeries: [Float] {
        guard let snap = stageSnapshots[selectedStage] else { return [] }
        let channels = min(availableChannels, snap.channelCount)
        // Overlay first N channels by averaging for a single sparkline strip set in UI.
        return snap.channelSeries(0) // primary; UI also reads multi-channel
    }

    func series(for channel: Int) -> [Float] {
        stageSnapshots[selectedStage]?.channelSeries(channel) ?? []
    }

    private func applyReplayCursor() {
        guard let replayer else { return }
        let snaps = replayer.tapsAtCursor()
        var map: [DSPStageID: StageTapSnapshot] = [:]
        for s in snaps { map[s.stage] = s }
        stageSnapshots = map
        if let last = replayer.eventsAtCursor().last(where: { $0.kind == .decoder }) {
            noisyText = last.text
        }
        if let pred = replayer.eventsAtCursor().last(where: { $0.kind == .prediction }) {
            prediction = PredictionPayload(
                predictedText: pred.text,
                confidence: 0.9,
                sourceCitation: pred.detail ?? "Replay",
                engine: "replay"
            )
        }
    }

    private func resolveBinURL() throws -> URL {
        let candidates = [
            Bundle.main.url(forResource: "synthetic_neural", withExtension: "bin"),
            URL(fileURLWithPath: "Samples/synthetic_neural.bin"),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("Samples/synthetic_neural.bin")
        ]
        for url in candidates {
            if let url, FileManager.default.fileExists(atPath: url.path) { return url }
        }
        throw NSError(domain: "Telepathy", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "synthetic_neural.bin missing — run python3 DatasetPrep/generate_synthetic.py"
        ])
    }

    private func flash(accept: Bool) {
        if accept {
            flashAccept = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { self.flashAccept = false }
        } else {
            flashReject = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { self.flashReject = false }
        }
    }
}

extension EngineViewModel: PipelineEngineDelegate {
    nonisolated func engineDidEmit(_ emission: DecoderEmission) {
        Task { @MainActor in
            noisyText = emission.noisyText
            let payload = suggestions.suggest(for: emission)
            prediction = payload
            recorder?.record(emission: emission)
            recorder?.record(event: .init(
                kind: .prediction,
                hostTimeNs: emission.hostTimeNs,
                text: payload.predictedText,
                detail: payload.sourceCitation
            ))
        }
    }

    nonisolated func engineDidDetect(_ intent: IntentEvent) {
        Task { @MainActor in
            recorder?.record(intent: intent)
            switch intent.intent {
            case .accept: accept()
            case .reject: reject()
            case .none: break
            }
        }
    }

    nonisolated func engineDidUpdateTaps(_ taps: [StageTapSnapshot]) {
        Task { @MainActor in
            var map = stageSnapshots
            for tap in taps { map[tap.stage] = tap }
            stageSnapshots = map
            recorder?.record(taps: taps)
            latencyMs = Double(engine.lastLatencyNs) / 1_000_000.0
            packets = engine.framesProcessed
        }
    }

    nonisolated func engineDidIngest(seq: UInt32, hostTimeNs: UInt64) {
        // Intentionally light — UI updated from tap/process path.
    }
}
