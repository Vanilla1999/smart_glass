#!/usr/bin/env python3
"""Deterministic WAV/DSP analysis for the audio frontend A/B artifacts."""

import argparse
import csv
import math
import wave
from pathlib import Path

import numpy as np

SAMPLE_RATE = 16000
BLOCK_SAMPLES = 256


def read_wav(path: Path):
    with wave.open(str(path), "rb") as wav:
        assert wav.getsampwidth() == 2, f"{path}: expected PCM16"
        assert wav.getframerate() == SAMPLE_RATE, f"{path}: expected 16000 Hz"
        channels = wav.getnchannels()
        frames = wav.getnframes()
        data = np.frombuffer(wav.readframes(frames), dtype="<i2")
    return data.reshape(-1, channels).astype(np.float64) / 32768.0, channels


def band_energy(samples, low, high):
    window = 1024
    if len(samples) < window:
        return 0.0
    frames = samples[: len(samples) // window * window].reshape(-1, window)
    spectrum = np.fft.rfft(frames * np.hanning(window), axis=1)
    power = np.mean(np.abs(spectrum) ** 2, axis=0)
    frequencies = np.fft.rfftfreq(window, 1 / SAMPLE_RATE)
    return float(power[(frequencies >= low) & (frequencies < high)].sum())


def metrics(name, samples):
    samples = samples[:, 0] if samples.ndim == 2 else samples
    rms = float(np.sqrt(np.mean(samples * samples)))
    peak = float(np.max(np.abs(samples)))
    clipped = int(np.count_nonzero(np.abs(samples) >= 32767 / 32768))
    differences = np.abs(np.diff(samples))
    boundaries = np.arange(BLOCK_SAMPLES, len(samples), BLOCK_SAMPLES)
    boundary_jumps = np.abs(samples[boundaries] - samples[boundaries - 1]) if len(boundaries) else np.array([0.0])
    ordinary_mask = np.ones(len(differences), dtype=bool)
    ordinary_mask[boundaries - 1] = False
    ordinary_jumps = differences[ordinary_mask]
    block_envelope = np.abs(samples[: len(samples) // BLOCK_SAMPLES * BLOCK_SAMPLES]).reshape(-1, BLOCK_SAMPLES).mean(axis=1)
    envelope_spectrum = np.abs(np.fft.rfft(block_envelope - block_envelope.mean())) ** 2
    envelope_freqs = np.fft.rfftfreq(len(block_envelope), BLOCK_SAMPLES / SAMPLE_RATE)
    artifact_625 = float(envelope_spectrum[np.argmin(np.abs(envelope_freqs - 62.5))]) if len(envelope_spectrum) else 0.0
    return {
        "file": name,
        "samples": len(samples),
        "duration_s": len(samples) / SAMPLE_RATE,
        "rms": rms,
        "peak_amplitude": peak,
        "peak_dbfs": 20 * math.log10(max(peak, 1e-15)),
        "dc_offset": float(np.mean(samples)),
        "clipped_samples": clipped,
        "clipped_fraction": clipped / len(samples),
        "crest_factor": peak / max(rms, 1e-15),
        "energy_0_80_hz": band_energy(samples, 0, 80),
        "energy_80_300_hz": band_energy(samples, 80, 300),
        "energy_300_3400_hz": band_energy(samples, 300, 3400),
        "energy_gt_3400_hz": band_energy(samples, 3400, SAMPLE_RATE / 2),
        "boundary_jump_median": float(np.median(boundary_jumps)),
        "boundary_jump_p95": float(np.quantile(boundary_jumps, 0.95)),
        "ordinary_jump_median": float(np.median(ordinary_jumps)),
        "ordinary_jump_p95": float(np.quantile(ordinary_jumps, 0.95)),
        "boundary_p95_to_ordinary_p95": float(np.quantile(boundary_jumps, 0.95) / max(np.quantile(ordinary_jumps, 0.95), 1e-15)),
        "envelope_62_5_hz_power": artifact_625,
    }


def best_lag(reference, candidate, maximum_lag=800):
    # Work on a deterministic 30 s portion to measure SSP pipeline delay without huge allocations.
    n = min(len(reference), len(candidate), SAMPLE_RATE * 30)
    reference = reference[:n] - reference[:n].mean()
    candidate = candidate[:n] - candidate[:n].mean()
    lags = np.arange(-maximum_lag, maximum_lag + 1)
    scores = []
    for lag in lags:
        left, right = (reference[lag:], candidate[: n - lag]) if lag >= 0 else (reference[: n + lag], candidate[-lag:])
        scores.append(float(np.dot(left, right) / max(np.linalg.norm(left) * np.linalg.norm(right), 1e-15)))
    index = int(np.argmax(np.abs(scores)))
    return int(lags[index]), scores[index]


def compare(reference, candidate, name):
    lag, _ = best_lag(reference, candidate)
    ref, value = (reference[lag:], candidate[: len(reference) - lag]) if lag >= 0 else (reference[: len(reference) + lag], candidate[-lag:])
    n = min(len(ref), len(value))
    ref, value = ref[:n], value[:n]
    correlation = float(np.dot(ref - ref.mean(), value - value.mean()) / max(np.linalg.norm(ref - ref.mean()) * np.linalg.norm(value - value.mean()), 1e-15))
    scale = float(np.dot(ref, value) / max(np.dot(value, value), 1e-15))
    distortion = ref - scale * value
    si_sdr = 10 * math.log10(max(np.dot(scale * value, scale * value), 1e-15) / max(np.dot(distortion, distortion), 1e-15))
    window = 1024
    frames = n // window
    ref_spectrum = np.abs(np.fft.rfft(ref[: frames * window].reshape(-1, window) * np.hanning(window), axis=1)) + 1e-12
    value_spectrum = np.abs(np.fft.rfft(value[: frames * window].reshape(-1, window) * np.hanning(window), axis=1)) + 1e-12
    log_spectral_distance = float(np.sqrt(np.mean((20 * np.log10(ref_spectrum) - 20 * np.log10(value_spectrum)) ** 2)))
    return {
        "comparison": name,
        "ssP_lag_samples": lag,
        "ssP_lag_ms": lag * 1000 / SAMPLE_RATE,
        "normalized_correlation": correlation,
        "si_sdr_db": si_sdr,
        "log_spectral_distance_db": log_spectral_distance,
        "rms_ratio": float(np.sqrt(np.mean(value * value)) / max(np.sqrt(np.mean(ref * ref)), 1e-15)),
        "speech_band_energy_ratio": band_energy(value, 300, 3400) / max(band_energy(ref, 300, 3400), 1e-15),
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--input-dir", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args()
    args.output_dir.mkdir(parents=True, exist_ok=True)
    wavs = sorted({*args.input_dir.glob("*.wav"), *args.output_dir.glob("*_denoised_*.wav")})
    rows = []
    for path in wavs:
        samples, _ = read_wav(path)
        rows.append(metrics(path.name, samples))
    with (args.output_dir / "metrics.csv").open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=rows[0].keys())
        writer.writeheader()
        writer.writerows(rows)

    comparisons = []
    for identifier in ("1786194763609", "1786194978795"):
        ssp, _ = read_wav(args.input_dir / f"ssp_mono_{identifier}.wav")
        for frontend in ("legacy", "aligned"):
            derived, _ = read_wav(args.output_dir / f"{frontend}_denoised_{identifier}.wav")
            comparisons.append(compare(ssp[:, 0], derived[:, 0], f"{frontend}_vs_ssp_{identifier}"))
    with (args.output_dir / "ssp_comparison.csv").open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=comparisons[0].keys())
        writer.writeheader()
        writer.writerows(comparisons)


if __name__ == "__main__":
    main()
