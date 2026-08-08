# Audio frontend A/B report

## Verdict

**ALIGNED WORSE** on these two recordings. The aligned frontend changes the
waveform, but it does not improve constrained commands and creates additional
free-text misses. This is preliminary: two recordings in one noisy scenario
are not production-quality evidence.

## Checked base

| Item | Value |
| --- | --- |
| Branch | `experiment/aligned-audio-frontend` |
| Commit | `259c4a572d47667ea8dec78ec9a1ad5a089c4117` |
| Input raw | PCM16 LE, 16 kHz, 4 channels |
| Input SSP | PCM16 LE, 16 kHz, mono |
| Model | `assets/vosk-model-small-ru-0.22.zip` / `vosk-model-small-ru-0.22` |
| Android Vosk dependency | `com.alphacephei:vosk-android:0.3.75` |
| Offline replay core | `vosk` Python `0.3.45` |

Initial `git status --short` already had untracked package build output and a
lockfile. This experiment additionally creates `artifacts/`; no existing
production source was changed.

## Implementation review

`AlignedFourChannelMixer` uses causal delays `[3, 0, 2, 2]`, keeps per-channel
ring history across `mix()` calls, and clears it in `reset()`. Its PCM decoder
is signed little-endian PCM16. It divides the sum by four and by 32768. The
production denoiser requires 2048-byte input frames and emits 512 bytes = 256
mono samples. The runner kept an instance for each whole recording and did not
call `reset()` between adjacent frames. No frame-boundary discontinuity was
found: boundary p95 / ordinary p95 is 0.994--1.014 for raw-derived output.

## Automated checks

| Command | Exit | Result |
| --- | ---: | --- |
| `./gradlew :app:testDebugUnitTest --tests 'ru.tander.smart_glasses.voice.AlignedFourChannelMixerTest' --tests 'ru.tander.smart_glasses.voice.RawLightDenoiserTest'` | 0 | pass |
| `flutter test` | 0 | 489 passed |
| `flutter analyze` | 1 | 0 errors; 506 pre-existing warnings/info diagnostics |
| `git diff --check` | 0 | pass |

Gradle emitted Kotlin-plugin, flat-directory and deprecation warnings. Flutter
analysis had warnings (notably unused imports/fields) and info (mainly
`avoid_print` and deprecations), none in the experiment sources.

## DSP results

Detailed values are in `metrics.csv` and `ssp_comparison.csv`.

| Recording | Frontend | Duration s | RMS | Peak dBFS | Clips | Speech-band energy | Boundary p95 ratio |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 4763609 | SSP | 181.248 | 0.00955 | -13.72 | 0 | 7.06 | 1.000 |
| 4763609 | Legacy | 181.952 | 0.00954 | -13.72 | 0 | 7.03 | 0.994 |
| 4763609 | Aligned | 181.952 | 0.00982 | -13.22 | 0 | 7.43 | 1.000 |
| 4978795 | SSP | 174.080 | 0.02492 | -6.00 | 0 | 83.80 | 0.995 |
| 4978795 | Legacy | 174.176 | 0.02492 | -6.00 | 0 | 83.77 | 0.994 |
| 4978795 | Aligned | 174.176 | 0.02609 | -4.56 | 0 | 93.56 | 1.014 |

No output has NaN, clipping, a bad WAV header, a changed sample rate, or a
duration change. The raw-derived WAV length matches each raw input exactly;
the vendor SSP is 704 and 96 samples shorter respectively. The 62.5 Hz block
envelope power has no new periodic spike: aligned is lower on recording one
and only modestly higher on recording two, while boundary jumps remain normal.

Legacy and SSP are sample-identical over their common duration after offset
zero (correlation 1.0; lag 0). Aligned versus SSP has lag -2/-1 samples,
correlation 0.9918/0.9893, SI-SDR 17.80/16.62 dB, and log spectral distance
7.48/7.22 dB. Therefore alignment is a real frontend alteration, not merely a
gain change; SSP closeness is not treated as the winning metric.

## Vosk configuration and results

Production creates two recognizers at 16 kHz. It receives 640-byte / 20 ms VAD
frames and batches four to 1280 bytes / 80 ms for the command recognizer.
Command recognizer grammar is `VoiceActionCatalog.grammarFor(screen)`, including
`[unk]`; menu grammar here is the exact production menu phrase set. Free text
has no command grammar, supports replay, and production calls
`acceptWaveformBytes`, then partial/result/final JSON methods. The offline
runner logs every partial, endpoint and terminal final to `asr_events.jsonl`.

| Recording | Frontend | Menu nonempty / empty finals | Free-text nonempty / empty finals | Important delta |
| --- | --- | --- | --- | --- |
| 4763609 | SSP | 21 / 26 | 40 / 15 | baseline |
| 4763609 | Legacy | 21 / 26 | 40 / 15 | exact SSP behavior |
| 4763609 | Aligned | 21 / 26 | 38 / 15 | no command gain; fewer free-text results |
| 4978795 | SSP | 23 / 22 | 42 / 10 | baseline |
| 4978795 | Legacy | 23 / 22 | 42 / 10 | exact SSP behavior |
| 4978795 | Aligned | 20 / 24 | 41 / 10 | 3 fewer constrained results |

This fixed menu grammar intentionally cannot assess dynamic product grammar:
the recording's product/list phrases require runtime item data that was not
captured. Free-text is the valid comparison for those words. Exact production
replay scheduling and Android Vosk 0.3.75 were not available in a local JVM;
this harness uses the same model, 16 kHz PCM and command batch size, but host
Vosk 0.3.45. Do not interpret its wall-clock processing as device latency.

## Yellow

Free text recovers all three `жёлтый` occurrences in recording 4763609 for
legacy and aligned at 74.52, 83.16 and 90.60 s. In recording 4978795, aligned
changes otherwise recognized yellow segments: 36.84 s `жёлтые` becomes `зал
пример`, and 62.52 s `жёлтый` becomes `жопы`. The first nonempty partial occurs
at 17.88 s for all 4978795 variants, before the first yellow utterance; precise
speech-to-word latency needs manual word-start timestamps and is not inferred.

## Availability

Recording 4763609 yields `доступность` at 111.48--111.96 s for all variants.
Recording 4978795 produces seven SSP/legacy free-text availability results at
87.24--107.16 s. Aligned changes the 102.60 s result to `доступны`; constrained
menu output also falls from seven to six availability results. Full partial and
endpoint chronology is in `asr_events.jsonl`.

## False commands and segmentation

With a fixed menu grammar, the background/dynamic `коровка` portion of 4978795
is decoded as `справка`: seven SSP/legacy endpoint hypotheses and four aligned
ones. These are false activations under the fixed menu replay, but are not a
faithful end-to-end product-screen command test because production would switch
grammar with screen state. Command repetitions, partial activation, and
true duplicate suppression require exact manual segment boundaries. Candidate
timestamps and all raw hypotheses are retained rather than claiming invented
hit-rate or latency metrics.

## Fixed-delay risk

`channel_delay_windows.csv` measures 10-second whole-window correlation, not
isolated owner speech. Its best offsets vary materially: channel 1 is mostly
-1/-3 samples, channel 2 -1/0/+1, and channel 3 -3 through +5 over the two
recordings. This does not corroborate a single stable `[0,+3,+1,+1]` arrival
model in this noisy mix. It may reflect television/background speech rather
than owner voice, so it is a risk signal, not a calibration replacement.

The next separate experiment should collect owner-speech calibration while
changing head pose and background source direction, then test channel weights.
Do not change equal 0.25 weights in this commit.

## Defects

| Severity | Finding |
| --- | --- |
| Blocker | None for the WAV/DSP run. |
| High | Fixed delays are not stable under whole-window correlation across these two captures; a global delay calibration may be position-sensitive. |
| Medium | Aligned causes concrete free-text regressions (`зал пример`, `жопы`, `доступны`) and fewer constrained outputs in recording 4978795. |
| Low | Desktop Vosk 0.3.45 differs from production Android Vosk 0.3.75, so host replay cannot certify device timing or exact decoder behavior. |

## Recommendation

**откатить aligned**. On these two recordings it has no important ASR win and
has observable recognition regressions. A future experiment needs a new,
pose-varied calibration recording before reconsidering alignment or weights.
