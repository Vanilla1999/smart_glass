#!/usr/bin/env python3
"""Shared PCM and frontend helpers for the replacement A/B experiment."""

from __future__ import annotations

import csv
import hashlib
import json
import math
import struct
import wave
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable, Sequence

SAMPLE_RATE = 16_000
SAMPLE_WIDTH = 2
RAW_CHANNELS = 4
WEBRTC_FRAME_SAMPLES = 160
WEBRTC_FRAME_BYTES = WEBRTC_FRAME_SAMPLES * SAMPLE_WIDTH
WEBRTC_DELAY_SAMPLES = 96
RECORDING_IDS = ("1786194763609", "1786194978795")


@dataclass(frozen=True)
class WavData:
    channels: int
    sample_rate: int
    sample_width: int
    frames: bytes
    frame_count: int


def read_wav(path: Path, expected_channels: int | None = None) -> WavData:
    with wave.open(str(path), "rb") as wav:
        data = WavData(
            channels=wav.getnchannels(),
            sample_rate=wav.getframerate(),
            sample_width=wav.getsampwidth(),
            frames=wav.readframes(wav.getnframes()),
            frame_count=wav.getnframes(),
        )
        compression = wav.getcomptype()
    if compression != "NONE":
        raise ValueError(f"{path}: compressed WAV is unsupported: {compression}")
    if data.sample_rate != SAMPLE_RATE or data.sample_width != SAMPLE_WIDTH:
        raise ValueError(
            f"{path}: expected {SAMPLE_RATE} Hz PCM16, got "
            f"{data.sample_rate} Hz width={data.sample_width}"
        )
    if expected_channels is not None and data.channels != expected_channels:
        raise ValueError(f"{path}: expected {expected_channels} channels, got {data.channels}")
    if len(data.frames) != data.frame_count * data.channels * data.sample_width:
        raise ValueError(f"{path}: truncated PCM payload")
    return data


def write_mono(path: Path, pcm: bytes) -> None:
    if len(pcm) % 2:
        raise ValueError("PCM16 payload has odd byte count")
    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), "wb") as wav:
        wav.setnchannels(1)
        wav.setsampwidth(SAMPLE_WIDTH)
        wav.setframerate(SAMPLE_RATE)
        wav.writeframes(pcm)


def unpack_i16(pcm: bytes) -> tuple[int, ...]:
    if len(pcm) % 2:
        raise ValueError("PCM16 payload has odd byte count")
    return struct.unpack(f"<{len(pcm) // 2}h", pcm)


def pack_i16(samples: Iterable[int]) -> bytes:
    values = [max(-32768, min(32767, int(value))) for value in samples]
    return struct.pack(f"<{len(values)}h", *values)


def extract_channels(raw_pcm: bytes) -> list[list[int]]:
    values = unpack_i16(raw_pcm)
    if len(values) % RAW_CHANNELS:
        raise ValueError("4-channel PCM sample count is not frame-aligned")
    channels = [[] for _ in range(RAW_CHANNELS)]
    for index in range(0, len(values), RAW_CHANNELS):
        for channel in range(RAW_CHANNELS):
            channels[channel].append(values[index + channel])
    return channels


def average_channels(channels: Sequence[Sequence[int]], indexes: Sequence[int]) -> bytes:
    if not indexes:
        raise ValueError("indexes must not be empty")
    length = len(channels[indexes[0]])
    if any(len(channels[index]) != length for index in indexes):
        raise ValueError("channel lengths differ")
    # Kotlin/Java integer division truncates toward zero.
    result = [int(sum(channels[index][i] for index in indexes) / len(indexes)) for i in range(length)]
    return pack_i16(result)


class HighPass80:
    """Production-equivalent 80 Hz biquad from RawLightDenoiser."""

    def __init__(self) -> None:
        q = 0.7071067811865476
        omega = 2.0 * math.pi * 80.0 / SAMPLE_RATE
        alpha = math.sin(omega) / (2.0 * q)
        scale = 1.0 / (1.0 + alpha)
        self.b0 = ((1.0 + math.cos(omega)) / 2.0) * scale
        self.b1 = -(1.0 + math.cos(omega)) * scale
        self.b2 = self.b0
        self.a1 = (-2.0 * math.cos(omega)) * scale
        self.a2 = (1.0 - alpha) * scale
        self.x1 = self.x2 = self.y1 = self.y2 = 0.0

    def process(self, pcm: bytes) -> bytes:
        output: list[int] = []
        for sample in unpack_i16(pcm):
            x = sample / 32768.0
            y = (
                self.b0 * x
                + self.b1 * self.x1
                + self.b2 * self.x2
                - self.a1 * self.y1
                - self.a2 * self.y2
            )
            self.x2, self.x1 = self.x1, x
            self.y2, self.y1 = self.y1, y
            output.append(max(-32768, min(32767, int(y * 32768.0))))
        return pack_i16(output)


def align_processed(processed: bytes, target_samples: int, delay_samples: int = WEBRTC_DELAY_SAMPLES) -> bytes:
    values = list(unpack_i16(processed))
    if delay_samples < 0:
        raise ValueError("delay_samples must be non-negative")
    aligned = values[delay_samples:]
    if len(aligned) < target_samples:
        aligned.extend([0] * (target_samples - len(aligned)))
    return pack_i16(aligned[:target_samples])


def blend(enhanced: bytes, dry: bytes, enhanced_weight: float) -> bytes:
    if not 0.0 <= enhanced_weight <= 1.0:
        raise ValueError("enhanced_weight must be in [0, 1]")
    a = unpack_i16(enhanced)
    b = unpack_i16(dry)
    if len(a) != len(b):
        raise ValueError("blend inputs differ in length")
    return pack_i16(int(enhanced_weight * x + (1.0 - enhanced_weight) * y) for x, y in zip(a, b))


def pcm_metrics(pcm: bytes) -> dict[str, object]:
    samples = unpack_i16(pcm)
    if not samples:
        return {
            "samples": 0,
            "duration_s": 0.0,
            "rms": 0.0,
            "peak_dbfs": float("-inf"),
            "dc_offset": 0.0,
            "clipped_samples": 0,
            "sha256": hashlib.sha256(pcm).hexdigest(),
        }
    rms = math.sqrt(sum(value * value for value in samples) / len(samples)) / 32768.0
    peak = max(abs(value) for value in samples)
    return {
        "samples": len(samples),
        "duration_s": len(samples) / SAMPLE_RATE,
        "rms": rms,
        "peak_dbfs": 20.0 * math.log10(peak / 32768.0) if peak else float("-inf"),
        "dc_offset": (sum(samples) / len(samples)) / 32768.0,
        "clipped_samples": sum(abs(value) >= 32767 for value in samples),
        "sha256": hashlib.sha256(pcm).hexdigest(),
    }


def load_webrtc_factory():
    try:
        from webrtc_audio_processing import AudioProcessingModule
    except Exception as error:
        raise RuntimeError(
            "Cannot import webrtc_audio_processing.AudioProcessingModule. "
            "Use the previously validated Python 3.11 environment."
        ) from error

    def create(level: int):
        ap = AudioProcessingModule(
            aec_type=0,
            enable_ns=True,
            agc_type=0,
            enable_vad=False,
        )
        ap.set_stream_format(SAMPLE_RATE, 1)
        ap.set_ns_level(level)
        return ap

    return create


def apply_webrtc(pcm: bytes, level: int, factory=None) -> bytes:
    factory = factory or load_webrtc_factory()
    ap = factory(level)
    output = bytearray()
    for offset in range(0, len(pcm), WEBRTC_FRAME_BYTES):
        chunk = pcm[offset : offset + WEBRTC_FRAME_BYTES]
        valid = len(chunk)
        if valid < WEBRTC_FRAME_BYTES:
            chunk += b"\x00" * (WEBRTC_FRAME_BYTES - valid)
        result = ap.process_stream(chunk)
        if isinstance(result, str):
            result = result.encode("latin1")
        if not isinstance(result, (bytes, bytearray)) or len(result) != WEBRTC_FRAME_BYTES:
            raise RuntimeError("WebRTC APM returned an invalid frame")
        output.extend(result[:valid])
    return bytes(output)


def slice_pcm(pcm: bytes, start_s: float, end_s: float) -> bytes:
    if end_s <= start_s:
        raise ValueError("end_s must be greater than start_s")
    total_samples = len(pcm) // 2
    start = max(0, min(total_samples, round(start_s * SAMPLE_RATE)))
    end = max(start, min(total_samples, round(end_s * SAMPLE_RATE)))
    return pcm[start * 2 : end * 2]
