# Offline WebRTC NS A/B Report

## Verdict

INCONCLUSIVE — NEEDS MANUAL SEGMENT LABELS

The real WebRTC APM binding ran successfully, and all five variants were
replayed through Vosk. No NS level qualifies as preliminarily better: every
level changes constrained endpoints and at least one recording has either more
empty finals or fewer nonempty finals. The two recordings have no timestamped
ground-truth labels, so changed text cannot be classified honestly as a
correction, a regression, or a false command activation.

Recommendation: `нужна ручная разметка существующих записей`. Do not add an
Android/JNI integration from this evidence.

## Verified Base

- Branch: `experiment/aligned-audio-frontend`
- Expected pre-harness HEAD: `ff09b62e823a4d8610071b2ce79223957eb59585`
- Actual HEAD: `28e621836793111680a21b9e71bdf848fe309e81`
- The delta from `ff09b62` initially contained only offline experiment files;
  Android production source files are unchanged by this experiment.
- Host Python: 3.11.15. Python 3.10 is unavailable; system Python 3.14.3 was
  not used.
- WebRTC binding: `webrtc-audio-processing==0.1.3`, built locally with SWIG
  4.2.0 and Python 3.11 headers.
- Offline Vosk: `vosk==0.3.45`.
- Android Vosk: `com.alphacephei:vosk-android:0.3.75@aar` in
  `packages/vosk_flutter_service/android/build.gradle`.
- Model: `assets/vosk-model-small-ru-0.22.zip`, extracted only to ignored
  `artifacts/webrtc_ns_ab/model/vosk-model-small-ru-0.22`.

| Input | Absolute path | Format | Frames |
| --- | --- | --- | ---: |
| SSP 1786194763609 | `/home/viadmin/Документы/voice_capture_2026-08-08/ssp_mono_1786194763609.wav` | PCM16 LE, 16 kHz, mono | 2,899,968 |
| SSP 1786194978795 | `/home/viadmin/Документы/voice_capture_2026-08-08/ssp_mono_1786194978795.wav` | PCM16 LE, 16 kHz, mono | 2,785,280 |
| Raw 1786194763609 | `/home/viadmin/Документы/voice_capture_2026-08-08/raw_4ch_1786194763609.wav` | PCM16 LE, 16 kHz, 4 channels | 2,911,232 |
| Raw 1786194978795 | `/home/viadmin/Документы/voice_capture_2026-08-08/raw_4ch_1786194978795.wav` | PCM16 LE, 16 kHz, 4 channels | 2,786,816 |

All files opened with Python `wave` and have compression type `NONE`.

## Commands And Exit Codes

| Command | Exit | Result |
| --- | ---: | --- |
| `python3 artifacts/webrtc_ns_ab/scripts/test_apply_webrtc_ns.py` | 0 | `WEBRTC_NS_FRAMING_TEST_OK` |
| `python3 -m py_compile` for all experiment scripts | 0 | Syntax compilation passed. |
| `python3.11 -m venv artifacts/webrtc_ns_ab/.venv` | 0 | Ignored environment created. |
| `.venv/bin/python -m pip install webrtc-audio-processing==0.1.3` | 0 | Binding built after SWIG installation. |
| Binding 320-byte smoke test | 0 | `WEBRTC_APM_IMPORT_OK` |
| `apply_webrtc_ns.py` | 0 | Ten WAVs plus manifest and basic metrics written. |
| `analyze_ns_matrix.py` | 0 | Baseline equivalence and ten-row DSP matrix written. |
| `replay_vosk_matrix.py --chunk-bytes 1280` | 0 | Original 40-ms replay written separately. |
| `replay_vosk_matrix.py --chunk-bytes 2560` | 0 | Production-equivalent 80-ms replay written separately. |

The initial binding installation failed because SWIG was missing. The relevant
error was `error: command 'swig' failed: No such file or directory`. It was
resolved by installing `swig python3.11-dev build-essential`; no denoiser
substitution was used.

## Harness Verification

| Property | Verified value |
| --- | --- |
| Input/output | Signed PCM16 little-endian, mono, 16 kHz |
| APM frame | 160 samples / 320 bytes / 10 ms |
| AEC | Off (`aec_type=0`) |
| AGC | Off (`agc_type=0`) |
| VAD | Off (`enable_vad=False`) |
| NS | On (`enable_ns=True`), policies 0 to 3 |

The APM instance is retained for all adjacent frames of one recording/level,
then recreated for every other recording/level. Only a final partial frame is
zero-padded and every output is trimmed to source length. The binding exposes
`aec_type` and `agc_type`, so the invalid `enable_aec`/`enable_agc` constructor
keywords in the supplied harness were corrected before running it.

## Output Validation

- Ten output WAVs are PCM16 LE, mono, 16 kHz and have the original sample
  count and duration.
- The two `baseline_ssp_*.wav` PCM payloads are byte-identical to the source
  SSP WAV payloads.
- Total clipped samples across all ten WAVs: 0.
- No odd PCM byte count or damaged WAV header was found.
- WebRTC APM has a stable 96-sample (6-ms) algorithmic delay; correlation,
  SI-SDR, and spectral distance below are measured after that alignment.
- 10-ms boundary p95 jump is at or below ordinary p95 jump for all variants;
  no periodic 100-Hz boundary artifact was observed in the envelope check.

## DSP Matrix

`energy_300_3400_hz` is the speech-band energy and `energy_gt_3400_hz` is the
high-frequency energy. Full precision, boundary, crest-factor and SI-SDR data:
`outputs/ns_dsp_matrix.csv`.

| Recording | Variant | RMS | Speech energy | HF energy | Corr. | LSD dB |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| 1786194763609 | baseline | 0.009554 | 7.062 | 0.0551 | 1.0000 | 0.00 |
| 1786194763609 | low | 0.009360 | 6.971 | 0.0152 | 0.9982 | 5.76 |
| 1786194763609 | moderate | 0.009457 | 7.099 | 0.0061 | 0.9967 | 10.84 |
| 1786194763609 | high | 0.009443 | 7.086 | 0.0031 | 0.9953 | 15.90 |
| 1786194763609 | very-high | 0.009430 | 7.076 | 0.0022 | 0.9945 | 18.88 |
| 1786194978795 | baseline | 0.024922 | 38.248 | 83.8010 | 1.0000 | 0.00 |
| 1786194978795 | low | 0.023705 | 33.871 | 78.2236 | 0.9957 | 5.73 |
| 1786194978795 | moderate | 0.024331 | 36.452 | 81.5818 | 0.9923 | 10.94 |
| 1786194978795 | high | 0.024229 | 36.183 | 80.9077 | 0.9889 | 16.07 |
| 1786194978795 | very-high | 0.024128 | 35.934 | 80.2147 | 0.9865 | 18.98 |

Higher NS levels progressively increase spectral distance. Lower RMS is not
treated as an improvement. High and very-high remove more high-frequency
energy than low/moderate, so they cannot win solely by reducing noise.

## ASR Matrix

Production uses 16-kHz PCM, screen-specific grammar from `VoiceActionCatalog`,
includes `[unk]`, and batches four 640-byte VAD frames: 2,560 bytes / 80 ms.
The original harness value, 1,280 bytes, is 40 ms rather than 80 ms. Both runs
are preserved; the 80-ms run is the primary comparison.

80-ms aggregate counts across both recordings:

| Variant | Mode | Endpoints | Nonempty finals | Empty finals |
| --- | --- | ---: | ---: | ---: |
| baseline | command_menu | 42 | 21 | 23 |
| low | command_menu | 45 | 22 | 25 |
| moderate | command_menu | 43 | 20 | 25 |
| high | command_menu | 44 | 20 | 26 |
| very-high | command_menu | 41 | 19 | 24 |
| baseline | free_text | 44 | 36 | 10 |
| low | free_text | 44 | 35 | 11 |
| moderate | free_text | 45 | 38 | 9 |
| high | free_text | 45 | 37 | 10 |
| very-high | free_text | 43 | 33 | 12 |

No level is non-regressive across both constrained recordings. Low increases
command empty finals by two, moderate/high reduce constrained nonempty finals,
and very-high reduces constrained nonempty finals and increases free-text empty
finals. Moderate improves aggregate free-text counts, but cannot be called a
win without labels and while command-menu counts regress.

Primary 80-ms evidence:

- Full timeline: `outputs/replay_80ms/ns_asr_events.jsonl`
- Summary: `outputs/replay_80ms/ns_recognition_summary.csv`
- Changed hypotheses: `outputs/ns_variant_deltas.csv` (1,809 rows)
- Keyword partial/final extract: `outputs/ns_keyword_events.csv` (4,023 rows)
- Terminal endpoint/final extract: `outputs/ns_terminal_events.csv` (281 rows)

The original 40-ms evidence is isolated under `outputs/replay_40ms/` and must
not be conflated with the 80-ms production-equivalent replay.

## Yellow

In the 80-ms free-text replay of recording `1786194978795`, baseline has the
partial `жёлтыми волосами` at 38.160-38.560 s; high NS has `жёлтый` at
40.560-41.920 s. These timestamps are not automatically comparable because
endpoint segmentation changed. The full per-variant partial/final evidence is
in `outputs/ns_keyword_events.csv`; no `зал пример` or `жопы` hypothesis was
observed in this replay. A human label of the spoken segment is required before
calling either hypothesis better.

## Availability And Background Speech

`доступность` remains present in command-menu endpoint output for baseline and
NS variants, but its endpoint timing and surrounding command sequence change.
For example, the baseline endpoint in recording `1786194763609` is at 112.560
s, while low/moderate/high/very-high alter nearby constrained segmentation.
The detailed timestamps and partial/final text are in
`outputs/ns_keyword_events.csv` and `outputs/ns_variant_deltas.csv`.

No timestamped labels identify background speech, intended commands, or false
activations. Therefore preserved, newly appearing, and disappearing command
hypotheses are deliberately classified as `different_unclear`, not as false
activations added/removed.

## Risks

### Blocker

- No blocker remains for the offline binding or matrix generation.

### High

- Neither recording has segment-level ground truth. Command correctness and
  false activations cannot be measured from recognizer text alone.

### Medium

- Host Vosk 0.3.45 differs from Android Vosk 0.3.75. The offline result is
  comparative ASR evidence, not device timing certification.
- APM adds 6 ms of algorithmic delay; Android integration, if ever justified,
  must account for it.

### Low

- Two recordings are not a representative production dataset.
