#!/usr/bin/env python3
"""Generate all frontend variants independently for each dataset utterance."""

from __future__ import annotations

import argparse
import csv
import json
from pathlib import Path

from build_frontend_matrix import CHANNEL_VARIANTS
from frontend_common import (
    HighPass80,
    align_processed,
    apply_webrtc,
    average_channels,
    blend,
    extract_channels,
    pcm_metrics,
    read_wav,
    write_mono,
)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dataset-root", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args()

    manifest_rows = list(csv.DictReader((args.dataset_root / "manifest.csv").open(encoding="utf-8")))
    metrics: list[dict[str, object]] = []
    matrix: list[dict[str, str]] = []

    for row in manifest_rows:
        raw = read_wav(args.dataset_root / row["raw_path"], expected_channels=4)
        legacy = read_wav(args.dataset_root / row["ssp_path"], expected_channels=1)
        if raw.frame_count != legacy.frame_count:
            raise ValueError(f'{row["utterance_id"]}: raw/SSP frame counts differ')
        channels = extract_channels(raw.frames)
        variants = {
            name: average_channels(channels, indexes)
            for name, indexes in CHANNEL_VARIANTS.items()
        }
        variants["hpf80_mix123"] = HighPass80().process(variants["raw_mix123"])
        variants["legacy_reference"] = legacy.frames

        for level_name, level in (("low", 0), ("moderate", 1)):
            # apply_webrtc creates a fresh APM instance for every utterance and level.
            processed = apply_webrtc(variants["raw_mix123"], level)
            aligned = align_processed(processed, raw.frame_count)
            variants[f"webrtc_{level_name}"] = aligned
            variants[f"webrtc_{level_name}_raw25"] = blend(
                aligned, variants["raw_mix123"], 0.75
            )
            variants[f"webrtc_{level_name}_raw50"] = blend(
                aligned, variants["raw_mix123"], 0.50
            )

        for frontend, pcm in sorted(variants.items()):
            output = args.output_dir / frontend / f'{row["utterance_id"]}.wav'
            write_mono(output, pcm)
            matrix.append(
                {
                    "utterance_id": row["utterance_id"],
                    "frontend": frontend,
                    "path": str(output.resolve()),
                }
            )
            metrics.append(
                {
                    "utterance_id": row["utterance_id"],
                    "frontend": frontend,
                    **pcm_metrics(pcm),
                }
            )

    args.output_dir.mkdir(parents=True, exist_ok=True)
    with (args.output_dir / "utterance_frontend_manifest.csv").open(
        "w", newline="", encoding="utf-8"
    ) as handle:
        writer = csv.DictWriter(handle, fieldnames=matrix[0].keys())
        writer.writeheader()
        writer.writerows(matrix)
    with (args.output_dir / "utterance_frontend_metrics.csv").open(
        "w", newline="", encoding="utf-8"
    ) as handle:
        writer = csv.DictWriter(handle, fieldnames=metrics[0].keys())
        writer.writeheader()
        writer.writerows(metrics)
    with (args.output_dir / "utterance_frontend_summary.json").open(
        "w", encoding="utf-8"
    ) as handle:
        json.dump(
            {
                "test_cases": len(manifest_rows),
                "frontends": len(metrics) // len(manifest_rows),
                "generated_wavs": len(metrics),
                "webrtc_apm_scope": "fresh instance per utterance and NS level",
            },
            handle,
            indent=2,
        )
    print(f"Wrote {len(metrics)} frontend utterances to {args.output_dir}")


if __name__ == "__main__":
    main()
