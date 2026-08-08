#!/usr/bin/env python3
"""Shared helpers for the continuous frontend benchmark."""

from __future__ import annotations

import math
from dataclasses import dataclass
from typing import Iterable

SAMPLE_RATE = 16_000
COMMANDS = {
    "вверх", "вниз", "печать", "белый", "жёлтый", "назад", "доступность",
    "список", "безалкогольное", "святой", "источник", "напитки", "мобильный",
    "молочная", "коровка",
}
IMMEDIATE_PARTIALS = {"вверх", "вниз"}


@dataclass(frozen=True)
class Region:
    start_s: float
    end_s: float


def evaluation_region(start_s: float, end_s: float, duration_s: float) -> Region:
    return Region(max(0.0, start_s - 0.3), min(duration_s, end_s + 1.0))


def merge_regions(regions: Iterable[Region]) -> list[Region]:
    result: list[Region] = []
    for region in sorted(regions, key=lambda item: item.start_s):
        if result and region.start_s <= result[-1].end_s:
            result[-1] = Region(result[-1].start_s, max(result[-1].end_s, region.end_s))
        else:
            result.append(region)
    return result


def subtract_regions(duration_s: float, excluded: Iterable[Region]) -> list[Region]:
    background: list[Region] = []
    cursor = 0.0
    for region in merge_regions(excluded):
        if region.start_s > cursor:
            background.append(Region(cursor, region.start_s))
        cursor = max(cursor, region.end_s)
    if cursor < duration_s:
        background.append(Region(cursor, duration_s))
    return background


def in_regions(timestamp_s: float, regions: Iterable[Region]) -> bool:
    return any(region.start_s <= timestamp_s <= region.end_s for region in regions)


def command_tokens(text: str) -> list[str]:
    return [token for token in text.lower().replace("|", " ").split() if token in COMMANDS]


def first_expected_time(events: list[dict], expected: str, start_s: float) -> float | None:
    for event in events:
        if expected in command_tokens(event.get("partial", "") or event.get("text", "")):
            return (float(event["timestamp_end_s"]) - start_s) * 1000.0
    return None


def stable_expected_time(
    events: list[dict], expected: str, start_s: float, stable_ms: float = 150.0
) -> float | None:
    candidate_start: float | None = None
    for event in events:
        if event["event_type"] != "partial":
            continue
        timestamp = float(event["timestamp_end_s"])
        tokens = command_tokens(event.get("partial", ""))
        if tokens == [expected]:
            candidate_start = timestamp if candidate_start is None else candidate_start
            if (timestamp - candidate_start) * 1000.0 >= stable_ms:
                return (candidate_start + stable_ms / 1000.0 - start_s) * 1000.0
        else:
            candidate_start = None
    return None


def duplicate_action_count(action_times: Iterable[float], region: Region) -> int:
    count = sum(region.start_s <= timestamp <= region.end_s for timestamp in action_times)
    return max(0, count - 1)


def deduplicate_hard_negatives(
    events: Iterable[tuple[str, float, str, str]], pre_s: float = 1.0, post_s: float = 1.5
) -> list[dict[str, object]]:
    grouped: dict[str, list[dict[str, object]]] = {}
    for frontend, timestamp, command, recording in sorted(events, key=lambda item: (item[3], item[1])):
        intervals = grouped.setdefault(recording, [])
        start, end = max(0.0, timestamp - pre_s), timestamp + post_s
        if intervals and start <= float(intervals[-1]["end_s"]):
            intervals[-1]["end_s"] = max(float(intervals[-1]["end_s"]), end)
            intervals[-1]["frontends"].add(frontend)
            intervals[-1]["commands"].add(command)
        else:
            intervals.append({"recording": recording, "start_s": start, "end_s": end,
                              "frontends": {frontend}, "commands": {command}})
    return [item for recording in sorted(grouped) for item in grouped[recording]]


def false_actions_per_minute(count: int, background_seconds: float) -> float:
    return count / (background_seconds / 60.0) if background_seconds > 0 else math.inf


def pairwise_delta(legacy: dict, candidate: dict) -> str:
    if legacy["detected"] == "false" and candidate["detected"] == "true":
        return "fixed_legacy_miss"
    if legacy["detected"] == "true" and candidate["detected"] == "false":
        return "regressed_from_legacy"
    if int(legacy["wrong_actionable_partial"]) > int(candidate["wrong_actionable_partial"]):
        return "removed_wrong_partial"
    if int(legacy["wrong_actionable_partial"]) < int(candidate["wrong_actionable_partial"]):
        return "added_wrong_partial"
    legacy_latency = _float_or_none(legacy.get("stable_partial_latency_ms"))
    candidate_latency = _float_or_none(candidate.get("stable_partial_latency_ms"))
    if legacy_latency is not None and candidate_latency is not None:
        if candidate_latency <= legacy_latency - 100.0:
            return "faster_stable_partial"
        if candidate_latency >= legacy_latency + 100.0:
            return "slower_stable_partial"
    return "unchanged"


def _float_or_none(value: object) -> float | None:
    return None if value in (None, "") else float(value)
