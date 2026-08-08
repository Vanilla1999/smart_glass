#!/usr/bin/env python3
"""Score utterance predictions and compare each frontend with legacy."""

from __future__ import annotations

import argparse
import csv
import math
from collections import Counter, defaultdict
from pathlib import Path

CLASSES = ("correct", "miss", "substitution", "insertion", "multiple_wrong")


def write_csv(path: Path, rows: list[dict[str, object]]) -> None:
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=rows[0].keys())
        writer.writeheader()
        writer.writerows(rows)


def mcnemar_p(b: int, c: int) -> float:
    n = b + c
    if not n:
        return 1.0
    tail = sum(math.comb(n, k) for k in range(0, min(b, c) + 1)) / (2**n)
    return min(1.0, 2.0 * tail)


def delta_class(legacy: str, candidate: str, kind: str) -> str:
    if kind == "negative":
        if legacy == candidate == "correct_rejection": return "unchanged_correct"
        if legacy == candidate == "false_activation": return "unchanged_wrong"
        if legacy == "false_activation": return "removed_false_activation"
        return "added_false_activation"
    if legacy == candidate == "correct": return "unchanged_correct"
    if legacy == candidate: return "unchanged_wrong"
    if legacy != "correct" and candidate == "correct": return "fixed_legacy_error"
    if legacy == "correct" and candidate != "correct": return "regressed_from_legacy"
    return "different_error"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--predictions", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args()
    rows = [row for row in csv.DictReader(args.predictions.open(encoding="utf-8")) if row["mode"] == "command"]
    grouped: dict[str, list[dict[str, str]]] = defaultdict(list)
    by_key: dict[tuple[str, str], dict[str, str]] = {}
    for row in rows:
        grouped[row["frontend"]].append(row)
        by_key[(row["frontend"], row["utterance_id"])] = row

    scores: list[dict[str, object]] = []
    for frontend, items in sorted(grouped.items()):
        commands = [row for row in items if row["kind"] == "command"]
        negatives = [row for row in items if row["kind"] == "negative"]
        counts = Counter(row["classification"] for row in items)
        scores.append({
            "frontend": frontend,
            "command_total": len(commands),
            "strict_correct": counts["correct"],
            "relaxed_correct": counts["correct"],
            "miss": counts["miss"],
            "substitution": counts["substitution"],
            "insertion": counts["insertion"],
            "multiple_wrong": counts["multiple_wrong"],
            "negative_total": len(negatives),
            "correct_rejection": counts["correct_rejection"],
            "false_activation": counts["false_activation"],
            "strict_command_accuracy": counts["correct"] / len(commands),
            "relaxed_command_accuracy": counts["correct"] / len(commands),
            "command_error_rate": 1 - counts["correct"] / len(commands),
            "false_activation_rate": counts["false_activation"] / len(negatives),
        })

    legacy = {row["utterance_id"]: row for row in grouped["legacy_reference"]}
    deltas: list[dict[str, object]] = []
    pair_stats: list[dict[str, object]] = []
    for frontend in sorted(grouped):
        fixed = regressed = 0
        for row in grouped[frontend]:
            old = legacy[row["utterance_id"]]
            delta = delta_class(old["classification"], row["classification"], row["kind"])
            if delta in {"fixed_legacy_error", "removed_false_activation"}: fixed += 1
            if delta in {"regressed_from_legacy", "added_false_activation"}: regressed += 1
            deltas.append({
                "utterance_id": row["utterance_id"],
                "expected_type": row["expected_type"],
                "expected_text": row["expected_text"],
                "legacy_result": old["classification"],
                "candidate_result": row["classification"],
                "candidate": frontend,
                "delta_class": delta,
            })
        pair_stats.append({"frontend": frontend, "improvements": fixed, "regressions": regressed,
                           "mcnemar_exact_p": mcnemar_p(fixed, regressed)})

    keyword_rows: list[dict[str, object]] = []
    keywords = sorted({row["expected_text"] for row in rows if row["kind"] == "command"})
    for frontend in sorted(grouped):
        for keyword in keywords:
            items = [row for row in grouped[frontend] if row["expected_text"] == keyword]
            counts = Counter(row["classification"] for row in items)
            keyword_rows.append({"frontend": frontend, "keyword": keyword, "total": len(items),
                                 "correct": counts["correct"], "miss": counts["miss"],
                                 "substitution": counts["substitution"], "insertion": counts["insertion"],
                                 "multiple_wrong": counts["multiple_wrong"]})

    args.output_dir.mkdir(parents=True, exist_ok=True)
    write_csv(args.output_dir / "final_frontend_scores.csv", scores)
    write_csv(args.output_dir / "final_keyword_scores.csv", keyword_rows)
    write_csv(args.output_dir / "pairwise_deltas.csv", deltas)
    write_csv(args.output_dir / "pairwise_stats.csv", pair_stats)
    print(f"Scored {len(grouped)} frontends across {len(rows)} command-mode predictions")


if __name__ == "__main__":
    main()
