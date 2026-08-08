# Continuous production-like frontend benchmark

## CONTINUOUS FINAL VERDICT

**INCONCLUSIVE — PRODUCTION SIMULATOR NOT EQUIVALENT**

The clean continuous run and the approximate production-like run do not select
the same frontend. The simulator cannot reproduce the Android decoder version,
native task scheduling, screen/route/grammar chronology, dynamic hints, or
device timing. The mandatory human audio review was also unavailable. These
limitations prevent a production winner declaration.

The engineering recommendation remains: keep `legacy_reference` and do not add
WebRTC/JNI. `webrtc_moderate` showed no unique recall or latency benefit over raw
or HPF frontends and produced one unreviewed extra `назад` endpoint.

## Dataset

- Two continuous recordings: 181.248 s and 174.080 s on the aligned SSP
  timeline.
- 84 manifest commands were machine-validated and scored.
- Human-confirmed commands in this run: 0. The required listening review of all
  `доступность`, `коровка`, `жёлтый`, and legacy misses was not performed and is
  not represented as automated confirmation.
- Command bounds were restored from dataset metadata: manifest clip bounds
  include 220 ms pre-roll and 360 ms post-roll.
- Background after subtracting command region guards: 222.448 s (3.707 min).
- One potential hard negative was generated; its human label remains
  `unreviewed`.

The ground-truth labels were never changed from Vosk output.

## Alignment

| Recording | Beginning | Middle | End | Conclusion |
|---|---:|---:|---:|---|
| `1786194763609` | -252 | -254 | -254 samples | stable |
| `1786194978795` | -254 | -254 | -255 samples | stable |

Correlation was 0.839-0.945. Drift was below 0.2 ms and no dropped internal
blocks were found. Raw frontends were delayed 254 samples onto the SSP timeline
once; the WebRTC 96-sample algorithmic delay was compensated separately. All
five outputs have the SSP duration, PCM16 mono at 16 kHz, no clipping, and valid
frames. Full details are in `continuous/alignment_report.csv`.

## Frontend Contracts

- `legacy_reference`: original complete `ssp_mono` recording.
- `raw_mix123`: channels 1, 2, and 3 averaged with truncation toward zero.
- `hpf80_mix123`: continuous `raw_mix123` through the production-equivalent
  80 Hz biquad; one filter state for the complete recording.
- `raw_ch3`: exact physical channel 3 without denoising.
- `webrtc_moderate`: continuous `raw_mix123` through one WebRTC APM per complete
  recording, NS policy 1, 10 ms frames, AEC/AGC/VAD off.

WebRTC was never cascaded after legacy processing.

## Main Production-Like Results

The table uses the approximate production-like mode. The potential WebRTC false
action is not human-confirmed.

| Frontend | Detected | Miss | Wrong partials | False actions/min | Stable partial median | Endpoint median | Status |
|---|---:|---:|---:|---:|---:|---:|---|
| `legacy_reference` | 82/84 | 2 | 3 | 0.00 | 490 ms | 840 ms | CURRENT BASELINE |
| `raw_mix123` | 81/84 | 3 | 3 | 0.00 | 510 ms | 880 ms | NO MATERIAL BENEFIT |
| `hpf80_mix123` | 80/84 | 4 | 3 | 0.00 | 510 ms | 880 ms | WORSE — MORE MISSES |
| `raw_ch3` | 81/84 | 3 | 4 | 0.00 | 470 ms | 880 ms | NO MATERIAL BENEFIT |
| `webrtc_moderate` | 81/84 | 3 | 3 | 0.27 unreviewed | 490 ms | 880 ms | NO MATERIAL BENEFIT |

No frontend met a victory criterion: no candidate reduced misses by two, reduced
confirmed false actions by 25%, or improved median stable partial latency by
100 ms. No duplicate action was found after one-to-one command-event ownership.

## Clean Continuous Results

| Frontend | Detected | Miss | Wrong partials | Stable median | Endpoint median |
|---|---:|---:|---:|---:|---:|
| `legacy_reference` | 81/84 | 3 | 4 | 510 ms | 900 ms |
| `raw_mix123` | 82/84 | 2 | 4 | 500 ms | 910 ms |
| `hpf80_mix123` | 83/84 | 1 | 4 | 490 ms | 900 ms |
| `raw_ch3` | 82/84 | 2 | 4 | 490 ms | 900 ms |
| `webrtc_moderate` | 81/84 | 3 | 4 | 490 ms | 920 ms |

HPF has the best clean-continuous recall, but it has the worst production-like
recall. This mode sensitivity is why the clean run cannot be promoted directly
to a production decision.

## Latency

Production-like median/p90 stable partial latency:

| Frontend | Median | P90 |
|---|---:|---:|
| `legacy_reference` | 490 ms | 680 ms |
| `raw_mix123` | 510 ms | 650 ms |
| `hpf80_mix123` | 510 ms | 650 ms |
| `raw_ch3` | 470 ms | 650 ms |
| `webrtc_moderate` | 490 ms | 670 ms |

Paired WebRTC-versus-legacy median deltas were 0 ms for first partial, stable
partial, and endpoint. Their bootstrap median 95% intervals collapsed at 0 ms
because most paired events land on the same 20/80 ms simulator boundaries. P90
paired deltas were +142 ms, +140 ms, and +156 ms respectively. WebRTC did not
make stable partials faster.

## False Actions

Legacy, raw mix, HPF, and raw channel 3 emitted no background action after event
ownership was matched to ground truth. WebRTC emitted one additional endpoint:

```text
recording: 1786194763609
interval: 171.700-174.200 s
command: назад
```

It is close to the genuine `1786194763609_cmd_039` (`назад`) and may be a delayed
duplicate endpoint rather than television speech. The clip is saved as
`continuous/hard_negative_clips/hard_neg_001_legacy_reference.wav`, but it was
not listened to. Therefore it remains `unreviewed` and cannot support a firm
false-activation claim.

## Keywords

Production-like recall:

| Keyword | Total | Legacy | Raw mix | HPF | Raw ch3 | WebRTC moderate |
|---|---:|---:|---:|---:|---:|---:|
| `вверх` | 14 | 14 | 13 | 12 | 12 | 12 |
| `вниз` | 13 | 12 | 13 | 13 | 13 | 13 |
| `жёлтый` | 14 | 14 | 14 | 14 | 14 | 14 |
| `доступность` | 8 | 8 | 8 | 8 | 8 | 8 |
| `коровка` | 8 | 7 | 7 | 7 | 7 | 7 |

All candidates trade one legacy `вниз` miss for at least one new `вверх` miss.
HPF and WebRTC moderate add two `вверх` misses. No frontend hurts `жёлтый` or
`доступность`; all miss the same `1786194978795_cmd_039` (`коровка`).

Special utterances:

- `1786194763609_cmd_002` (`вниз`): detected by all five; production-like stable
  latency was 910 ms legacy, 610 ms raw mix/HPF, and 1,090 ms raw ch3/WebRTC.
- `1786194978795_cmd_032` (`доступность`): detected by all five; stable latency
  was 490 ms legacy/WebRTC and 450 ms raw mix/HPF/raw ch3.
- `1786194978795_cmd_039` (`коровка`): missed by all five in both modes.

## WebRTC Adaptation

No command occurs in the first five seconds, so command adaptation cannot be
measured there. In production-like mode:

| Phase | Commands | Detected | Stable median |
|---|---:|---:|---:|
| 0-5 s | 0 | 0 | n/a |
| 5-20 s | 8 | 7 | 590 ms |
| after 20 s | 76 | 74 | 490 ms |

The later interval is faster, but the same pattern appears for raw mix, HPF, and
raw channel 3. It is explained by command composition and simulator/Vosk state,
not a unique WebRTC adaptation effect.

## Pairwise Summary

- Raw mix: one more production-like miss than legacy, same wrong-partial count,
  no false action, and no median latency win.
- HPF: two more misses, including the rare `источник`, with no compensating
  latency or false-action win.
- Raw channel 3: one more miss and one more wrong actionable partial; median
  stable partial is only 20 ms faster.
- WebRTC moderate: one more miss, same aggregate wrong-partial count, equal
  median stable latency, and one unreviewed extra endpoint.
- McNemar discordant counts are too small for a meaningful significance claim.

Detailed per-utterance changes are in
`continuous/continuous_pairwise_deltas.csv`; paired latency distributions and
bootstrap intervals are in `continuous/continuous_latency_deltas.csv`.

## Simulator Differences

The simulator reproduces 16 kHz PCM, 20 ms VAD frames, 750 ms calibration,
200 ms pre-roll, 80 ms recognizer batches, 500 ms silence closure, four-second
maximum segments, exact `вверх`/`вниз` actionable partials, endpoint-only other
commands, and recognizer reset after forced finalization.

It does not reproduce:

- Android Vosk 0.3.75; offline Python uses Vosk 0.3.45;
- JNI task-lane scheduling, queue backpressure, operation timeouts, or native
  recognizer replacement;
- actual screen transitions, route/grammar revisions, and dynamic item hints;
- free-text replay ownership and command-yield contention;
- device capture leases, UAC4 callback timing, or MethodChannel latency.

The source sequence is insufficient to reconstruct exact screen chronology and
dynamic grammars, so no screen-specific score was mixed into the combined-
grammar comparison.

## Engineering Conclusion

- Legacy is not proven acoustically superior; it remains the current baseline
  because no candidate satisfies the replacement criteria.
- WebRTC moderate repeats the raw/HPF trade-off and has no unique ASR gain.
- Stable partial latency is unchanged for WebRTC and only 20 ms better for raw
  channel 3, far below the 100 ms threshold.
- Television/background false actions were zero for four frontends; the one
  WebRTC event requires human review.
- Do not add WebRTC/JNI or change production frontend from this evidence.
- Repeat on an unseen recording with recorded screen/grammar chronology and
  human-confirmed labels/hard negatives before a production change.
