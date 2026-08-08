#!/usr/bin/env python3
"""Replay baseline and WebRTC NS variants through constrained and free-text Vosk."""

from __future__ import annotations

import argparse
import csv
import json
import sys
import wave
from pathlib import Path

SAMPLE_RATE = 16_000
CHUNK_BYTES = 1_280
RECORDING_IDS = ("1786194763609", "1786194978795")
VARIANTS = ("baseline", "webrtc_ns_low", "webrtc_ns_moderate", "webrtc_ns_high", "webrtc_ns_very_high")
MENU_GRAMMAR = [
    "вверх",
    "вниз",
    "выбрать",
    "печать ценников",
    "печать",
    "печать ценника",
    "доступность",
    "справка",
    "настройки",
    "[unk]",
]


def variant_path(audio_dir: Path, variant: str, recording_id: str) -> Path:
    if variant == "baseline":
        return audio_dir / f"baseline_ssp_{recording_id}.wav"
    return audio_dir / f"{variant}_{recording_id}.wav"


def load_audio(path: Path) -> bytes:
    with wave.open(str(path), "rb") as wav:
        actual = (wav.getframerate(), wav.getnchannels(), wav.getsampwidth(), wav.getcomptype())
        expected = (SAMPLE_RATE, 1, 2, "NONE")
        if actual != expected:
            raise ValueError(f"{path}: expected {expected}, got {actual}")
        return wav.readframes(wav.getnframes())


def replay(vosk, model, path: Path, variant: str, mode: str, events) -> dict[str, object]:
    grammar = json.dumps(MENU_GRAMMAR, ensure_ascii=False) if mode == "command_menu" else None
    recognizer = (
        vosk.KaldiRecognizer(model, SAMPLE_RATE, grammar)
        if grammar
        else vosk.KaldiRecognizer(model, SAMPLE_RATE)
    )
    recognizer.SetWords(True)
    audio = load_audio(path)
    endpoint_count = 0
    nonempty_final_count = 0
    empty_final_count = 0
    first_partial_ms = None

    for offset in range(0, len(audio), CHUNK_BYTES):
        timestamp_ms = offset * 1000 / (SAMPLE_RATE * 2)
        chunk = audio[offset : offset + CHUNK_BYTES]
        if recognizer.AcceptWaveform(chunk):
            result = json.loads(recognizer.Result())
            text = result.get("text", "")
            endpoint_count += 1
            nonempty_final_count += int(bool(text))
            empty_final_count += int(not text)
            event = "endpoint"
        else:
            result = json.loads(recognizer.PartialResult())
            text = result.get("partial", "")
            if text and first_partial_ms is None:
                first_partial_ms = timestamp_ms
            event = "partial"

        events.write(
            json.dumps(
                {
                    "file": path.name,
                    "variant": variant,
                    "mode": mode,
                    "audio_timestamp_ms": timestamp_ms,
                    "event": event,
                    "result": result,
                },
                ensure_ascii=False,
            )
            + "\n"
        )

    result = json.loads(recognizer.FinalResult())
    text = result.get("text", "")
    nonempty_final_count += int(bool(text))
    empty_final_count += int(not text)
    events.write(
        json.dumps(
            {
                "file": path.name,
                "variant": variant,
                "mode": mode,
                "audio_timestamp_ms": len(audio) * 1000 / (SAMPLE_RATE * 2),
                "event": "final",
                "result": result,
            },
            ensure_ascii=False,
        )
        + "\n"
    )

    return {
        "recording": path.stem.rsplit("_", 1)[-1],
        "file": path.name,
        "variant": variant,
        "mode": mode,
        "duration_ms": len(audio) * 1000 / (SAMPLE_RATE * 2),
        "endpoint_count": endpoint_count,
        "nonempty_final_count": nonempty_final_count,
        "empty_final_count": empty_final_count,
        "first_nonempty_partial_ms": "" if first_partial_ms is None else first_partial_ms,
        "terminal_final": text,
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", type=Path, required=True)
    parser.add_argument("--audio-dir", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument(
        "--python-deps",
        type=Path,
        help="Optional directory containing the vosk Python package.",
    )
    args = parser.parse_args()

    if args.python_deps:
        sys.path.insert(0, str(args.python_deps))
    import vosk

    args.output_dir.mkdir(parents=True, exist_ok=True)
    vosk.SetLogLevel(-1)
    model = vosk.Model(str(args.model))

    rows: list[dict[str, object]] = []
    events_path = args.output_dir / "ns_asr_events.jsonl"
    with events_path.open("w", encoding="utf-8") as events:
        for recording_id in RECORDING_IDS:
            for variant in VARIANTS:
                source = variant_path(args.audio_dir, variant, recording_id)
                if not source.is_file():
                    raise FileNotFoundError(source)
                for mode in ("command_menu", "free_text"):
                    rows.append(replay(vosk, model, source, variant, mode, events))

    summary_path = args.output_dir / "ns_recognition_summary.csv"
    with summary_path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=rows[0].keys())
        writer.writeheader()
        writer.writerows(rows)

    print(f"Wrote {events_path}")
    print(f"Wrote {summary_path}")


if __name__ == "__main__":
    main()
