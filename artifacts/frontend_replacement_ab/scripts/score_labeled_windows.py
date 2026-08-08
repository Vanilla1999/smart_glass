#!/usr/bin/env python3
"""Aggregate labeled fixed-window command results by frontend."""

from __future__ import annotations

import argparse
import csv
from collections import Counter, defaultdict
from pathlib import Path


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--summary", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    counters: dict[str, Counter] = defaultdict(Counter)
    with args.summary.open(newline="", encoding="utf-8") as handle:
        for row in csv.DictReader(handle):
            if row["mode"] != "command_menu" or row["classification"] == "unscored":
                continue
            counters[row["variant"]][row["classification"]] += 1

    fieldnames = [
        "variant",
        "correct",
        "miss",
        "wrong",
        "false_activation",
        "correct_rejection",
        "scored_total",
    ]
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        for variant in sorted(counters):
            counter = counters[variant]
            total = sum(counter.values())
            writer.writerow(
                {
                    "variant": variant,
                    "correct": counter["correct"],
                    "miss": counter["miss"],
                    "wrong": counter["wrong"],
                    "false_activation": counter["false_activation"],
                    "correct_rejection": counter["correct_rejection"],
                    "scored_total": total,
                }
            )

    print(f"Wrote {args.output}")


if __name__ == "__main__":
    main()
