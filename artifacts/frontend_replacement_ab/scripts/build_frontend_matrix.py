#!/usr/bin/env python3
"""Generate mutually exclusive frontend candidates from raw UAC4 recordings."""

from __future__ import annotations

import argparse
import csv
import json
from pathlib import Path

from frontend_common import (
    RECORDING_IDS,
    HighPass80,
    align_processed,
    apply_webrtc,
    average_channels,
    blend,
    extract_channels,
    pack_i16,
    pcm_metrics,
    read_wav,
    write_mono,
)

CHANNEL_VARIANTS = {
    "raw_ch0": (0,),
    "raw_ch1": (1,),
    "raw_ch2": (2,),
    "raw_ch3": (3,),
    "raw_pair01": (0, 1),
    "raw_pair12": (1, 2),
    "raw_pair13": (1, 3),
    "raw_pair23": (2, 3),
    "raw_mix123": (1, 2, 3),
}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--capture-dir", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args()
    args.output_dir.mkdir(parents=True, exist_ok=True)

    rows: list[dict[str, object]] = []
    manifest: dict[str, object] = {
        "sample_rate": 16000,
        "raw_channels": 4,
        "webrtc": {
            "input": "raw_mix123",
            "aec": False,
            "agc": False,
            "vad": False,
            "delay_compensation_samples": 96,
        },
        "variants": [],
        "recordings": [],
    }

    for recording_id in RECORDING_IDS:
        raw_path = args.capture_dir / f"raw_4ch_{recording_id}.wav"
        legacy_path = args.capture_dir / f"ssp_mono_{recording_id}.wav"
        raw = read_wav(raw_path, expected_channels=4)
        legacy = read_wav(legacy_path, expected_channels=1)
        channels = extract_channels(raw.frames)
        variants: dict[str, bytes] = {}

        for name, indexes in CHANNEL_VARIANTS.items():
            variants[name] = average_channels(channels, indexes)

        variants["hpf80_mix123"] = HighPass80().process(variants["raw_mix123"])
        variants["legacy_reference"] = legacy.frames

        for level_name, level in (("low", 0), ("moderate", 1)):
            processed = apply_webrtc(variants["raw_mix123"], level)
            aligned = align_processed(processed, len(variants["raw_mix123"]) // 2)
            variants[f"webrtc_{level_name}"] = aligned
            variants[f"webrtc_{level_name}_raw25"] = blend(aligned, variants["raw_mix123"], 0.75)
            variants[f"webrtc_{level_name}_raw50"] = blend(aligned, variants["raw_mix123"], 0.50)

        recording_entry = {
            "recording": recording_id,
            "raw": str(raw_path.resolve()),
            "legacy": str(legacy_path.resolve()),
            "variants": {},
        }

        for name, pcm in variants.items():
            path = args.output_dir / f"{name}_{recording_id}.wav"
            write_mono(path, pcm)
            rows.append({"recording": recording_id, "variant": name, **pcm_metrics(pcm)})
            recording_entry["variants"][name] = path.name

        manifest["recordings"].append(recording_entry)

    manifest["variants"] = sorted({row["variant"] for row in rows})
    with (args.output_dir / "frontend_manifest.json").open("w", encoding="utf-8") as handle:
        json.dump(manifest, handle, ensure_ascii=False, indent=2)

    with (args.output_dir / "frontend_metrics.csv").open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=rows[0].keys())
        writer.writeheader()
        writer.writerows(rows)

    print(f"Wrote {len(rows)} frontend WAVs to {args.output_dir}")


if __name__ == "__main__":
    main()
