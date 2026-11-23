import SwiftUI
import NeuralCore

struct ContentView: View {
    @EnvironmentObject private var model: EngineViewModel

    var body: some View {
#if os(iOS)
        TabView {
            pipelineTab.tabItem { Label("Stages", systemImage: "waveform.path.ecg") }
            signalTab.tabItem { Label("Signal", systemImage: "dot.radiowaves.left.and.right") }
            textTab.tabItem { Label("Text", systemImage: "text.cursor") }
        }
#else
        NavigationSplitView {
            controlSidebar
                .navigationTitle("Telepathy")
                .frame(minWidth: 220)
        } detail: {
            HStack(spacing: 0) {
                pipelinePane
                Divider()
                textPane
            }
        }
#endif
    }

    private var pipelineTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                controls
                stagePicker
                TimeseriesPlotView(
                    title: model.selectedStage.rawValue.uppercased(),
                    channelCount: min(model.availableChannels, model.stageSnapshots[model.selectedStage]?.channelCount ?? 0),
                    seriesForChannel: { model.series(for: $0) }
                )
                .frame(minHeight: 280)
            }
            .padding()
        }
    }

    private var signalTab: some View {
        VStack {
            MetalSpikeView(snapshot: model.stageSnapshots[.spikes] ?? model.stageSnapshots[.raw])
                .clipShape(RoundedRectangle(cornerRadius: 12))
            statusBar
        }
        .padding()
    }

    private var textTab: some View {
        ScrollView {
            textPaneContent
                .padding()
        }
    }

    private var controlSidebar: some View {
        List {
            Section("Mode") {
                controls
            }
            Section("DSP Stage") {
                stagePicker
            }
            Section("Status") {
                Text(model.status).font(.caption)
                Text(model.dataSourceLabel).font(.caption2).foregroundStyle(.secondary)
                Text(String(format: "Frames: %llu  Latency: %.1f ms", model.packets, model.latencyMs))
                    .font(.caption.monospacedDigit())
            }
        }
    }

    private var pipelinePane: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                stagePicker
                Spacer()
                Stepper("Channels: \(model.availableChannels)", value: $model.availableChannels, in: 1...16)
                    .frame(maxWidth: 220)
            }
            TimeseriesPlotView(
                title: "Stage: \(model.selectedStage.rawValue)",
                channelCount: min(model.availableChannels, model.stageSnapshots[model.selectedStage]?.channelCount ?? 0),
                seriesForChannel: { model.series(for: $0) }
            )
            .frame(maxHeight: .infinity)

            MetalSpikeView(snapshot: model.stageSnapshots[.spikes] ?? model.stageSnapshots[.bandpass])
                .frame(height: 160)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            if model.mode == .replay {
                Slider(value: Binding(
                    get: { model.replayFraction },
                    set: { model.scrubReplay($0) }
                ), in: 0...1)
                Text("Session scrub").font(.caption).foregroundStyle(.secondary)
            }
            statusBar
        }
        .padding()
        .background(model.flashAccept ? Color.green.opacity(0.15) : model.flashReject ? Color.red.opacity(0.15) : Color.clear)
        .animation(.easeOut(duration: 0.2), value: model.flashAccept)
    }

    private var textPane: some View {
        ScrollView {
            textPaneContent
                .padding()
        }
        .frame(minWidth: 320, idealWidth: 380)
    }

    private var textPaneContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Human-in-the-Loop").font(.title2.weight(.semibold))
            GroupBox("Noisy Decoder") {
                Text(model.noisyText.isEmpty ? "—" : model.noisyText)
                    .font(.system(.title3, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            ContextReminderView(prediction: model.prediction)
            HStack {
                Button("Accept ⌘↩") { model.accept() }
                    .keyboardShortcut(.return, modifiers: [.command])
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                Button("Reject ⌘⌫") { model.reject() }
                    .keyboardShortcut(.delete, modifiers: [.command])
                    .buttonStyle(.bordered)
                    .tint(.red)
            }
            GroupBox("Committed") {
                Text(model.committedText.isEmpty ? "Accepted phrases appear here." : model.committedText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Spacer(minLength: 0)
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button("Start Local Bin") { model.startLiveLocal() }
            Button("Listen UDP :\(WireProtocol.defaultPort)") { model.startLiveUDP() }
            Button("Stop Stream", role: .destructive) { model.stopLive() }
                .disabled(!model.isStreaming)
            Button("Load Latest Replay") { model.loadLatestReplay() }
            if model.isRecording {
                Button("Stop Recording", role: .destructive) { model.stopRecording() }
            } else {
                Button("Record Session") { model.startRecording() }
                    .disabled(!model.isStreaming && model.mode != .replay)
            }
            Text(model.dataSourceLabel)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var stagePicker: some View {
        Picker("Stage", selection: $model.selectedStage) {
            ForEach(DSPStageID.allCases, id: \.self) { stage in
                Text(stage.rawValue).tag(stage)
            }
        }
#if os(iOS)
        .pickerStyle(.segmented)
#else
        .pickerStyle(.radioGroup)
#endif
    }

    private var statusBar: some View {
        HStack {
            Text(model.status).font(.caption)
            Spacer()
            Text(String(format: "%.1f ms", model.latencyMs))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }
}
