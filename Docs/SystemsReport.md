# Systems Engineering Report — Context-Aware Telepathy Engine

## 1. System Latency & Throughput

**Target:** end-to-end (packet/frame receipt → UI tap publish) &lt; 100 ms; zero ARC allocations on the steady-state ingest/DSP queues.

### Procedure
1. Run **Start Local Bin** or `swift run Streamer` + **Listen UDP**.
2. Open Xcode Instruments → **Allocations** + **Time Profiler** against `TelepathyEngine`.
3. After warmup (~5 s), confirm the DSP queue shows no persistent heap growth.
4. Read on-screen latency (ns delta from frame `hostTimeNs` to process time).

### Recorded results
| Metric | Value | Notes |
|--------|-------|-------|
| Sustained sample rate | _TBD_ | 10 kHz × 64 ch target |
| UI latency (ms) | _TBD_ | from app HUD |
| Steady-state allocations | _TBD_ | Instruments screenshot |

## 2. Biological Decoding Accuracy (WER)

Measure Word Error Rate of the **raw noisy decoder** against ground-truth phrases in `Samples/synthetic_neural.json` / Kunz manifest **before** RAG correction.

```text
WER = edits(hypothesis, reference) / words(reference)
```

| Condition | WER |
|-----------|-----|
| Raw decoder | _TBD_ |
| After HITL RAG accept | _TBD_ |

## 3. Information Transfer Rate (ITR)

Compare bits/min of raw decoder vs HITL+RAG corrected committed text over a fixed session length.

```text
ITR ≈ (log2(N) + P*log2(P) + (1-P)*log2((1-P)/(N-1))) * (trials/min)
```

Document baseline vs final ITR once demo phrases and accept rates are collected.

## 4. Pipeline Observability

Session files (`.telepathy`) store decimated taps for stages `raw`, `bandpass`, `pca`, `spikes`, `rates` plus decoder/HITL events so any filtering step can be scrubbed offline.
