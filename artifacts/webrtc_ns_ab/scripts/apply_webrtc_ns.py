#!/usr/bin/env python3
"""Apply WebRTC APM noise suppression levels to 16 kHz mono PCM16 WAV files."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import math
import shutil
import struct
import sys
import wave
from dataclasses import dataclass
from pathlib import Path
from typing import Callable

SAMPLE_RATE = 16_000
CHANNELS = 1
SAMPLE_WIDTH = 2
FRAME_SAMPLES = SAMPLE_RATE // 100  # WebRTC APM consumes 10 ms frames.
FRAME_BYTES = FRAME_SAMPLES * SAMPLE_WIDTH

RECORDING_IDS = ("1786194763609", "1786194978795")
LEVELS = (
    ("low", 0),
    ("moderate", 1),
    ("high", 2),
    ("very_high", 3),
)


@dataclass(frozen=True)
class WavData:
    frames: bytes
    frame_count: int


def read_pcm16_mono(path: Path) -> WavData:
    with wave.open(str(path), "rb") as wav:
        actual = (wav.getframerate(), wav.getnchannels(), wav.getsampwidth(), wav.getcomptype())
        expected = (SAMPLE_RATE, CHANNELS, SAMPLE_WIDTH, "NONE")
        if actual != expected:
            raise ValueError(f"{path}: expected {expected}, got {actual}")
        frame_count = wav.getnframes()
        frames = wav.readframes(frame_count)
    if len(frames) != frame_count * SAMPLE_WIDTH:
        raise ValueError(f"{path}: truncated PCM payload")
    return WavData(frames=frames, frame_count=frame_count)


def write_pcm16_mono(path: Path, frames: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), "wb") as wav:
        wav.setnchannels(CHANNELS)
        wav.setsampwidth(SAMPLE_WIDTH)
        wav.setframerate(SAMPLE_RATE)
        wav.writeframes(frames)


def load_ap_factory() -> Callable[[int], object]:
    try:
        from webrtc_audio_processing import AudioProcessingModule
    except Exception as error:
        raise RuntimeError(
            "Cannot import webrtc_audio_processing.AudioProcessingModule. "
            "Use a Python 3.10/3.11 environment and install "
            "webrtc-audio-processing==0.1.3. Do not replace it with another denoiser."
        ) from error

    def create(level: int) -> object:
        # Only NS is enabled. AEC/AGC/VAD remain disabled.
        ap = AudioProcessingModule(
            enable_aec=False,
            enable_ns=True,
            enable_agc=False,
            enable_vad=False,
        )
        ap.set_stream_format(SAMPLE_RATE, CHANNELS)
        ap.set_ns_level(level)
        return ap

    return create


def process_frames(source: bytes, level: int, create_ap: Callable[[int], object]) -> bytes:
    ap = create_ap(level)
    output = bytearray()
    for offset in range(0, len(source), FRAME_BYTES):
        chunk = source[offset : offset + FRAME_BYTES]
        valid_size = len(chunk)
        if valid_size < FRAME_BYTES:
            chunk += b"\x00" * (FRAME_BYTES - valid_size)
        processed = ap.process_stream(chunk)
        if isinstance(processed, str):
            processed = processed.encode("latin1")
        if not isinstance(processed, (bytes, bytearray)) or len(processed) != FRAME_BYTES:
            raise RuntimeError(
                f"WebRTC APM returned {type(processed).__name__} with "
                f"{len(processed) if hasattr(processed, '__len__') else 'unknown'} bytes; "
                f"expected {FRAME_BYTES}"
            )
        output.extend(processed[:valid_size])
    return bytes(output)


def pcm_metrics(frames: bytes) -> dict[str, float | int | str]:
    if len(frames) % 2:
        raise ValueError("PCM16 byte count must be even")
    samples = struct.unpack(f"<{len(frames) // 2}h", frames)
    if not samples:
        return {
            "samples": 0,
            "duration_s": 0.0,
            "rms": 0.0,
            "peak": 0,
            "peak_dbfs": float("-inf"),
            "dc_offset": 0.0,
            "clipped_samples": 0,
            "sha256": hashlib.sha256(frames).hexdigest(),
        }
    peak = max(abs(value) for value in samples)
    rms = math.sqrt(sum(value * value for value in samples) / len(samples))
    mean = sum(samples) / len(samples)
    return {
        "samples": len(samples),
        "duration_s": len(samples) / SAMPLE_RATE,
        "rms": rms / 32768.0,
        "peak": peak,
        "peak_dbfs": 20.0 * math.log10(peak / 32768.0) if peak else float("-inf"),
        "dc_offset": mean / 32768.0,
        "clipped_samples": sum(abs(value) >= 32767 for value in samples),
        "sha256": hashlib.sha256(frames).hexdigest(),
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input-dir", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args()

    create_ap = load_ap_factory()
    args.output_dir.mkdir(parents=True, exist_ok=True)
    rows: list[dict[str, object]] = []
    manifest: dict[str, object] = {
        "sample_rate": SAMPLE_RATE,
        "channels": CHANNELS,
        "sample_width_bytes": SAMPLE_WIDTH,
        "frame_samples": FRAME_SAMPLES,
        "frame_bytes": FRAME_BYTES,
        "aec": False,
        "agc": False,
        "vad": False,
        "levels": {name: value for name, value in LEVELS},
        "files": [],
    }

    for recording_id in RECORDING_IDS:
        source_path = args.input_dir / f"ssp_mono_{recording_id}.wav"
        source = read_pcm16_mono(source_path)

        baseline_path = args.output_dir / f"baseline_ssp_{recording_id}.wav"
        shutil.copyfile(source_path, baseline_path)
        baseline_metrics = pcm_metrics(source.frames)
        rows.append({"recording": recording_id, "variant": "baseline", **baseline_metrics})

        file_entry: dict[str, object] = {
            "recording": recording_id,
            "source": str(source_path.resolve()),
            "source_frames": source.frame_count,
            "outputs": {"baseline": baseline_path.name},
        }

        for level_name, level_value in LEVELS:
            processed = process_frames(source.frames, level_value, create_ap)
            if len(processed) != len(source.frames):
                raise RuntimeError(
                    f"{recording_id}/{level_name}: length changed "
                    f"{len(source.frames)} -> {len(processed)} bytes"
                )
            output_path = args.output_dir / f"webrtc_ns_{level_name}_{recording_id}.wav"
            write_pcm16_mono(output_path, processed)
            rows.append(
                {
                    "recording": recording_id,
                    "variant": f"webrtc_ns_{level_name}",
                    **pcm_metrics(processed),
                }
            )
            file_entry["outputs"][level_name] = output_path.name

        manifest["files"].append(file_entry)

    with (args.output_dir / "ns_manifest.json").open("w", encoding="utf-8") as handle:
        json.dump(manifest, handle, ensure_ascii=False, indent=2)

    with (args.output_dir / "ns_metrics.csv").open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=rows[0].keys())
        writer.writeheader()
        writer.writerows(rows)

    print(f"Wrote WebRTC NS matrix to {args.output_dir}")


if __name__ == "__main__":
    main()
