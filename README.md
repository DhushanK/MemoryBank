# Context-Aware Telepathy Engine

Zero-allocation-oriented HITL pipeline: simulated intracortical neural stream → Swift DSP → local Memory Bank RAG → Accept/Reject UI, with per-stage timeseries visualization and session record/replay.

## Quick start

```bash
# 1) Synthetic neural data
python3 DatasetPrep/generate_synthetic.py

# 2) Build libraries + UDP streamer
swift build
swift test

# 3) Generate / refresh the Xcode app project
python3 Scripts/generate_xcode_project.py
open TelepathyEngine.xcodeproj
```

In Xcode, select the **My Mac** destination (or iPad/iPhone simulator) and run.

### App controls
- **Start Local Bin** — plays `Samples/synthetic_neural.bin` in-process (no network).
- **Listen UDP :9000** — receive from the Mac streamer: `swift run Streamer --bin Samples/synthetic_neural.bin`
- **Record Session / Load Latest Replay** — inspect any DSP stage as timeseries after the fact.
- Stage picker: `raw → bandpass → pca → spikes → rates`
- **Accept / Reject** — reinforce or down-weight Memory Bank context.

## Layout

| Path | Role |
|------|------|
| `Packages/NeuralCore` | UDP ingest, ring buffer, DSP stages + taps, decoder, intent |
| `Packages/SessionKit` | `.telepathy` session record/replay |
| `Packages/MemoryBankKit` | NL/hash embeddings + short-term buffer |
| `Packages/LLMBridge` | Suggestion engine (heuristic RAG; llama.cpp hook point) |
| `Streamer` | Mac UDP implant simulator |
| `Apps/TelepathyEngine` | SwiftUI + Metal UI (Mac / iPad / iPhone) |
| `DatasetPrep` | Kunz `.mat` → `.bin` + synthetic generator |
| `Firmware` | ESP32 drop-in notes (deferred) |

## Metrics (Phase 5 stubs)

See [`Docs/SystemsReport.md`](Docs/SystemsReport.md) for latency, WER, and ITR measurement procedure.
