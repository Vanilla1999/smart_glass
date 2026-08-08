#!/usr/bin/env python3
"""Measure raw_mix123-to-SSP lag at three energetic full-recording regions."""

from __future__ import annotations

import argparse
import csv
from pathlib import Path

import numpy as np

from frontend_common import average_channels, extract_channels, read_wav, unpack_i16

RECORDINGS = ("1786194763609", "1786194978795")


def best_region(raw: np.ndarray, start: int, end: int, window: int) -> int:
    candidates = range(start, max(start + 1, end - window + 1), 16_000)
    return max(candidates, key=lambda offset: float(np.mean(raw[offset:offset + window] ** 2)))


def lag(raw: np.ndarray, ssp: np.ndarray, limit: int = 2000) -> tuple[int, float]:
    raw = raw - raw.mean(); ssp = ssp - ssp.mean()
    values = []
    for shift in range(-limit, limit + 1):
        left = raw[max(0, shift):min(len(raw), len(raw) + shift)]
        right = ssp[max(0, -shift):min(len(ssp), len(ssp) - shift)]
        values.append(float(np.dot(left, right)))
    best = int(np.argmax(values)) - limit
    left = raw[max(0, best):min(len(raw), len(raw) + best)]
    right = ssp[max(0, -best):min(len(ssp), len(ssp) - best)]
    return best, float(np.corrcoef(left, right)[0, 1])


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--capture-dir", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args(); rows = []
    for recording in RECORDINGS:
        raw_wav = read_wav(args.capture_dir / f"raw_4ch_{recording}.wav", 4)
        ssp_wav = read_wav(args.capture_dir / f"ssp_mono_{recording}.wav", 1)
        channels = extract_channels(raw_wav.frames)
        raw = np.asarray(unpack_i16(average_channels(channels, (1, 2, 3))), dtype=np.float64)
        ssp = np.asarray(unpack_i16(ssp_wav.frames), dtype=np.float64)
        common = min(len(raw), len(ssp)); third = common // 3; window = 8 * 16_000
        for region in range(3):
            offset = best_region(raw, region * third, (region + 1) * third, window)
            measured, correlation = lag(raw[offset:offset + window], ssp[offset:offset + window])
            rows.append({"recording": recording, "region_start_s": offset / 16_000,
                         "region_end_s": (offset + window) / 16_000, "lag_samples": measured,
                         "lag_ms": measured / 16.0, "correlation": correlation})
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=rows[0].keys()); writer.writeheader(); writer.writerows(rows)
    print(f"Wrote {args.output}")


if __name__ == "__main__":
    main()
