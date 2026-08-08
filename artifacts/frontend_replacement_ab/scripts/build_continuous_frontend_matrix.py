#!/usr/bin/env python3
"""Build five full-recording frontend candidates with a continuous state."""

from __future__ import annotations

import argparse
import csv
from pathlib import Path

from frontend_common import (
    HighPass80, align_processed, apply_webrtc, average_channels, extract_channels,
    pcm_metrics, read_wav, write_mono,
)

RECORDINGS = ("1786194763609", "1786194978795")
CONTENT_LAG_SAMPLES = 254


def align_raw_to_ssp(pcm: bytes, target_samples: int, lag_samples: int = CONTENT_LAG_SAMPLES) -> bytes:
    """Delay raw content to the SSP timeline while preserving target duration."""
    delayed = b"\x00\x00" * lag_samples + pcm
    target_bytes = target_samples * 2
    return (delayed + b"\x00" * target_bytes)[:target_bytes]


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--capture-dir", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args()
    rows: list[dict[str, object]] = []
    for recording in RECORDINGS:
        raw = read_wav(args.capture_dir / f"raw_4ch_{recording}.wav", expected_channels=4)
        legacy = read_wav(args.capture_dir / f"ssp_mono_{recording}.wav", expected_channels=1)
        channels = extract_channels(raw.frames)
        raw_mix = average_channels(channels, (1, 2, 3))
        raw_ch3 = average_channels(channels, (3,))
        hpf = HighPass80().process(raw_mix)
        # One APM processes the complete recording, including every background interval.
        webrtc = align_processed(apply_webrtc(raw_mix, 1), raw.frame_count)
        variants = {
            "legacy_reference": legacy.frames,
            "raw_mix123": align_raw_to_ssp(raw_mix, legacy.frame_count),
            "hpf80_mix123": align_raw_to_ssp(hpf, legacy.frame_count),
            "raw_ch3": align_raw_to_ssp(raw_ch3, legacy.frame_count),
            "webrtc_moderate": align_raw_to_ssp(webrtc, legacy.frame_count),
        }
        for frontend, pcm in variants.items():
            path = args.output_dir / f"{frontend}_{recording}.wav"
            write_mono(path, pcm)
            rows.append({"recording": recording, "frontend": frontend, "path": str(path.resolve()),
                         **pcm_metrics(pcm)})
    args.output_dir.mkdir(parents=True, exist_ok=True)
    with (args.output_dir / "continuous_frontend_manifest.csv").open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=rows[0].keys())
        writer.writeheader(); writer.writerows(rows)
    print(f"Wrote {len(rows)} continuous frontend WAVs")


if __name__ == "__main__":
    main()
