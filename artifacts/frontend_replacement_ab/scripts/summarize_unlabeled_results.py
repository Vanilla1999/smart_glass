#!/usr/bin/env python3
"""Summarize unlabeled fixed-window hypotheses without treating them as accuracy."""

import argparse, csv
from collections import Counter
from pathlib import Path

KEYWORDS = ("жёлтый", "доступность", "вверх", "вниз", "печать", "белый")

def main():
    parser=argparse.ArgumentParser(); parser.add_argument("--summary",type=Path,required=True); parser.add_argument("--output-dir",type=Path,required=True); args=parser.parse_args()
    rows=list(csv.DictReader(args.summary.open(encoding="utf-8"))); args.output_dir.mkdir(parents=True,exist_ok=True)
    aggregates=Counter(); keywords=Counter(); by_key={(r["window_id"],r["recording"],r["mode"],r["variant"]):r for r in rows}
    for row in rows:
        text=row["terminal_text"].lower(); aggregates[(row["variant"],row["mode"],"windows")]+=1; aggregates[(row["variant"],row["mode"],"nonempty")]+=bool(text.strip())
        for word in KEYWORDS: keywords[(row["variant"],row["mode"],word)]+=word in text
    with (args.output_dir/"unlabeled_hypothesis_summary.csv").open("w",newline="",encoding="utf-8") as f:
        fields=("variant","mode","windows","nonempty_hypotheses"); w=csv.DictWriter(f,fieldnames=fields); w.writeheader()
        for variant,mode in sorted({(r["variant"],r["mode"]) for r in rows}): w.writerow({"variant":variant,"mode":mode,"windows":aggregates[(variant,mode,"windows")],"nonempty_hypotheses":aggregates[(variant,mode,"nonempty")]})
    with (args.output_dir/"keyword_scores.csv").open("w",newline="",encoding="utf-8") as f:
        fields=("variant","mode","keyword","hypothesis_window_count","ground_truth_status"); w=csv.DictWriter(f,fieldnames=fields); w.writeheader()
        for key,value in sorted(keywords.items()): w.writerow(dict(zip(fields,(key[0],key[1],key[2],value,"unlabeled"))))
    with (args.output_dir/"error_deltas.csv").open("w",newline="",encoding="utf-8") as f:
        fields=("window_id","recording","mode","variant","legacy_text","variant_text","classification"); w=csv.DictWriter(f,fieldnames=fields); w.writeheader()
        for row in rows:
            if row["variant"]=="legacy_reference": continue
            legacy=by_key[(row["window_id"],row["recording"],row["mode"],"legacy_reference")]["terminal_text"]
            if legacy!=row["terminal_text"]: w.writerow({"window_id":row["window_id"],"recording":row["recording"],"mode":row["mode"],"variant":row["variant"],"legacy_text":legacy,"variant_text":row["terminal_text"],"classification":"different_unlabeled"})
if __name__=="__main__": main()
