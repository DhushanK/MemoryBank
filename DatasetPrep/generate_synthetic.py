#!/usr/bin/env python3
"""Generate a synthetic 64-ch int16 neural .bin for offline demos (stdlib only)."""

from __future__ import annotations

import argparse
import json
import math
import random
import struct
from pathlib import Path

PHRASES = [
    "Meeting at 4",
    "Send the design notes",
    "Call mom after lunch",
    "Book a flight to Seattle",
    "Remind me to stretch",
]


def synthesize(channels: int, sample_rate: int, seconds: float, seed: int) -> bytes:
    rng = random.Random(seed)
    n = int(sample_rate * seconds)
    out = bytearray()
    window = max(1, n // len(PHRASES))

    for i in range(n):
        phrase_i = min(len(PHRASES) - 1, i // window)
        t = i / sample_rate
        local = (i % window) / window
        envelope = 0.5 - 0.5 * math.cos(2 * math.pi * local)
        for ch in range(channels):
            noise = rng.uniform(-0.05, 0.05)
            freq = 400 + (ch * 37) % 2000
            burst = 0.35 * math.sin(2 * math.pi * freq * t) * envelope
            spike = 0.0
            if rng.random() < 0.005:
                spike = rng.uniform(0.6, 1.0)
            bias = 0.02 * phrase_i
            sample = max(-1.0, min(1.0, noise + burst + spike + bias))
            out += struct.pack("<h", int(sample * 32767))
    return bytes(out)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", type=Path, default=Path("Samples/synthetic_neural.bin"))
    parser.add_argument("--channels", type=int, default=64)
    parser.add_argument("--rate", type=int, default=10_000)
    parser.add_argument("--seconds", type=float, default=2.0)
    parser.add_argument("--seed", type=int, default=42)
    args = parser.parse_args()

    args.out.parent.mkdir(parents=True, exist_ok=True)
    payload = synthesize(args.channels, args.rate, args.seconds, args.seed)
    args.out.write_bytes(payload)

    manifest = {
        "path": str(args.out),
        "channels": args.channels,
        "sample_rate": args.rate,
        "seconds": args.seconds,
        "dtype": "int16",
        "layout": "frame-major interleaved channels",
        "phrases": PHRASES,
        "bytes": len(payload),
    }
    manifest_path = args.out.with_suffix(".json")
    manifest_path.write_text(json.dumps(manifest, indent=2))
    print(f"Wrote {args.out} ({len(payload)} bytes) and {manifest_path}")


if __name__ == "__main__":
    main()
