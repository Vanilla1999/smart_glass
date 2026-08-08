#!/usr/bin/env python3
"""Create reproducible changed-hypothesis and keyword extracts from Vosk events."""

from __future__ import annotations

import argparse
import csv
import json
import re
from collections import defaultdict
from pathlib import Path

VARIANTS = ("baseline", "webrtc_ns_low", "webrtc_ns_moderate", "webrtc_ns_high", "webrtc_ns_very_high")
KEYWORDS = re.compile(r"ж[её]лт|доступн|вверх|вниз|печать|бел|назад|список|коровк|молоч", re.IGNORECASE)


def text_of(event: dict[str, object]) -> str:
    result = event["result"]
    assert isinstance(result, dict)
    return str(result.get("partial", result.get("text", "")))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--events", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args()
    args.output_dir.mkdir(parents=True, exist_ok=True)

    by_time: dict[tuple[str, str, float], dict[str, str]] = defaultdict(dict)
    keyword_rows: list[dict[str, object]] = []
    terminal_rows: list[dict[str, object]] = []
    for line in args.events.read_text(encoding="utf-8").splitlines():
        event = json.loads(line)
        text = text_of(event)
        recording = str(event["file"]).rsplit("_", 1)[-1].removesuffix(".wav")
        key = (recording, str(event["mode"]), float(event["audio_timestamp_ms"]))
        by_time[key][str(event["variant"])] = f"{event['event']}:{text}"
        if text and KEYWORDS.search(text):
            keyword_rows.append(
                {
                    "recording": recording,
                    "mode": event["mode"],
                    "variant": event["variant"],
                    "timestamp": event["audio_timestamp_ms"],
                    "event": event["event"],
                    "text": text,
                }
            )
        if text and event["event"] in ("endpoint", "final"):
            terminal_rows.append(
                {
                    "recording": recording,
                    "mode": event["mode"],
                    "variant": event["variant"],
                    "timestamp": event["audio_timestamp_ms"],
                    "event": event["event"],
                    "text": text,
                }
            )

    deltas: list[dict[str, object]] = []
    for (recording, mode, timestamp), values in sorted(by_time.items()):
        texts = [values.get(variant, "") for variant in VARIANTS]
        if len(set(texts)) == 1:
            continue
        deltas.append(
            {
                "recording": recording,
                "mode": mode,
                "timestamp": timestamp,
                "baseline_text": values.get("baseline", ""),
                "low_text": values.get("webrtc_ns_low", ""),
                "moderate_text": values.get("webrtc_ns_moderate", ""),
                "high_text": values.get("webrtc_ns_high", ""),
                "very_high_text": values.get("webrtc_ns_very_high", ""),
                "classification": "different_unclear",
            }
        )

    for name, rows in (
        ("ns_variant_deltas.csv", deltas),
        ("ns_keyword_events.csv", keyword_rows),
        ("ns_terminal_events.csv", terminal_rows),
    ):
        with (args.output_dir / name).open("w", newline="", encoding="utf-8") as handle:
            writer = csv.DictWriter(handle, fieldnames=rows[0].keys() if rows else {
                "ns_variant_deltas.csv": ["recording", "mode", "timestamp", "baseline_text", "low_text", "moderate_text", "high_text", "very_high_text", "classification"],
                "ns_keyword_events.csv": ["recording", "mode", "variant", "timestamp", "event", "text"],
                "ns_terminal_events.csv": ["recording", "mode", "variant", "timestamp", "event", "text"],
            }[name])
            writer.writeheader()
            writer.writerows(rows)
    print(f"deltas={len(deltas)} keywords={len(keyword_rows)} terminal_events={len(terminal_rows)}")


if __name__ == "__main__":
    main()
