#!/usr/bin/env python3
"""Score continuous Vosk events against full-recording command timestamps."""

from __future__ import annotations

import argparse
import csv
import json
import random
import statistics
import wave
from collections import Counter, defaultdict
from pathlib import Path

from continuous_common import (
    IMMEDIATE_PARTIALS, Region, command_tokens, deduplicate_hard_negatives,
    duplicate_action_count, evaluation_region, false_actions_per_minute,
    first_expected_time, in_regions, pairwise_delta, stable_expected_time,
    subtract_regions,
)


def percentile(values: list[float], fraction: float) -> float | None:
    if not values: return None
    values = sorted(values); index = (len(values) - 1) * fraction
    low = int(index); high = min(len(values) - 1, low + 1); weight = index - low
    return values[low] * (1 - weight) + values[high] * weight


def bootstrap_median_ci(values: list[float], seed: int = 7) -> tuple[float | None, float | None]:
    if not values: return None, None
    rng = random.Random(seed); samples = []
    for _ in range(2000):
        samples.append(statistics.median(rng.choice(values) for _ in values))
    return percentile(samples, 0.025), percentile(samples, 0.975)


def write_csv(path: Path, rows: list[dict]) -> None:
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=rows[0].keys()); writer.writeheader(); writer.writerows(rows)


def speech_bounds(row: dict) -> tuple[float, float]:
    # dataset_summary.json: clips include 220 ms pre-roll and 360 ms post-roll.
    return float(row["start_s_ssp"]) + 0.220, float(row["end_s_ssp"]) - 0.360


def event_owner(event: dict, token: str, command_rows: list[dict], durations: dict[str, float]) -> str | None:
    timestamp = float(event["timestamp_end_s"])
    candidates = []
    for row in command_rows:
        if row["recording"] != event["recording"] or row["expected_text"] != token:
            continue
        start, end = speech_bounds(row)
        region = evaluation_region(start, end, durations[row["recording"]])
        if region.start_s <= timestamp <= region.end_s:
            candidates.append((abs(timestamp - float(row["start_s_ssp"])), row["utterance_id"]))
    return min(candidates)[1] if candidates else None


def build_occurrence_owners(events: list[dict], command_rows: list[dict], durations: dict[str, float]) -> dict[tuple, str]:
    owners: dict[tuple, str] = {}
    streams: dict[tuple, list[dict]] = defaultdict(list)
    for event in events:
        streams[(event["recording"], event["frontend"], event["mode"])].append(event)
    for (recording, frontend, mode), stream in streams.items():
        for token in sorted({row["expected_text"] for row in command_rows if row["recording"] == recording}):
            occurrences: dict[int, list[float]] = defaultdict(list)
            for event in stream:
                if token in command_tokens(event.get("partial", "") or event.get("text", "")):
                    occurrences[int(event["utterance_id"])].append(float(event["timestamp_end_s"]))
            available = [row for row in command_rows if row["recording"] == recording and row["expected_text"] == token]
            for utterance, timestamps in sorted(occurrences.items(), key=lambda item: min(item[1])):
                timestamp = min(timestamps)
                candidates = []
                for row in available:
                    start, end = speech_bounds(row)
                    region = evaluation_region(start, end, durations[recording])
                    if region.start_s <= timestamp <= region.end_s:
                        candidates.append((abs(timestamp - float(row["start_s_ssp"])), row))
                if candidates:
                    selected = min(candidates, key=lambda item: item[0])[1]
                    owners[(recording, frontend, mode, utterance, token)] = selected["utterance_id"]
                    available.remove(selected)
    return owners


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--events", type=Path, nargs="+", required=True)
    parser.add_argument("--dataset-root", type=Path, required=True)
    parser.add_argument("--matrix-dir", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args(); args.output_dir.mkdir(parents=True, exist_ok=True)
    labels = list(csv.DictReader((args.dataset_root / "manifest.csv").open(encoding="utf-8")))
    commands = [row for row in labels if row["kind"] == "command" and row.get("manual_status", "confirmed") != "unclear"]
    events = [
        json.loads(line)
        for path in args.events
        for line in path.open(encoding="utf-8")
    ]
    grouped: dict[tuple[str, str, str], list[dict]] = defaultdict(list)
    for event in events: grouped[(event["recording"], event["frontend"], event["mode"])].append(event)
    frontends = sorted({event["frontend"] for event in events}); modes = sorted({event["mode"] for event in events})
    durations = {}
    for recording in sorted({row["recording"] for row in labels}):
        with wave.open(str(args.matrix_dir / f"legacy_reference_{recording}.wav"), "rb") as wav:
            durations[recording] = wav.getnframes() / wav.getframerate()
    regions_by_recording = {
        recording: [evaluation_region(*speech_bounds(row), durations[recording])
                    for row in commands if row["recording"] == recording]
        for recording in durations
    }
    background = {recording: subtract_regions(durations[recording], regions) for recording, regions in regions_by_recording.items()}
    occurrence_owners = build_occurrence_owners(events, commands, durations)

    outcomes = []
    action_times: dict[tuple[str, str, str], list[float]] = defaultdict(list)
    background_triggers = []
    false_rows = []
    for recording in durations:
        for frontend in frontends:
            for mode in modes:
                stream = grouped[(recording, frontend, mode)]; seen_actions = set(); false_partial = false_final = 0
                for event in stream:
                    tokens = command_tokens(event.get("partial", "") or event.get("text", ""))
                    actionable = []
                    if event["event_type"] == "partial": actionable = [token for token in tokens if token in IMMEDIATE_PARTIALS]
                    elif event["event_type"] in {"endpoint", "forced_final", "final"}: actionable = tokens
                    key = event["utterance_id"]
                    if actionable and key not in seen_actions:
                        seen_actions.add(key); timestamp = float(event["timestamp_end_s"])
                        action_times[(recording, frontend, mode)].append(timestamp)
                        owned = any((recording, frontend, mode, int(key), token) in occurrence_owners for token in actionable)
                        if not owned and in_regions(timestamp, background[recording]):
                            if event["event_type"] == "partial": false_partial += 1
                            else: false_final += 1
                            for token in actionable: background_triggers.append((frontend, timestamp, token, recording))
                bg_seconds = sum(region.end_s-region.start_s for region in background[recording])
                false_rows.append({"recording": recording, "frontend": frontend, "mode": mode,
                                   "background_seconds": bg_seconds, "false_actionable_partials": false_partial,
                                   "false_final_commands": false_final, "false_actions_per_minute":
                                   false_actions_per_minute(false_partial+false_final, bg_seconds)})

    for row in commands:
        recording = row["recording"]; expected = row["expected_text"]
        command_start, command_end = speech_bounds(row)
        region = evaluation_region(command_start, command_end, durations[recording])
        for frontend in frontends:
            for mode in modes:
                selected = [event for event in grouped[(recording, frontend, mode)]
                            if region.start_s <= float(event["timestamp_end_s"]) <= region.end_s]
                def owned_by_row(event: dict) -> bool:
                    return occurrence_owners.get((recording, frontend, mode, int(event["utterance_id"]), expected)) == row["utterance_id"]
                expected_events = [event for event in selected if expected in command_tokens(event.get("partial", "") or event.get("text", "")) and owned_by_row(event)]
                owned_selected = []
                for event in selected:
                    if expected in command_tokens(event.get("partial", "") or event.get("text", "")) and not owned_by_row(event):
                        event = {**event, "partial": "", "text": ""}
                    owned_selected.append(event)
                first = first_expected_time(owned_selected, expected, command_start)
                stable = stable_expected_time(owned_selected, expected, command_start)
                wrong = len({(int(event["utterance_id"]), token) for event in selected
                             if event["event_type"] == "partial"
                             for token in command_tokens(event.get("partial", ""))
                             if token in IMMEDIATE_PARTIALS and token != expected})
                endpoint = next((float(event["timestamp_end_s"])-command_end for event in expected_events
                                 if event["event_type"] in {"endpoint", "forced_final", "final"}), None)
                outcomes.append({"utterance_id": row["utterance_id"], "recording": recording,
                                 "expected_text": expected, "frontend": frontend, "mode": mode,
                                 "detected": str(bool(expected_events)).lower(),
                                 "wrong_actionable_partial": wrong,
                                 "first_partial_latency_ms": "" if first is None else first,
                                 "stable_partial_latency_ms": "" if stable is None else stable,
                                 "endpoint_latency_ms": "" if endpoint is None else endpoint*1000,
                                 "duplicate_activation": max(0, len({int(event["utterance_id"]) for event in expected_events if
                                     event["event_type"] in {"endpoint", "forced_final", "final"} or
                                     (event["event_type"] == "partial" and expected in IMMEDIATE_PARTIALS)}) - 1)})

    score_rows=[]; latency_rows=[]; keyword_rows=[]
    for frontend in frontends:
        for mode in modes:
            items=[row for row in outcomes if row["frontend"]==frontend and row["mode"]==mode]
            score_rows.append({"frontend":frontend,"mode":mode,"command_total":len(items),
                               "command_detected":sum(row["detected"]=="true" for row in items),
                               "command_miss":sum(row["detected"]=="false" for row in items),
                               "wrong_actionable_partial":sum(int(row["wrong_actionable_partial"]) for row in items),
                               "duplicate_activation":sum(int(row["duplicate_activation"]) for row in items)})
            latency={name:[float(row[name]) for row in items if row[name] != ""] for name in
                     ("first_partial_latency_ms","stable_partial_latency_ms","endpoint_latency_ms")}
            latency_rows.append({"frontend":frontend,"mode":mode,
                                 **{f"median_{name}":percentile(values,0.5) for name,values in latency.items()},
                                 **{f"p90_{name}":percentile(values,0.9) for name,values in latency.items()}})
            for keyword in sorted({row["expected_text"] for row in items}):
                subset=[row for row in items if row["expected_text"]==keyword]
                keyword_rows.append({"frontend":frontend,"mode":mode,"keyword":keyword,"total":len(subset),
                                     "detected":sum(row["detected"]=="true" for row in subset)})

    pairwise=[]
    index={(row["utterance_id"],row["frontend"],row["mode"]):row for row in outcomes}
    for row in outcomes:
        if row["frontend"]=="legacy_reference": continue
        legacy=index[(row["utterance_id"],"legacy_reference",row["mode"])]
        delta=pairwise_delta(legacy,row)
        llat=legacy["stable_partial_latency_ms"]; clat=row["stable_partial_latency_ms"]
        pairwise.append({"recording":row["recording"],"event_or_utterance_id":row["utterance_id"],
                         "expected_text":row["expected_text"],"candidate":row["frontend"],"mode":row["mode"],
                         "legacy_outcome":legacy["detected"],"candidate_outcome":row["detected"],
                         "delta_class":delta,"latency_delta_ms":"" if llat=="" or clat=="" else float(clat)-float(llat),"notes":""})

    latency_delta_rows=[]
    for frontend in frontends:
        if frontend == "legacy_reference": continue
        for mode in modes:
            for metric in ("first_partial_latency_ms", "stable_partial_latency_ms", "endpoint_latency_ms"):
                deltas=[]
                for row in outcomes:
                    if row["frontend"] != frontend or row["mode"] != mode or row[metric] == "": continue
                    legacy=index[(row["utterance_id"],"legacy_reference",mode)]
                    if legacy[metric] != "": deltas.append(float(row[metric])-float(legacy[metric]))
                low,high=bootstrap_median_ci(deltas)
                latency_delta_rows.append({"candidate":frontend,"mode":mode,"metric":metric,"paired_count":len(deltas),
                                           "median_delta_ms":percentile(deltas,0.5),"p90_delta_ms":percentile(deltas,0.9),
                                           "bootstrap_ci95_low_ms":low,"bootstrap_ci95_high_ms":high})

    adaptation_rows=[]
    phases=(("0-5",0.0,5.0),("5-20",5.0,20.0),("after-20",20.0,float("inf")))
    for frontend in frontends:
        for mode in modes:
            for phase,start,end in phases:
                items=[row for row in outcomes if row["frontend"]==frontend and row["mode"]==mode and
                       start <= speech_bounds(next(label for label in commands if label["utterance_id"]==row["utterance_id"]))[0] < end]
                stable=[float(row["stable_partial_latency_ms"]) for row in items if row["stable_partial_latency_ms"]!=""]
                adaptation_rows.append({"frontend":frontend,"mode":mode,"phase":phase,"command_total":len(items),
                                        "detected":sum(row["detected"]=="true" for row in items),
                                        "median_stable_partial_ms":percentile(stable,0.5)})

    hard=deduplicate_hard_negatives(background_triggers)
    hard_rows=[]
    for index,item in enumerate(hard,1):
        hard_rows.append({"negative_id":f"hard_neg_{index:03d}","recording":item["recording"],
                          "start_s":item["start_s"],"end_s":item["end_s"],
                          "frontends_triggered":" | ".join(sorted(item["frontends"])),
                          "commands_triggered":" | ".join(sorted(item["commands"])),
                          "human_label":"unreviewed","notes":"requires human listening"})
    write_csv(args.output_dir/"continuous_command_scores.csv",score_rows)
    write_csv(args.output_dir/"continuous_latency_scores.csv",latency_rows)
    write_csv(args.output_dir/"continuous_false_actions.csv",false_rows)
    write_csv(args.output_dir/"continuous_keyword_scores.csv",keyword_rows)
    write_csv(args.output_dir/"continuous_pairwise_deltas.csv",pairwise)
    write_csv(args.output_dir/"continuous_latency_deltas.csv",latency_delta_rows)
    write_csv(args.output_dir/"continuous_adaptation_scores.csv",adaptation_rows)
    write_csv(args.output_dir/"continuous_command_outcomes.csv",outcomes)
    if hard_rows: write_csv(args.output_dir/"hard_negatives_manifest.csv",hard_rows)
    else:
        (args.output_dir/"hard_negatives_manifest.csv").write_text("negative_id,recording,start_s,end_s,frontends_triggered,commands_triggered,human_label,notes\n",encoding="utf-8")
    print(f"Scored {len(outcomes)} command/frontend/mode outcomes; {len(hard_rows)} hard negatives")


if __name__ == "__main__":
    main()
