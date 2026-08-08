#!/usr/bin/env python3
"""Validate and measure the WebRTC NS output matrix against its SSP baseline."""

from __future__ import annotations

import argparse
import csv
import hashlib
import math
import wave
from pathlib import Path

import numpy as np

SAMPLE_RATE = 16_000
FRAME_SAMPLES = 160
RECORDING_IDS = ("1786194763609", "1786194978795")
VARIANTS = ("baseline", "webrtc_ns_low", "webrtc_ns_moderate", "webrtc_ns_high", "webrtc_ns_very_high")


def read_wav(path: Path) -> tuple[bytes, np.ndarray]:
    with wave.open(str(path), "rb") as wav:
        actual = (wav.getframerate(), wav.getnchannels(), wav.getsampwidth(), wav.getcomptype())
        expected = (SAMPLE_RATE, 1, 2, "NONE")
        if actual != expected:
            raise ValueError(f"{path}: expected {expected}, got {actual}")
        pcm = wav.readframes(wav.getnframes())
    if len(pcm) % 2:
        raise ValueError(f"{path}: odd PCM byte count")
    return pcm, np.frombuffer(pcm, dtype="<i2").astype(np.float64) / 32768.0


def band_energy(samples: np.ndarray, low: float, high: float) -> float:
    window = 1024
    usable = len(samples) // window * window
    if not usable:
        return 0.0
    frames = samples[:usable].reshape(-1, window) * np.hanning(window)
    spectrum = np.fft.rfft(frames, axis=1)
    frequencies = np.fft.rfftfreq(window, 1 / SAMPLE_RATE)
    return float(np.mean(np.abs(spectrum) ** 2, axis=0)[(frequencies >= low) & (frequencies < high)].sum())


def output_path(audio_dir: Path, variant: str, recording: str) -> Path:
    return audio_dir / (f"baseline_ssp_{recording}.wav" if variant == "baseline" else f"{variant}_{recording}.wav")


def align_to_baseline(baseline: np.ndarray, samples: np.ndarray) -> tuple[int, np.ndarray, np.ndarray]:
    if np.array_equal(baseline, samples):
        return 0, baseline, samples
    # APM may add a short fixed algorithmic delay; estimate it on 30 s only.
    length = min(len(baseline), len(samples), SAMPLE_RATE * 30)
    reference = baseline[:length] - baseline[:length].mean()
    candidate = samples[:length] - samples[:length].mean()
    best_lag = 0
    best_score = -1.0
    for lag in range(-320, 321):
        left, right = (reference[lag:], candidate[:length - lag]) if lag >= 0 else (reference[:length + lag], candidate[-lag:])
        score = abs(float(np.dot(left, right) / max(np.linalg.norm(left) * np.linalg.norm(right), 1e-15)))
        if score > best_score:
            best_lag, best_score = lag, score
    if best_lag >= 0:
        return best_lag, baseline[best_lag:], samples[:len(baseline) - best_lag]
    return best_lag, baseline[:len(baseline) + best_lag], samples[-best_lag:]


def metrics(recording: str, variant: str, baseline: np.ndarray, pcm: bytes, samples: np.ndarray) -> dict[str, object]:
    peak = float(np.max(np.abs(samples)))
    rms = float(np.sqrt(np.mean(samples * samples)))
    boundaries = np.arange(FRAME_SAMPLES, len(samples), FRAME_SAMPLES)
    jumps = np.abs(np.diff(samples))
    boundary_jumps = jumps[boundaries - 1]
    ordinary = np.ones(len(jumps), dtype=bool)
    ordinary[boundaries - 1] = False
    frame_envelope = np.abs(samples[:len(samples) // FRAME_SAMPLES * FRAME_SAMPLES]).reshape(-1, FRAME_SAMPLES).mean(axis=1)
    frequencies = np.fft.rfftfreq(len(frame_envelope), FRAME_SAMPLES / SAMPLE_RATE)
    envelope = np.abs(np.fft.rfft(frame_envelope - frame_envelope.mean())) ** 2
    lag, aligned_baseline, aligned_samples = align_to_baseline(baseline, samples)
    correlation = float(np.corrcoef(aligned_baseline, aligned_samples)[0, 1])
    scale = float(np.dot(aligned_baseline, aligned_samples) / max(np.dot(aligned_samples, aligned_samples), 1e-15))
    error = aligned_baseline - scale * aligned_samples
    si_sdr = 10 * math.log10(max(np.dot(scale * aligned_samples, scale * aligned_samples), 1e-15) / max(np.dot(error, error), 1e-15))
    window = 1024
    count = len(aligned_samples) // window
    baseline_spectrum = np.abs(np.fft.rfft(aligned_baseline[:count * window].reshape(-1, window) * np.hanning(window), axis=1)) + 1e-12
    sample_spectrum = np.abs(np.fft.rfft(aligned_samples[:count * window].reshape(-1, window) * np.hanning(window), axis=1)) + 1e-12
    return {
        "recording": recording,
        "variant": variant,
        "samples": len(samples),
        "duration_s": len(samples) / SAMPLE_RATE,
        "rms": rms,
        "peak_amplitude": peak,
        "peak_dbfs": 20 * math.log10(max(peak, 1e-15)),
        "dc_offset": float(np.mean(samples)),
        "clipped_samples": int(np.count_nonzero(np.abs(samples) >= 32767 / 32768)),
        "crest_factor": peak / max(rms, 1e-15),
        "energy_0_80_hz": band_energy(samples, 0, 80),
        "energy_80_300_hz": band_energy(samples, 80, 300),
        "energy_300_3400_hz": band_energy(samples, 300, 3400),
        "energy_gt_3400_hz": band_energy(samples, 3400, SAMPLE_RATE / 2),
        "alignment_lag_samples": lag,
        "alignment_lag_ms": lag * 1000 / SAMPLE_RATE,
        "correlation_to_baseline": correlation,
        "log_spectral_distance_db": float(np.sqrt(np.mean((20 * np.log10(baseline_spectrum) - 20 * np.log10(sample_spectrum)) ** 2))),
        "si_sdr_db": si_sdr,
        "boundary_jump_p95": float(np.quantile(boundary_jumps, 0.95)),
        "ordinary_jump_p95": float(np.quantile(jumps[ordinary], 0.95)),
        "boundary_to_ordinary_p95": float(np.quantile(boundary_jumps, 0.95) / max(np.quantile(jumps[ordinary], 0.95), 1e-15)),
        "envelope_100_hz_power": float(envelope[np.argmin(np.abs(frequencies - 100.0))]),
        "pcm_sha256": hashlib.sha256(pcm).hexdigest(),
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input-dir", type=Path, required=True)
    parser.add_argument("--audio-dir", type=Path, required=True)
    args = parser.parse_args()
    rows: list[dict[str, object]] = []
    for recording in RECORDING_IDS:
        source_pcm, source = read_wav(args.input_dir / f"ssp_mono_{recording}.wav")
        for variant in VARIANTS:
            pcm, samples = read_wav(output_path(args.audio_dir, variant, recording))
            if len(samples) != len(source):
                raise ValueError(f"{recording}/{variant}: sample count changed")
            if variant == "baseline" and pcm != source_pcm:
                raise ValueError(f"{recording}: baseline PCM differs from source")
            rows.append(metrics(recording, variant, source, pcm, samples))
    with (args.audio_dir / "ns_dsp_matrix.csv").open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=rows[0].keys())
        writer.writeheader()
        writer.writerows(rows)


if __name__ == "__main__":
    main()
