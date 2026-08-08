#!/usr/bin/env python3
"""Dependency-free tests for PCM, DSP, framing and window deduplication."""

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).parent
sys.path.insert(0, str(SCRIPT_DIR))

from frontend_common import (
    WEBRTC_FRAME_BYTES,
    align_processed,
    apply_webrtc,
    average_channels,
    blend,
    extract_channels,
    pack_i16,
    unpack_i16,
)
from build_eval_windows import Window, merge_windows


class IdentityAp:
    def process_stream(self, chunk):
        assert len(chunk) == WEBRTC_FRAME_BYTES
        return chunk


def identity_factory(_level):
    return IdentityAp()


def test_channel_extraction_and_averages():
    frames = [
        (100, 200, 300, 400),
        (-100, -200, 101, 301),
    ]
    raw = pack_i16(value for frame in frames for value in frame)
    channels = extract_channels(raw)
    assert channels == [[100, -100], [200, -200], [300, 101], [400, 301]]
    assert unpack_i16(average_channels(channels, (1, 2, 3))) == (300, 67)
    assert unpack_i16(average_channels(channels, (1, 3))) == (300, 50)


def test_webrtc_framing_preserves_partial_tail():
    source = bytes(index % 251 for index in range(WEBRTC_FRAME_BYTES * 2 + 19))
    assert apply_webrtc(source, 0, identity_factory) == source


def test_delay_alignment():
    source = pack_i16(range(120))
    aligned = unpack_i16(align_processed(source, target_samples=40, delay_samples=10))
    assert aligned == tuple(range(10, 50))


def test_blend():
    enhanced = pack_i16([1000, -1000])
    dry = pack_i16([0, 0])
    assert unpack_i16(blend(enhanced, dry, 0.75)) == (750, -750)
    assert unpack_i16(blend(enhanced, dry, 0.50)) == (500, -500)


def test_temporal_merge_and_mode_deduplication():
    windows = [
        Window("r", 1.0, 3.0, "disputed", {"вверх"}),
        Window("r", 2.8, 4.0, "disputed", {"вниз"}),
        Window("r", 4.5, 5.0, "disputed", set()),
    ]
    merged = merge_windows(windows, gap=0.75, max_duration=6.0)
    assert len(merged) == 1
    assert merged[0].start == 1.0 and merged[0].end == 5.0
    assert merged[0].keywords == {"вверх", "вниз"}


def test_max_window_prevents_overmerge():
    windows = [
        Window("r", 0.0, 4.0, "disputed", set()),
        Window("r", 4.2, 8.0, "disputed", set()),
    ]
    merged = merge_windows(windows, gap=0.75, max_duration=6.0)
    assert len(merged) == 2
    assert merged[0].end <= merged[1].start


if __name__ == "__main__":
    test_channel_extraction_and_averages()
    test_webrtc_framing_preserves_partial_tail()
    test_delay_alignment()
    test_blend()
    test_temporal_merge_and_mode_deduplication()
    test_max_window_prevents_overmerge()
    print("FRONTEND_REPLACEMENT_TEST_OK")
