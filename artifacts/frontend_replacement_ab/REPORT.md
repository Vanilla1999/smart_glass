# Frontend Replacement Offline A/B

## Verdict

INCONCLUSIVE — INSUFFICIENT LABELS

The mutually exclusive frontend matrix and fixed-window Vosk replay completed,
but none of the 47 evaluation windows has listening-derived ground truth.
Recognizer text was not reused as truth. Therefore no frontend can be called a
winner and no Android/JNI integration is justified.

## Base And Environment

- Branch: `experiment/aligned-audio-frontend`
- Base HEAD: `31092ece30c68f31ec8a7d144c2dcc94258bd321`
- Python: 3.11.15
- `webrtc-audio-processing`: 0.1.3
- Host Vosk: 0.3.45
- Model: `artifacts/webrtc_ns_ab/model/vosk-model-small-ru-0.22`
- Raw inputs: `/home/viadmin/Документы/voice_capture_2026-08-08/raw_4ch_1786194763609.wav`, `/home/viadmin/Документы/voice_capture_2026-08-08/raw_4ch_1786194978795.wav`
- Legacy inputs: `/home/viadmin/Документы/voice_capture_2026-08-08/ssp_mono_1786194763609.wav`, `/home/viadmin/Документы/voice_capture_2026-08-08/ssp_mono_1786194978795.wav`

The request called this a 15-frontend matrix, but its explicit list and supplied
patch define 17 frontends. The user confirmed running all 17, producing 34 WAVs.

## Frontend Contracts

- `raw_ch0..3`: exact deinterleaved physical channels.
- `raw_pair01/12/13/23`: Kotlin-style truncating averages of the named pair.
- `raw_mix123`: Kotlin-style truncating average of channels 1, 2 and 3.
- `hpf80_mix123`: raw mix through only the production-equivalent 80 Hz biquad.
- `legacy_reference`: existing SSP mono capture.
- `webrtc_low/moderate`: WebRTC NS policy 0/1 directly on raw mix, never SSP.
- `*_raw25`: 75% enhanced plus 25% dry raw mix.
- `*_raw50`: 50% enhanced plus 50% dry raw mix.

WebRTC used PCM16 LE mono at 16 kHz, 160-sample/10-ms frames, AEC off,
AGC off, VAD off, and 96-sample delay compensation.

All 34 WAVs passed header, even-byte, sample-level channel/average/blend, and
zero-clipping checks. Raw-derived WAVs retain raw duration; window generation
uses the minimum duration across all frontends because SSP is slightly shorter.

## Evaluation Windows

- Disputed deduplicated windows: 38
- Non-overlapping uniform controls: 9 (recording 1: 4, recording 2: 5)
- Total: 47 windows, 179.080 s, 50.40% of the original 355.328 s
- Labeled windows: 0

The first patch output was 183.040 s and contained overlapping disputed
windows. The offline merge logic was corrected to remove duplicated overlap,
giving 179.080 s. This remains 1.416 s above the requested 50% threshold because
the disputed union alone is 161.080 s. Only nine 2-second controls fit without
overlapping disputed regions, so the requested ten controls per recording
cannot be met under the simultaneous no-overlap rule.

## Fixed-window Vosk

Every `(window, frontend, mode)` used a fresh recognizer and 2,560-byte/80-ms
chunks. Total independent runs: 1,598 (`47 × 17 × 2`). Command and free-text
were not merged into a score.

The patch grammar is an explicit combined command grammar with `[unk]`. It adds
`белый`, `жёлтый`, `назад`, and `список` to the earlier menu grammar. Production
uses screen-specific `VoiceActionCatalog` grammars, so this replay is not an
exact single-screen grammar certification. No arbitrary free-text words were
added.

The following counts are descriptive nonempty hypotheses, not correctness:

| Frontend | command-menu | free-text |
| --- | ---: | ---: |
| hpf80_mix123 | 28/47 | 33/47 |
| legacy_reference | 29/47 | 33/47 |
| raw_ch0 | 27/47 | 32/47 |
| raw_ch1 | 27/47 | 32/47 |
| raw_ch2 | 29/47 | 32/47 |
| raw_ch3 | 30/47 | 33/47 |
| raw_mix123 | 28/47 | 33/47 |
| raw_pair01 | 28/47 | 32/47 |
| raw_pair12 | 27/47 | 33/47 |
| raw_pair13 | 27/47 | 32/47 |
| raw_pair23 | 29/47 | 33/47 |
| webrtc_low | 28/47 | 33/47 |
| webrtc_low_raw25 | 28/47 | 33/47 |
| webrtc_low_raw50 | 27/47 | 33/47 |
| webrtc_moderate | 30/47 | 33/47 |
| webrtc_moderate_raw25 | 29/47 | 33/47 |
| webrtc_moderate_raw50 | 28/47 | 33/47 |

`labeled_scores.csv` contains only its header because every window is
`unlabeled`. `keyword_scores.csv` likewise marks counts as unlabeled evidence.
`error_deltas.csv` records changed hypotheses relative to legacy as
`different_unlabeled`, never as fixes or regressions.

## Required Questions

- Is denoise needed at all? Unknown without labels.
- Which channel or pair is best? Unknown; raw channel 3 has the most nonempty
  constrained hypotheses, but nonempty is not correctness.
- Does HPF-only help? Not demonstrated; it has one fewer nonempty constrained
  hypothesis than legacy, with unknown correctness.
- Is WebRTC better than legacy? Not demonstrated.
- Does restoring dry signal help? Not demonstrated.

## Artifacts

- `outputs/frontend_manifest.json`
- `outputs/frontend_metrics.csv`
- `outputs/eval_windows.csv`
- `outputs/eval_windows_labeled.csv`
- `outputs/fixed_window_asr_summary.csv`
- `outputs/fixed_window_asr_events.jsonl` (ignored large timeline)
- `outputs/labeled_scores.csv`
- `outputs/keyword_scores.csv`
- `outputs/error_deltas.csv`
- `outputs/unlabeled_hypothesis_summary.csv`

## Next Step

Listen to and label the fixed windows independently of Vosk output, prioritizing
keyword windows and the nine available controls. Only then run
`score_labeled_windows.py`, calculate keyword correctness/false activations,
and prune to at most four candidates. No winner should be selected before that.

## Verification

- `FRONTEND_REPLACEMENT_TEST_OK`; Python compilation passed.
- Android `AlignedFourChannelMixerTest` and `RawLightDenoiserTest`: Gradle exit
  0, `BUILD SUCCESSFUL`.
- `flutter test`: exit 0, 489 tests passed.
- `flutter analyze`: exit 1, 506 pre-existing warning/info diagnostics and no
  reported analyzer errors. This is not reported as a successful analyze run.
- `git diff --check`: passed.
