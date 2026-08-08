#!/usr/bin/env python3
"""Build a compact, time-aligned manual-labeling package from 80 ms Vosk events."""

from __future__ import annotations

import argparse
import csv
import json
import re
import wave
from collections import Counter, defaultdict
from dataclasses import dataclass
from pathlib import Path

RATE = 16_000
DELAY = 96
VARIANTS = ("baseline", "webrtc_ns_low", "webrtc_ns_moderate")
SHORT = {"baseline": "baseline", "webrtc_ns_low": "low", "webrtc_ns_moderate": "moderate"}
KEYWORDS = ("жёлт", "желт", "доступн", "вверх", "вниз", "назад", "печать", "бел", "список", "коровк", "молоч")
SEQUENCE = {
    "1786194763609": "вниз/вверх; печать; белый; назад; жёлтый; доступность; список; напитки",
    "1786194978795": "вниз/вверх; печать; жёлтый; белый; мобильный; назад; доступность; список; молочное; коровка",
}


@dataclass
class Event:
    recording: str
    variant: str
    mode: str
    start: float
    end: float
    text: str
    partials: tuple[str, ...]


def event_text(row: dict) -> str:
    return str(row["result"].get("text", row["result"].get("partial", ""))).strip()


def terminal_events(path: Path) -> list[Event]:
    active: dict[tuple[str, str, str], tuple[float, list[str]]] = {}
    result = []
    for line in path.read_text(encoding="utf-8").splitlines():
        row = json.loads(line)
        if row["variant"] not in VARIANTS:
            continue
        recording = row["file"].rsplit("_", 1)[-1].removesuffix(".wav")
        key = (recording, row["variant"], row["mode"])
        text = event_text(row)
        time = float(row["audio_timestamp_ms"]) / 1000
        if row["event"] == "partial" and text:
            if key not in active:
                active[key] = (time, [])
            if not active[key][1] or active[key][1][-1] != text:
                active[key][1].append(text)
        elif row["event"] in ("endpoint", "final"):
            start, partials = active.pop(key, (max(0, time - 2.0), []))
            if text:
                result.append(Event(recording, row["variant"], row["mode"], start, time, text, tuple(partials)))
    return result


def cluster_events(events: list[Event], merge_gap: float = 0.7) -> list[list[Event]]:
    clusters = []
    for group_key in sorted({(e.recording, e.mode) for e in events}):
        group = sorted((e for e in events if (e.recording, e.mode) == group_key), key=lambda e: e.start)
        parents = list(range(len(group)))
        def root(index):
            while parents[index] != index:
                parents[index] = parents[parents[index]]; index = parents[index]
            return index
        for left, first in enumerate(group):
            for right in range(left + 1, len(group)):
                second = group[right]
                if second.start > first.end + merge_gap:
                    break
                if first.variant != second.variant and second.end >= first.start - merge_gap:
                    a, z = root(left), root(right)
                    if a != z: parents[z] = a
        merged = defaultdict(list)
        for index, event in enumerate(group): merged[root(index)].append(event)
        clusters.extend(merged.values())
    return clusters


def clip_ranges(start: float, end: float, duration: float, pre: float = 0.5, post: float = 0.5, maximum: float = 4.0) -> list[tuple[float, float]]:
    start, end = max(0.0, start - pre), min(duration, end + post)
    ranges = []
    while end - start > maximum:
        ranges.append((start, start + maximum))
        start += maximum
    ranges.append((start, end))
    return ranges


def read_pcm(path: Path) -> bytes:
    with wave.open(str(path), "rb") as wav:
        assert (wav.getframerate(), wav.getnchannels(), wav.getsampwidth(), wav.getcomptype()) == (RATE, 1, 2, "NONE")
        return wav.readframes(wav.getnframes())


def aligned_slice(pcm: bytes, start: int, end: int, delay: int = 0) -> bytes:
    count = end - start
    source_start = start + delay
    data = pcm[max(0, source_start) * 2:max(0, source_start + count) * 2]
    if source_start < 0:
        data = b"\0" * (-source_start * 2) + data
    return (data + b"\0" * (count * 2))[:count * 2]


def write_wav(path: Path, pcm: bytes) -> None:
    with wave.open(str(path), "wb") as wav:
        wav.setnchannels(1); wav.setsampwidth(2); wav.setframerate(RATE); wav.writeframes(pcm)


def summaries(events: list[Event], mode: str, start: float, end: float) -> tuple[dict, dict, dict]:
    texts, partials, counts = {}, {}, {}
    for variant in VARIANTS:
        selected = [e for e in events if e.mode == mode and e.variant == variant and e.end >= start and e.start <= end]
        name = SHORT[variant]
        texts[name] = " | ".join(e.text for e in selected)
        partials[name] = " -> ".join(dict.fromkeys(p for e in selected for p in e.partials))
        counts[name] = len(selected)
    return texts, partials, counts


def is_disputed(texts: dict, partials: dict, counts: dict) -> bool:
    if len(set(texts.values())) > 1 or len(set(counts.values())) > 1:
        return True
    keyword_partials = {
        name: tuple(keyword for keyword in KEYWORDS if keyword in text.lower())
        for name, text in partials.items()
    }
    return len(set(keyword_partials.values())) > 1


def build(events_path: Path, outputs: Path, captures: Path, destination: Path) -> list[dict]:
    events = terminal_events(events_path)
    clusters = cluster_events(events)
    clips = destination / "clips"; clips.mkdir(parents=True, exist_ok=True)
    for old_clip in clips.glob("*.wav"):
        old_clip.unlink()
    rows = []
    pcm_cache = {}
    for recording in sorted({e.recording for e in events}):
        pcm_cache[(recording, "source")] = read_pcm(captures / f"ssp_mono_{recording}.wav")
        pcm_cache[(recording, "baseline")] = read_pcm(outputs / f"baseline_ssp_{recording}.wav")
        pcm_cache[(recording, "low")] = read_pcm(outputs / f"webrtc_ns_low_{recording}.wav")
        pcm_cache[(recording, "moderate")] = read_pcm(outputs / f"webrtc_ns_moderate_{recording}.wav")
    index = 0
    for cluster in clusters:
        recording, mode = cluster[0].recording, cluster[0].mode
        duration = len(pcm_cache[(recording, "source")]) / 2 / RATE
        for start, end in clip_ranges(min(e.start for e in cluster), max(e.end for e in cluster), duration):
            texts, partials, counts = summaries(events, mode, start, end)
            if not is_disputed(texts, partials, counts):
                continue
            index += 1
            segment_id = f"seg_{recording}_{index:03d}_{mode}"
            begin, finish = round(start * RATE), round(end * RATE)
            for name in ("source", "baseline", "low", "moderate"):
                delay = DELAY if name in ("low", "moderate") else 0
                write_wav(clips / f"{segment_id}_{name}.wav", aligned_slice(pcm_cache[(recording, name)], begin, finish, delay))
            all_text = " ".join((*texts.values(), *partials.values())).lower()
            consensus = texts["baseline"] if len(set(texts.values())) == 1 else ""
            provisional = consensus if consensus and " | " not in consensus and any(k in consensus.lower() for k in KEYWORDS) else ""
            rows.append({
                "segment_id": segment_id, "recording": recording, "mode": mode,
                "start_s": f"{start:.3f}", "end_s": f"{end:.3f}", "duration_s": f"{end-start:.3f}",
                "baseline_endpoint_text": texts["baseline"], "low_endpoint_text": texts["low"], "moderate_endpoint_text": texts["moderate"],
                "baseline_partial_summary": partials["baseline"], "low_partial_summary": partials["low"], "moderate_partial_summary": partials["moderate"],
                "baseline_endpoint_count": counts["baseline"], "low_endpoint_count": counts["low"], "moderate_endpoint_count": counts["moderate"],
                "contains_keyword_candidate": ";".join(k for k in KEYWORDS if k in all_text), "known_sequence_hint": SEQUENCE[recording],
                "expected_type": "command" if provisional else "unlabeled", "expected_text": provisional,
                "label_confidence": "provisional" if provisional else "", "notes": "",
                "audio": {name: f"../clips/{segment_id}_{name}.wav" for name in ("source", "baseline", "low", "moderate")},
            })
    return rows


def write_package(rows: list[dict], destination: Path, delta_count: int) -> None:
    csv_fields = [key for key in rows[0] if key != "audio"]
    with (destination / "labeling_manifest.csv").open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=csv_fields); writer.writeheader(); writer.writerows({k:v for k,v in row.items() if k != "audio"} for row in rows)
    (destination / "labeling_manifest.json").write_text(json.dumps(rows, ensure_ascii=False, indent=2), encoding="utf-8")
    counts = Counter(row["recording"] for row in rows)
    keywords = Counter(k for row in rows for k in row["contains_keyword_candidate"].split(";") if k)
    total = sum(float(row["duration_s"]) for row in rows)
    provisional = sum(row["label_confidence"] == "provisional" for row in rows)
    report = f"""# Pre-label Report

- Source ASR delta rows: {delta_count}
- Unique disputed temporal clips: {len(rows)}
- Total clip duration: {total:.3f} s
- Original recording duration: 355.328 s
- Reduction: {100 * (1 - total / 355.328):.1f}%
- Provisional labels: {provisional}
- Unlabeled: {len(rows) - provisional}
- By recording: {dict(counts)}
- Keyword candidates: {dict(keywords)}

Provisional labels require human confirmation. Known command sequences are hints only.
"""
    (destination / "PRE_LABEL_REPORT.md").write_text(report, encoding="utf-8")
    (destination / "README.md").write_text("Run `python3 -m http.server 8765` here, then open http://localhost:8765/player/.\n", encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--events", type=Path, default=Path("artifacts/webrtc_ns_ab/outputs/replay_80ms/ns_asr_events.jsonl"))
    parser.add_argument("--deltas", type=Path, default=Path("artifacts/webrtc_ns_ab/outputs/ns_variant_deltas.csv"))
    parser.add_argument("--outputs", type=Path, default=Path("artifacts/webrtc_ns_ab/outputs"))
    parser.add_argument("--captures", type=Path, default=Path("/home/viadmin/Документы/voice_capture_2026-08-08"))
    parser.add_argument("--destination", type=Path, default=Path("artifacts/webrtc_ns_ab/labeling"))
    args = parser.parse_args(); args.destination.mkdir(parents=True, exist_ok=True)
    rows = build(args.events, args.outputs, args.captures, args.destination)
    with args.deltas.open(encoding="utf-8") as handle: delta_count = sum(1 for _ in csv.DictReader(handle))
    write_package(rows, args.destination, delta_count)
    print(f"LABELING_PACKAGE clips={len(rows)} duration_s={sum(float(r['duration_s']) for r in rows):.3f}")


if __name__ == "__main__": main()
