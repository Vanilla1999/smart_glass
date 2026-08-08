#!/usr/bin/env python3
"""Evaluate baseline/low/moderate outputs against explicit manual labels."""

import argparse, csv, json, re
from collections import Counter
from pathlib import Path

VARIANTS=("baseline","low","moderate")
def normalize(text, relaxed=False):
    value=" ".join(text.lower().strip().split())
    return value.replace("ё","е") if relaxed else value
def classify(expected_type, expected, actual, relaxed=False, mode="command_menu"):
    if expected_type in ("mixed_command_and_background","unclear","unlabeled"): return "unclear"
    if expected_type=="command":
        if not actual.strip(): return "miss"
        return "correct_command" if normalize(actual,relaxed)==normalize(expected,relaxed) else "wrong_command"
    if expected_type in ("background_speech","silence"):
        if mode == "free_text" and expected_type == "background_speech": return "background_transcription" if actual.strip() else "correct_rejection"
        return "false_activation" if actual.strip() else "correct_rejection"
    return "unclear"
def load_labels(path): return {x["segment_id"]:x for x in json.loads(path.read_text(encoding="utf-8"))}
def main():
    p=argparse.ArgumentParser(); p.add_argument("manifest",type=Path); p.add_argument("labels",type=Path); p.add_argument("--output-dir",type=Path); a=p.parse_args(); out=a.output_dir or a.manifest.parent
    manifest=json.loads(a.manifest.read_text(encoding="utf-8")); labels=load_labels(a.labels); rows=[]; totals=Counter()
    for segment in manifest:
        label=labels.get(segment["segment_id"],{"expected_type":"unlabeled","expected_text":""})
        for variant in VARIANTS:
            actual=segment[f"{variant}_endpoint_text"]
            strict=classify(label["expected_type"],label.get("expected_text",""),actual,False,segment["mode"]); relaxed=classify(label["expected_type"],label.get("expected_text",""),actual,True,segment["mode"])
            rows.append({"segment_id":segment["segment_id"],"mode":segment["mode"],"variant":variant,"expected_type":label["expected_type"],"expected_text":label.get("expected_text",""),"actual_text":actual,"strict_result":strict,"relaxed_result":relaxed}); totals[(variant,segment["mode"],strict)]+=1
    with (out/"labeled_results.csv").open("w",newline="",encoding="utf-8") as f: w=csv.DictWriter(f,fieldnames=rows[0].keys()); w.writeheader(); w.writerows(rows)
    lines=["# Manual Label Evaluation","", "No winner is selected automatically.",""]
    for variant in VARIANTS:
        for mode in ("command_menu","free_text"):
            values=Counter({result: totals[(variant,mode,result)] for result in ("correct_command","miss","wrong_command","false_activation","correct_rejection","background_transcription","unclear")})
            command_total=values["correct_command"]+values["miss"]+values["wrong_command"]
            rejection_total=values["false_activation"]+values["correct_rejection"]
            accuracy=values["correct_command"]/command_total if command_total else 0
            false_rate=values["false_activation"]/rejection_total if rejection_total else 0
            lines += [f"## {variant} / {mode}","",f"- Counts: {dict(values)}",f"- Strict command accuracy: {accuracy:.4f}",f"- False activation rate: {false_rate:.4f}",""]
    changed=[row for row in rows if row["strict_result"]!=row["relaxed_result"]]
    lines += ["## Relaxed ё/е differences","",*(f"- {r['segment_id']} {r['variant']}: `{r['actual_text']}`" for r in changed)]
    (out/"EVALUATION.md").write_text("\n".join(lines)+"\n",encoding="utf-8")
if __name__=="__main__": main()
