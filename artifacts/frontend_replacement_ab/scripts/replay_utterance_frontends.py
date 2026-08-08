#!/usr/bin/env python3
"""Replay each utterance frontend through isolated Vosk recognizers."""

from __future__ import annotations

import argparse
import csv
import json
from pathlib import Path

from frontend_common import SAMPLE_RATE, read_wav

COMMAND_GRAMMAR = [
    "вверх", "вниз", "печать", "белый", "жёлтый", "назад", "доступность",
    "список", "безалкогольное", "святой", "источник", "напитки", "мобильный",
    "молочная", "коровка", "[unk]",
]
COMMANDS = set(COMMAND_GRAMMAR) - {"[unk]"}


def recognize(vosk, model, pcm: bytes, grammar: list[str] | None, chunk_bytes: int) -> dict[str, str]:
    recognizer = (
        vosk.KaldiRecognizer(model, SAMPLE_RATE, json.dumps(grammar, ensure_ascii=False))
        if grammar else vosk.KaldiRecognizer(model, SAMPLE_RATE)
    )
    endpoints: list[str] = []
    partials: list[str] = []
    for offset in range(0, len(pcm), chunk_bytes):
        if recognizer.AcceptWaveform(pcm[offset : offset + chunk_bytes]):
            text = json.loads(recognizer.Result()).get("text", "").strip()
            if text:
                endpoints.append(text)
        else:
            partial = json.loads(recognizer.PartialResult()).get("partial", "").strip()
            if partial and (not partials or partial != partials[-1]):
                partials.append(partial)
    final_text = json.loads(recognizer.FinalResult()).get("text", "").strip()
    terminal = endpoints + ([final_text] if final_text else [])
    return {
        "endpoint_texts": " | ".join(endpoints),
        "final_text": final_text,
        "terminal_sequence": " | ".join(terminal),
        "partials": " | ".join(partials),
    }


def command_tokens(text: str) -> list[str]:
    return [token for token in text.lower().replace("|", " ").split() if token in COMMANDS]


def classify(kind: str, expected: str, tokens: list[str]) -> str:
    if kind == "negative":
        return "correct_rejection" if not tokens else "false_activation"
    if not tokens:
        return "miss"
    if tokens == [expected]:
        return "correct"
    if expected in tokens:
        return "insertion"
    return "substitution" if len(tokens) == 1 else "multiple_wrong"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dataset-root", type=Path, required=True)
    parser.add_argument("--matrix-dir", type=Path, required=True)
    parser.add_argument("--model", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--chunk-bytes", type=int, default=2560)
    args = parser.parse_args()

    import vosk

    vosk.SetLogLevel(-1)
    model = vosk.Model(str(args.model))
    labels = {
        row["utterance_id"]: row
        for row in csv.DictReader((args.dataset_root / "manifest.csv").open(encoding="utf-8"))
    }
    matrix = list(csv.DictReader((args.matrix_dir / "utterance_frontend_manifest.csv").open(encoding="utf-8")))
    rows: list[dict[str, str]] = []
    for index, item in enumerate(matrix, 1):
        label = labels[item["utterance_id"]]
        pcm = read_wav(Path(item["path"]), expected_channels=1).frames
        for mode, grammar in (("command", COMMAND_GRAMMAR), ("free_text", None)):
            result = recognize(vosk, model, pcm, grammar, args.chunk_bytes)
            tokens = command_tokens(result["terminal_sequence"]) if mode == "command" else []
            rows.append(
                {
                    "utterance_id": item["utterance_id"],
                    "recording": label["recording"],
                    "kind": label["kind"],
                    "expected_type": label["expected_type"],
                    "expected_text": label["expected_text"],
                    "frontend": item["frontend"],
                    "mode": mode,
                    **result,
                    "command_tokens": " | ".join(tokens),
                    "classification": classify(label["kind"], label["expected_text"], tokens)
                    if mode == "command" else "diagnostic",
                }
            )
        if index % 100 == 0:
            print(f"Replayed {index}/{len(matrix)} frontend utterances", flush=True)

    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=rows[0].keys())
        writer.writeheader()
        writer.writerows(rows)
    print(f"Wrote {len(rows)} predictions to {args.output}")


if __name__ == "__main__":
    main()
