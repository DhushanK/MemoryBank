#!/usr/bin/env python3
"""
Parse Kunz et al. inner-speech .mat recordings into int16 .bin windows.

Usage (once you have the dataset locally):
  python3 DatasetPrep/prepare_bin.py --mat path/to/file.mat --out Samples/kunz_window.bin
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np


def load_mat(path: Path):
    try:
        from scipy.io import loadmat
    except ImportError as exc:  # pragma: no cover
        raise SystemExit("scipy required: pip install -r DatasetPrep/requirements.txt") from exc
    return loadmat(path, simplify_cells=True)


def find_voltage_array(mat: dict) -> np.ndarray:
    """Heuristic search for a 2D voltage array (samples × channels or channels × samples)."""
    candidates = []
    for key, value in mat.items():
        if key.startswith("__"):
            continue
        arr = np.asarray(value)
        if arr.ndim == 2 and np.issubdtype(arr.dtype, np.floating):
            candidates.append((key, arr))
    if not candidates:
        raise SystemExit("No 2D float array found in .mat — inspect keys and pass --key")
    # Prefer wider channel-like second dim around 64–128, else largest array.
    candidates.sort(key=lambda kv: kv[1].size, reverse=True)
    return candidates[0][1]


def to_frames_channels(arr: np.ndarray, channels: int | None) -> np.ndarray:
    if channels is not None:
        if arr.shape[1] == channels:
            return arr
        if arr.shape[0] == channels:
            return arr.T
    # Assume longer axis is time.
    return arr if arr.shape[0] >= arr.shape[1] else arr.T


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--mat", type=Path, required=True)
    parser.add_argument("--out", type=Path, default=Path("Samples/kunz_window.bin"))
    parser.add_argument("--key", type=str, default=None, help="Optional mat key for voltage array")
    parser.add_argument("--start-sec", type=float, default=0.0)
    parser.add_argument("--duration-sec", type=float, default=10.0)
    parser.add_argument("--sample-rate", type=float, default=10_000.0)
    parser.add_argument("--channels", type=int, default=None)
    parser.add_argument("--sentence", type=str, default="")
    args = parser.parse_args()

    mat = load_mat(args.mat)
    arr = np.asarray(mat[args.key]) if args.key else find_voltage_array(mat)
    frames = to_frames_channels(arr, args.channels).astype(np.float64)

    start = int(args.start_sec * args.sample_rate)
    end = int(start + args.duration_sec * args.sample_rate)
    window = frames[start:end]
    if window.size == 0:
        raise SystemExit("Empty window — check start/duration/sample-rate")

    # Robust scale to int16
    peak = np.percentile(np.abs(window), 99.9)
    peak = peak if peak > 0 else 1.0
    scaled = np.clip(window / peak, -1.0, 1.0)
    int16 = (scaled * np.iinfo(np.int16).max).astype(np.int16)

    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_bytes(int16.tobytes(order="C"))
    meta = {
        "source": str(args.mat),
        "path": str(args.out),
        "channels": int(int16.shape[1]),
        "frames": int(int16.shape[0]),
        "sample_rate": args.sample_rate,
        "start_sec": args.start_sec,
        "duration_sec": args.duration_sec,
        "sentence": args.sentence,
        "dtype": "int16",
    }
    args.out.with_suffix(".json").write_text(json.dumps(meta, indent=2))
    print(f"Wrote {args.out} shape={int16.shape}")


if __name__ == "__main__":
    main()
