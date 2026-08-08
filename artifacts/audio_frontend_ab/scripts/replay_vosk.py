#!/usr/bin/env python3
"""Offline Vosk replay using the repository model and extracted production menu grammar."""

import argparse
import csv
import json
import sys
import wave
from pathlib import Path


SAMPLE_RATE = 16000
CHUNK_BYTES = 1280  # Production command recognizer batches four 20 ms / 640-byte frames.
MENU_GRAMMAR = [
    "вверх", "вниз", "выбрать", "печать ценников", "печать", "печать ценника",
    "доступность", "справка", "настройки", "[unk]",
]


def load_audio(path):
    with wave.open(str(path), "rb") as wav:
        assert wav.getframerate() == SAMPLE_RATE and wav.getnchannels() == 1 and wav.getsampwidth() == 2
        return wav.readframes(wav.getnframes())


def replay(vosk, model, path, mode, events):
    grammar = json.dumps(MENU_GRAMMAR, ensure_ascii=False) if mode == "command_menu" else None
    recognizer = vosk.KaldiRecognizer(model, SAMPLE_RATE, grammar) if grammar else vosk.KaldiRecognizer(model, SAMPLE_RATE)
    recognizer.SetWords(True)
    audio = load_audio(path)
    endpoints = nonempty_finals = empty_finals = 0
    first_partial = None
    for offset in range(0, len(audio), CHUNK_BYTES):
        timestamp_ms = offset * 1000 / (SAMPLE_RATE * 2)
        chunk = audio[offset:offset + CHUNK_BYTES]
        if recognizer.AcceptWaveform(chunk):
            result = json.loads(recognizer.Result())
            text = result.get("text", "")
            events.write(json.dumps({"file": path.name, "mode": mode, "audio_timestamp_ms": timestamp_ms, "event": "endpoint", "result": result}, ensure_ascii=False) + "\n")
            endpoints += 1
            nonempty_finals += bool(text)
            empty_finals += not bool(text)
        else:
            result = json.loads(recognizer.PartialResult())
            text = result.get("partial", "")
            if text and first_partial is None:
                first_partial = timestamp_ms
            events.write(json.dumps({"file": path.name, "mode": mode, "audio_timestamp_ms": timestamp_ms, "event": "partial", "result": result}, ensure_ascii=False) + "\n")
    result = json.loads(recognizer.FinalResult())
    text = result.get("text", "")
    events.write(json.dumps({"file": path.name, "mode": mode, "audio_timestamp_ms": len(audio) * 1000 / (SAMPLE_RATE * 2), "event": "final", "result": result}, ensure_ascii=False) + "\n")
    nonempty_finals += bool(text)
    empty_finals += not bool(text)
    return {"file": path.name, "mode": mode, "duration_ms": len(audio) * 1000 / (SAMPLE_RATE * 2), "endpoint_count": endpoints, "nonempty_final_count": nonempty_finals, "empty_final_count": empty_finals, "first_nonempty_partial_ms": "" if first_partial is None else first_partial, "terminal_final": text}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", type=Path, required=True)
    parser.add_argument("--audio-dir", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.output_dir / "python_deps"))
    import vosk

    args.output_dir.mkdir(parents=True, exist_ok=True)
    vosk.SetLogLevel(-1)
    model = vosk.Model(str(args.model))
    sources = []
    for identifier in ("1786194763609", "1786194978795"):
        sources.extend([
            args.audio_dir / f"ssp_mono_{identifier}.wav",
            args.output_dir / f"legacy_denoised_{identifier}.wav",
            args.output_dir / f"aligned_denoised_{identifier}.wav",
        ])
    rows = []
    with (args.output_dir / "asr_events.jsonl").open("w") as events:
        for source in sources:
            for mode in ("command_menu", "free_text"):
                rows.append(replay(vosk, model, source, mode, events))
    with (args.output_dir / "recognition_summary.csv").open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=rows[0].keys())
        writer.writeheader()
        writer.writerows(rows)


if __name__ == "__main__":
    main()
