#!/usr/bin/env python3
"""Dependency-free resumable CLI for labeling disputed audio segments."""

import argparse, csv, json, shutil, subprocess
from pathlib import Path

TYPES = ("command", "background_speech", "silence", "mixed_command_and_background", "unclear", "unlabeled")

def load_progress(path):
    return {row["segment_id"]: row for row in json.loads(path.read_text(encoding="utf-8"))} if path.exists() else {}

def save_progress(path, labels): path.write_text(json.dumps(list(labels.values()), ensure_ascii=False, indent=2), encoding="utf-8")

def play(path):
    for command in ("ffplay", "paplay", "aplay"):
        if shutil.which(command):
            args = [command, "-nodisp", "-autoexit", "-loglevel", "quiet", str(path)] if command == "ffplay" else [command, str(path)]
            subprocess.run(args, check=False); return
    print("No local player found")

def main():
    parser=argparse.ArgumentParser(); parser.add_argument("--manifest", type=Path, default=Path("artifacts/webrtc_ns_ab/labeling/labeling_manifest.csv")); parser.add_argument("--labels", type=Path, default=Path("artifacts/webrtc_ns_ab/labeling/manual_labels.json")); args=parser.parse_args()
    rows=list(csv.DictReader(args.manifest.open(encoding="utf-8"))); labels=load_progress(args.labels); clips=args.manifest.parent/"clips"
    for row in rows:
        if row["segment_id"] in labels: continue
        print(json.dumps({k:row[k] for k in ("segment_id","start_s","end_s","baseline_endpoint_text","low_endpoint_text","moderate_endpoint_text")}, ensure_ascii=False, indent=2))
        choice=input("play source/baseline/low/moderate/skip? ").strip()
        if choice in ("source","baseline","low","moderate"): play(clips/f"{row['segment_id']}_{choice}.wav")
        expected=input(f"expected_type {TYPES}: ").strip() or "unlabeled"
        labels[row["segment_id"]]={"segment_id":row["segment_id"],"expected_type":expected,"expected_text":input("expected_text: ").strip(),"confidence":input("confidence: ").strip(),"notes":input("notes: ").strip()}; save_progress(args.labels,labels)

if __name__ == "__main__": main()
