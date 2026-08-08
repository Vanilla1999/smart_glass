#!/usr/bin/env python3
"""Build deduplicated fixed evaluation windows with independent controls."""

from __future__ import annotations

import argparse
import csv
from collections import defaultdict
from dataclasses import dataclass
from pathlib import Path

from frontend_common import RECORDING_IDS, read_wav


@dataclass
class Window:
    recording: str
    start: float
    end: float
    source: str
    keywords: set[str]

    def overlaps_or_near(self, other: "Window", gap: float) -> bool:
        return self.recording == other.recording and other.start <= self.end + gap

    def merge(self, other: "Window") -> None:
        self.start = min(self.start, other.start)
        self.end = max(self.end, other.end)
        self.keywords.update(other.keywords)
        if self.source != other.source:
            self.source = "mixed"


def parse_keywords(value: str) -> set[str]:
    return {item.strip() for item in value.split(";") if item.strip()}


def read_disputed(path: Path) -> list[Window]:
    windows: list[Window] = []
    with path.open(newline="", encoding="utf-8") as handle:
        for row in csv.DictReader(handle):
            windows.append(
                Window(
                    recording=row["recording"],
                    start=float(row["start_s"]),
                    end=float(row["end_s"]),
                    source="disputed",
                    keywords=parse_keywords(row.get("contains_keyword_candidate", "")),
                )
            )
    return windows


def merge_windows(windows: list[Window], gap: float, max_duration: float) -> list[Window]:
    result: list[Window] = []
    for window in sorted(windows, key=lambda item: (item.recording, item.start, item.end)):
        if result and result[-1].overlaps_or_near(window, gap):
            candidate_end = max(result[-1].end, window.end)
            if candidate_end - result[-1].start <= max_duration:
                result[-1].merge(window)
                continue
            # The previous bounded window already covers any overlap. Keep the
            # uncovered tail only instead of duplicating audio across windows.
            window.start = max(window.start, result[-1].end)
            if window.start >= window.end:
                continue
        result.append(Window(window.recording, window.start, window.end, window.source, set(window.keywords)))
    return result


def add_controls(
    existing: list[Window],
    durations: dict[str, float],
    interval: float,
    duration: float,
    guard: float,
) -> list[Window]:
    result = list(existing)
    for recording, total in durations.items():
        center = interval / 2.0
        while center + duration / 2.0 <= total:
            start = center - duration / 2.0
            end = center + duration / 2.0
            conflict = any(
                item.recording == recording
                and not (end + guard <= item.start or start - guard >= item.end)
                for item in existing
            )
            if not conflict:
                result.append(Window(recording, start, end, "uniform_control", set()))
            center += interval
    return sorted(result, key=lambda item: (item.recording, item.start, item.end))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--labeling-manifest", type=Path, required=True)
    parser.add_argument("--matrix-dir", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--merge-gap", type=float, default=0.75)
    parser.add_argument("--max-window", type=float, default=6.0)
    parser.add_argument("--control-interval", type=float, default=15.0)
    parser.add_argument("--control-duration", type=float, default=2.0)
    args = parser.parse_args()

    disputed = read_disputed(args.labeling_manifest)
    merged = merge_windows(disputed, args.merge_gap, args.max_window)

    durations: dict[str, float] = {}
    for recording in RECORDING_IDS:
        variant_paths = list(args.matrix_dir.glob(f"*_{recording}.wav"))
        if not variant_paths:
            raise FileNotFoundError(f"No matrix WAVs for {recording}")
        durations[recording] = min(read_wav(path, expected_channels=1).frame_count for path in variant_paths) / 16000.0

    windows = add_controls(
        merged,
        durations,
        args.control_interval,
        args.control_duration,
        guard=0.5,
    )

    args.output.parent.mkdir(parents=True, exist_ok=True)
    fieldnames = [
        "window_id",
        "recording",
        "start_s",
        "end_s",
        "duration_s",
        "source",
        "keywords",
        "expected_type",
        "expected_text",
        "notes",
    ]
    with args.output.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        for index, window in enumerate(windows, start=1):
            writer.writerow(
                {
                    "window_id": f"win_{index:03d}",
                    "recording": window.recording,
                    "start_s": f"{window.start:.3f}",
                    "end_s": f"{window.end:.3f}",
                    "duration_s": f"{window.end - window.start:.3f}",
                    "source": window.source,
                    "keywords": ";".join(sorted(window.keywords)),
                    "expected_type": "unlabeled",
                    "expected_text": "",
                    "notes": "",
                }
            )

    disputed_count = sum(item.source != "uniform_control" for item in windows)
    control_count = sum(item.source == "uniform_control" for item in windows)
    print(
        f"Wrote {len(windows)} windows: disputed={disputed_count}, "
        f"controls={control_count}, total_duration={sum(w.end-w.start for w in windows):.3f}s"
    )


if __name__ == "__main__":
    main()
