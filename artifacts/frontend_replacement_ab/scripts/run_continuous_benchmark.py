#!/usr/bin/env python3
"""Run clean-continuous and approximate production-like Vosk benchmarks."""

from __future__ import annotations

import argparse
import csv
import json
import math
import wave
from pathlib import Path

from continuous_common import COMMANDS, IMMEDIATE_PARTIALS, command_tokens
from frontend_common import SAMPLE_RATE

GRAMMAR = sorted(COMMANDS) + ["[unk]"]


def emit(handle, recording: str, frontend: str, mode: str, start: float, end: float,
         event_type: str, result: dict, utterance_id: int) -> dict:
    row = {"recording": recording, "frontend": frontend, "mode": mode,
           "timestamp_start_s": round(start, 6), "timestamp_end_s": round(end, 6),
           "event_type": event_type, "partial": result.get("partial", ""),
           "text": result.get("text", ""), "words": result.get("result", []),
           "confidence": _confidence(result), "utterance_id": utterance_id}
    handle.write(json.dumps(row, ensure_ascii=False) + "\n")
    return row


def _confidence(result: dict) -> float | None:
    words = result.get("result", [])
    return sum(word.get("conf", 0.0) for word in words) / len(words) if words else None


def run_clean(vosk, model, pcm: bytes, recording: str, frontend: str, handle) -> None:
    rec = vosk.KaldiRecognizer(model, SAMPLE_RATE, json.dumps(GRAMMAR, ensure_ascii=False)); rec.SetWords(True)
    utterance = 1
    for offset in range(0, len(pcm), 2560):
        chunk = pcm[offset:offset + 2560]; start = offset / 2 / SAMPLE_RATE; end = (offset + len(chunk)) / 2 / SAMPLE_RATE
        if rec.AcceptWaveform(chunk):
            emit(handle, recording, frontend, "clean_continuous", start, end, "endpoint", json.loads(rec.Result()), utterance)
            utterance += 1
        else:
            emit(handle, recording, frontend, "clean_continuous", start, end, "partial", json.loads(rec.PartialResult()), utterance)
    emit(handle, recording, frontend, "clean_continuous", len(pcm)/2/SAMPLE_RATE,
         len(pcm)/2/SAMPLE_RATE, "final", json.loads(rec.FinalResult()), utterance)


class Segmenter:
    """Production constants: 20 ms frames, 750 ms calibration, 500 ms silence."""
    def __init__(self) -> None:
        self.calibration = []; self.noise = 0.0002; self.speaking = False
        self.silence_frames = 0; self.segment_frames = 0; self.frame_index = 0

    def add(self, pcm: bytes) -> tuple[bool, bool, bool]:
        self.frame_index += 1
        values = memoryview(pcm).cast("h")
        rms = math.sqrt(sum(value * value for value in values) / len(values)) / 32768.0
        if self.frame_index <= 38:
            if rms > 1e-7: self.calibration.append(rms)
            if self.frame_index == 38 and self.calibration:
                self.noise = max(0.0002, sorted(self.calibration)[int(0.2*(len(self.calibration)-1))])
            return False, False, False
        on = max(0.001, self.noise * 2.5); off = max(0.0007, self.noise * 1.5)
        active = rms >= (off if self.speaking else on)
        started = active and not self.speaking
        if active:
            self.speaking = True; self.silence_frames = 0; self.segment_frames += 1
        elif self.speaking:
            self.silence_frames += 1; self.segment_frames += 1
        elif rms > 1e-7 and rms < on:
            self.noise = min(self.noise * 0.98 + rms * 0.02, on * 0.5)
        endpoint = self.speaking and (self.silence_frames >= 25 or self.segment_frames >= 200)
        if endpoint:
            self.speaking = False; self.silence_frames = 0; self.segment_frames = 0
        return self.speaking or endpoint, started, endpoint


def run_production(vosk, model, pcm: bytes, recording: str, frontend: str, handle) -> None:
    rec = vosk.KaldiRecognizer(model, SAMPLE_RATE, json.dumps(GRAMMAR, ensure_ascii=False)); rec.SetWords(True)
    segmenter = Segmenter(); preroll: list[tuple[int, bytes]] = []; batch = bytearray(); batch_start = 0
    utterance = 1; claimed = False

    def process(payload: bytes, start_offset: int) -> None:
        nonlocal utterance, claimed
        start = start_offset / 2 / SAMPLE_RATE; end = (start_offset + len(payload)) / 2 / SAMPLE_RATE
        if rec.AcceptWaveform(payload):
            result = json.loads(rec.Result()); event = emit(handle, recording, frontend, "production_like", start, end, "endpoint", result, utterance)
            claimed = claimed or bool(command_tokens(event["text"])); utterance += 1; claimed = False
        else:
            result = json.loads(rec.PartialResult()); event = emit(handle, recording, frontend, "production_like", start, end, "partial", result, utterance)
            tokens = command_tokens(event["partial"])
            if not claimed and len(tokens) == 1 and tokens[0] in IMMEDIATE_PARTIALS: claimed = True

    for offset in range(0, len(pcm), 640):
        frame = pcm[offset:offset + 640]
        if len(frame) < 640: frame += b"\x00" * (640-len(frame))
        admitted, started, endpoint = segmenter.add(frame)
        if not admitted:
            preroll.append((offset, frame)); preroll = preroll[-10:]; continue
        frames = preroll + [(offset, frame)] if started else [(offset, frame)]
        if started: preroll = []
        for frame_offset, admitted_frame in frames:
            if not batch: batch_start = frame_offset
            batch.extend(admitted_frame)
            if len(batch) == 2560:
                process(bytes(batch), batch_start); batch.clear()
        if endpoint:
            if batch: process(bytes(batch), batch_start); batch.clear()
            timestamp = (offset + 640) / 2 / SAMPLE_RATE
            emit(handle, recording, frontend, "production_like", timestamp, timestamp,
                 "forced_final", json.loads(rec.FinalResult()), utterance)
            rec.Reset(); utterance += 1; claimed = False; preroll = []
    if batch: process(bytes(batch), batch_start)
    timestamp = len(pcm) / 2 / SAMPLE_RATE
    emit(handle, recording, frontend, "production_like", timestamp, timestamp,
         "final", json.loads(rec.FinalResult()), utterance)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--matrix-manifest", type=Path, required=True)
    parser.add_argument("--model", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args()
    import vosk
    vosk.SetLogLevel(-1); model = vosk.Model(str(args.model)); args.output_dir.mkdir(parents=True, exist_ok=True)
    rows = list(csv.DictReader(args.matrix_manifest.open(encoding="utf-8")))
    clean_path = args.output_dir / "continuous_vosk_events.jsonl"
    production_path = args.output_dir / "continuous_production_events.jsonl"
    with clean_path.open("w", encoding="utf-8") as clean_handle, production_path.open("w", encoding="utf-8") as production_handle:
        for index, row in enumerate(rows, 1):
            with wave.open(row["path"], "rb") as wav: pcm = wav.readframes(wav.getnframes())
            run_clean(vosk, model, pcm, row["recording"], row["frontend"], clean_handle)
            run_production(vosk, model, pcm, row["recording"], row["frontend"], production_handle)
            print(f"Completed {index}/{len(rows)} {row['recording']} {row['frontend']}", flush=True)


if __name__ == "__main__":
    main()
