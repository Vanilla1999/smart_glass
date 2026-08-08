#!/usr/bin/env python3
"""Replay identical fixed windows through a fresh Vosk recognizer per variant."""

from __future__ import annotations

import argparse
import csv
import json
import wave
from pathlib import Path

from frontend_common import SAMPLE_RATE, read_wav, slice_pcm

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
    "белый",
    "жёлтый",
    "назад",
    "список",
    "[unk]",
]


def load_windows(path: Path) -> list[dict[str, str]]:
    with path.open(newline="", encoding="utf-8") as handle:
        return list(csv.DictReader(handle))


def replay(vosk, model, pcm: bytes, grammar: list[str] | None, chunk_bytes: int) -> tuple[str, list[dict]]:
    recognizer = (
        vosk.KaldiRecognizer(model, SAMPLE_RATE, json.dumps(grammar, ensure_ascii=False))
        if grammar
        else vosk.KaldiRecognizer(model, SAMPLE_RATE)
    )
    recognizer.SetWords(True)
    events: list[dict] = []
    for offset in range(0, len(pcm), chunk_bytes):
        chunk = pcm[offset : offset + chunk_bytes]
        if recognizer.AcceptWaveform(chunk):
            result = json.loads(recognizer.Result())
            events.append({"offset_bytes": offset, "event": "endpoint", "result": result})
        else:
            result = json.loads(recognizer.PartialResult())
            events.append({"offset_bytes": offset, "event": "partial", "result": result})
    final = json.loads(recognizer.FinalResult())
    events.append({"offset_bytes": len(pcm), "event": "final", "result": final})
    endpoint_texts = [
        event["result"].get("text", "")
        for event in events
        if event["event"] in {"endpoint", "final"} and event["result"].get("text", "")
    ]
    return " | ".join(endpoint_texts), events


def classify(expected_type: str, expected_text: str, text: str) -> str:
    normalized = " ".join(text.lower().strip().split())
    expected = " ".join(expected_text.lower().strip().split())
    if expected_type == "command":
        if not normalized:
            return "miss"
        return "correct" if normalized == expected else "wrong"
    if expected_type in {"background_speech", "silence"}:
        return "correct_rejection" if not normalized else "false_activation"
    return "unscored"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", type=Path, required=True)
    parser.add_argument("--matrix-dir", type=Path, required=True)
    parser.add_argument("--windows", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--chunk-bytes", type=int, default=2560)
    args = parser.parse_args()

    import vosk

    args.output_dir.mkdir(parents=True, exist_ok=True)
    vosk.SetLogLevel(-1)
    model = vosk.Model(str(args.model))
    windows = load_windows(args.windows)

    # Discover variants from filenames instead of hard-coding the matrix.
    recordings = sorted({row["recording"] for row in windows})
    variants_by_recording: dict[str, dict[str, Path]] = {}
    for recording in recordings:
        mapping = {}
        for path in args.matrix_dir.glob(f"*_{recording}.wav"):
            variant = path.name[: -(len(recording) + 5)]
            mapping[variant] = path
        if not mapping:
            raise FileNotFoundError(f"No variants for {recording}")
        variants_by_recording[recording] = mapping

    rows: list[dict[str, object]] = []
    events_path = args.output_dir / "fixed_window_asr_events.jsonl"
    with events_path.open("w", encoding="utf-8") as event_handle:
        for window in windows:
            recording = window["recording"]
            start = float(window["start_s"])
            end = float(window["end_s"])
            for variant, path in sorted(variants_by_recording[recording].items()):
                pcm = slice_pcm(read_wav(path, expected_channels=1).frames, start, end)
                for mode, grammar in (("command_menu", MENU_GRAMMAR), ("free_text", None)):
                    text, events = replay(vosk, model, pcm, grammar, args.chunk_bytes)
                    result_class = (
                        classify(window["expected_type"], window["expected_text"], text)
                        if mode == "command_menu"
                        else "unscored"
                    )
                    rows.append(
                        {
                            "window_id": window["window_id"],
                            "recording": recording,
                            "start_s": start,
                            "end_s": end,
                            "source": window["source"],
                            "expected_type": window["expected_type"],
                            "expected_text": window["expected_text"],
                            "variant": variant,
                            "mode": mode,
                            "terminal_text": text,
                            "classification": result_class,
                        }
                    )
                    for event in events:
                        event_handle.write(
                            json.dumps(
                                {
                                    "window_id": window["window_id"],
                                    "recording": recording,
                                    "variant": variant,
                                    "mode": mode,
                                    **event,
                                },
                                ensure_ascii=False,
                            )
                            + "\n"
                        )

    summary_path = args.output_dir / "fixed_window_asr_summary.csv"
    with summary_path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=rows[0].keys())
        writer.writeheader()
        writer.writerows(rows)

    print(f"Wrote {summary_path}")
    print(f"Wrote {events_path}")


if __name__ == "__main__":
    main()
