#!/usr/bin/env python3
"""Measure short inter-channel correlation lags in fixed 10 s windows."""

import csv
import sys
import wave
from pathlib import Path

import numpy as np


def best_lag(reference, candidate):
    scores = []
    for lag in range(-8, 9):
        a, b = (reference[lag:], candidate[: len(reference) - lag]) if lag >= 0 else (reference[: len(reference) + lag], candidate[-lag:])
        scores.append(float(np.dot(a, b) / max(np.linalg.norm(a) * np.linalg.norm(b), 1e-15)))
    index = int(np.argmax(scores))
    return index - 8, scores[index]


def main():
    input_dir, output = map(Path, sys.argv[1:3])
    rows = []
    for path in sorted(input_dir.glob("raw_4ch_*.wav")):
        with wave.open(str(path), "rb") as wav:
            data = np.frombuffer(wav.readframes(wav.getnframes()), dtype="<i2").astype(np.float64).reshape(-1, 4)
        for start in range(0, len(data), 160_000):
            segment = data[start:start + 160_000]
            if len(segment) < 16_000:
                continue
            for channel in range(1, 4):
                lag, correlation = best_lag(segment[:, 0] - segment[:, 0].mean(), segment[:, channel] - segment[:, channel].mean())
                rows.append({"file": path.name, "start_s": start / 16_000, "channel": channel, "best_lag_samples": lag, "correlation": correlation})
    with output.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=rows[0].keys())
        writer.writeheader()
        writer.writerows(rows)


if __name__ == "__main__":
    main()
