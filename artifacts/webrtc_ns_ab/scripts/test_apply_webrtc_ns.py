#!/usr/bin/env python3
"""Dependency-free contract tests for the offline WebRTC NS framing logic."""

from __future__ import annotations

import importlib.util
from pathlib import Path

SCRIPT = Path(__file__).with_name("apply_webrtc_ns.py")
SPEC = importlib.util.spec_from_file_location("apply_webrtc_ns", SCRIPT)
MODULE = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
import sys
sys.modules[SPEC.name] = MODULE
SPEC.loader.exec_module(MODULE)


class IdentityAp:
    def process_stream(self, chunk):
        assert len(chunk) == MODULE.FRAME_BYTES
        return chunk


def factory(_level):
    return IdentityAp()


def test_exact_frame():
    source = bytes((index % 251 for index in range(MODULE.FRAME_BYTES)))
    assert MODULE.process_frames(source, 1, factory) == source


def test_partial_frame_is_trimmed():
    source = bytes((index % 251 for index in range(MODULE.FRAME_BYTES + 17)))
    assert MODULE.process_frames(source, 1, factory) == source


def test_multiple_frames_preserve_order():
    source = bytes((index % 251 for index in range(MODULE.FRAME_BYTES * 3 + 9)))
    assert MODULE.process_frames(source, 1, factory) == source


if __name__ == "__main__":
    test_exact_frame()
    test_partial_frame_is_trimmed()
    test_multiple_frames_preserve_order()
    print("WEBRTC_NS_FRAMING_TEST_OK")
