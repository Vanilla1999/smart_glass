# Final utterance-level frontend A/B

## FINAL VERDICT

**NO MATERIAL DIFFERENCE — KEEP LEGACY**

On the two supplied recordings, no candidate demonstrated a material or
statistically supported improvement over `legacy_reference`. Several candidates
scored 82/84 instead of 81/84, but every one of them fixed the same single clip
(`1786194763609_cmd_002`, expected `вниз`). The exact paired McNemar p-value is
1.0. All frontends rejected all 30 negative clips, so there is no false-
activation advantage to distinguish them.

Production should remain unchanged. In particular, this result does not justify
adding WebRTC/JNI integration.

## Dataset Validation

- Archive SHA-256:
  `fc203375df9f0a4aed4fd8648eeca192a5d5f584cfd6e651e204efcc36207a0c`.
- 84 command clips, 30 negative clips, 114 manifest rows, 228 source WAVs.
- Raw clips: PCM16 LE, 16 kHz, four channels.
- SSP clips: PCM16 LE, 16 kHz, mono.
- Every command row has `expected_text`; every negative row has an empty label.
- Both built-in and independent structural validation passed.
- Ten command raw/SSP pairs were cross-correlated after the dataset's alignment;
  residual lags were within approximately +/-0.25 ms. The documented -252/-256
  sample source offset was not applied a second time.
- No clips were excluded. Automated validation cannot replace the requested
  human auditory label review; no human listening was performed in this run.

The final score uses only the new `manifest.csv`. The historical 47 windows and
68 labeling segments were not used.

## Execution Contracts

- Generated 1,938 independent frontend WAVs: 114 clips x 17 frontends.
- Ran 3,876 Vosk recognizers: command grammar and diagnostic free text.
- A fresh WebRTC APM was created for every clip and NS level.
- A fresh `KaldiRecognizer` was created for every clip, frontend, and mode.
- Vosk input chunks were 2,560 bytes (80 ms), followed by `FinalResult()`.
- WebRTC used mono PCM16 at 16 kHz, 160-sample frames, AEC/AGC/VAD off, and
  96-sample frontend delay compensation.
- WebRTC was applied directly to `raw_mix123`, never after the legacy frontend.

## All Frontends

`Strict` is out of 84 commands and `FA` is out of 30 negative clips. There were
no substitutions, insertions, or multiple-wrong results for any frontend; all
command errors were misses. No command-grammar result required a morphological
relaxation, so relaxed and strict scores are identical.

| Frontend | Strict | Relaxed | Miss | Subst. | Insert. | FA | Status |
|---|---:|---:|---:|---:|---:|---:|---|
| `legacy_reference` | 81 | 81 | 3 | 0 | 0 | 0 | BEST |
| `hpf80_mix123` | 82 | 82 | 2 | 0 | 0 | 0 | VIABLE |
| `raw_ch0` | 80 | 80 | 4 | 0 | 0 | 0 | WORSE THAN LEGACY |
| `raw_ch1` | 81 | 81 | 3 | 0 | 0 | 0 | NO MATERIAL BENEFIT |
| `raw_ch2` | 81 | 81 | 3 | 0 | 0 | 0 | NO MATERIAL BENEFIT |
| `raw_ch3` | 82 | 82 | 2 | 0 | 0 | 0 | VIABLE |
| `raw_mix123` | 82 | 82 | 2 | 0 | 0 | 0 | VIABLE |
| `raw_pair01` | 81 | 81 | 3 | 0 | 0 | 0 | NO MATERIAL BENEFIT |
| `raw_pair12` | 82 | 82 | 2 | 0 | 0 | 0 | VIABLE |
| `raw_pair13` | 82 | 82 | 2 | 0 | 0 | 0 | VIABLE |
| `raw_pair23` | 82 | 82 | 2 | 0 | 0 | 0 | VIABLE |
| `webrtc_low` | 82 | 82 | 2 | 0 | 0 | 0 | NO MATERIAL BENEFIT |
| `webrtc_low_raw25` | 82 | 82 | 2 | 0 | 0 | 0 | NO MATERIAL BENEFIT |
| `webrtc_low_raw50` | 82 | 82 | 2 | 0 | 0 | 0 | NO MATERIAL BENEFIT |
| `webrtc_moderate` | 82 | 82 | 2 | 0 | 0 | 0 | NO MATERIAL BENEFIT |
| `webrtc_moderate_raw25` | 82 | 82 | 2 | 0 | 0 | 0 | NO MATERIAL BENEFIT |
| `webrtc_moderate_raw50` | 82 | 82 | 2 | 0 | 0 | 0 | NO MATERIAL BENEFIT |

## Comparison With Legacy

- `hpf80_mix123`, `raw_ch3`, `raw_mix123`, pairs 12/13/23, and every WebRTC
  variant fixed `1786194763609_cmd_002` (`вниз`) and introduced no strict
  regressions or false activations.
- `raw_ch1` and `raw_pair01` produced exactly the same correctness as legacy.
- `raw_ch2` fixed `1786194763609_cmd_002` but regressed
  `1786194978795_cmd_005` (`вверх`), for no net gain.
- `raw_ch0` fixed nothing and regressed `1786194978795_cmd_008` (`вниз`).
- No frontend removed or added a false activation because legacy and every
  candidate had zero false activations.

Only `raw_ch0` is strictly dominated by legacy under the pruning rule. The
shortlist is `legacy_reference`, `raw_ch3` (simplest best raw),
`hpf80_mix123` (simple production-equivalent filter), and `webrtc_low` (least
aggressive best-scoring WebRTC representative). This shortlist does not imply a
production change: none beats legacy with meaningful evidence.

## Keyword Results

Legacy and `webrtc_moderate` had identical keyword totals except for `вниз`.

| Keyword | Total | Legacy | WebRTC moderate | Note |
|---|---:|---:|---:|---|
| `вверх` | 14 | 14 | 14 | no regression |
| `вниз` | 13 | 12 | 13 | moderate fixed one legacy miss |
| `печать` | 4 | 4 | 4 | unchanged |
| `белый` | 3 | 3 | 3 | unchanged |
| `жёлтый` | 14 | 14 | 14 | no critical regression |
| `назад` | 10 | 10 | 10 | unchanged |
| `доступность` | 8 | 7 | 7 | same miss: `cmd_032` |
| `список` | 3 | 3 | 3 | unchanged |
| `молочная` | 2 | 2 | 2 | unchanged |
| `коровка` | 8 | 7 | 7 | same miss: `cmd_039` |

Each rare keyword (`безалкогольное`, `святой`, `источник`, `напитки`, and
`мобильный`) occurred once and was recognized by both frontends. These samples
are reported but are too sparse for a strong conclusion.

## WebRTC Moderate

`webrtc_moderate` achieved 82/84 strict correct (97.62%), two misses, and 0/30
false activations. Relative to legacy it:

- fixed `1786194763609_cmd_002` (`вниз`);
- did not introduce any strict command regression;
- preserved all 14 `жёлтый` clips;
- preserved seven of eight `доступность` clips, matching legacy;
- missed the same `1786194978795_cmd_032` (`доступность`) and
  `1786194978795_cmd_039` (`коровка`) as every 82/84 candidate;
- produced no command insertion, substitution, or negative false activation.

This is technically viable but not a demonstrated denoiser win. The same one-
clip improvement appears with HPF-only, raw channel 3, raw mixing, raw pairs,
WebRTC low, and every dry/wet blend. `webrtc_moderate` also changed diagnostic
free-text output on 16/114 clips, but free-text variation is not the command
score and does not establish better recognition. With McNemar p=1.0 and an
absolute gain of only 1/84 (1.19 percentage points), its JNI/dependency cost is
not justified.

## Rejected Or Non-Winning Variants

- `raw_ch0`: worse; one additional miss and no offsetting improvement.
- `raw_ch1`, `raw_pair01`: no result change versus legacy.
- `raw_ch2`: one fix and one new miss; no net improvement.
- Other 82/84 raw, pair, mix, and HPF variants: one non-significant fix; useful
  candidates for validation on unseen audio, not enough for replacement now.
- All WebRTC variants: identical strict score and false-activation count to
  simpler 82/84 frontends; added complexity without unique measured benefit.

## Remaining Risk

The dataset contains two recordings from one main speaker and one background
scenario. The result applies only to those recordings. A future decision should
evaluate the shortlist on a new, untouched recording with human-confirmed
utterance labels. If that recording repeatedly favors one candidate, production
integration can then be reconsidered.
