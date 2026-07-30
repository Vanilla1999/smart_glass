# Voice Recovery Implementation Status

## Noise-Robust Screen-Scoped Voice Grammar

Reviewed baseline: `f1e26f60161b3fdd0648b042ec7969dd254a3cae` on
`feature/native-uac4-voice`. The dual-endpoint patch was validated from a dirty
working tree on a physical T2151; commit the patch before treating the evidence
as release evidence.

| Area | Status | Automated evidence | External validation |
|---|---|---|---|
| Immutable screen grammar and validation | DONE | Catalog, collision, root-back, and dynamic callback tests | T2151 grammar accuracy |
| Vosk endpoint utterances | DONE | Natural endpoint, serialized VAD-silence fallback, timeout replacement, max-duration, restart, and partial-retraction tests | Real Vosk accuracy |
| Runtime grammar switching | DONE | 100 switches, no-op, failure recovery, rollback, latest-wins, and PCM cutover tests | Device p50/p95 |
| Grammar-first free text | DONE | Readiness, endpoint aggregation, epoch cancellation, and timeout tests | Real WAV/UAC corpus |
| Fixed 20 ms PCM framing | DONE | `pcm_frame_accumulator_test.dart` | UAC4 format confirmation |
| Robust VAD calibration | DONE | Time-based calibration and percentile tests | T2151 noise A/B |
| Host `VoiceReplayRunner` | DONE | Synthetic PCM replay suite | Real WAV/UAC corpus |
| T2151 scenario matrix | IN_PROGRESS | Controlled command sequence passed on `t2151_voice_recognition` | Remaining profiles, noise, and long-run matrix |

Implementation rules now enforced:

- `acceptWaveformBytes() == true` calls `getResult()`, closes one
  `commandUtteranceId`, clears its PCM, and permits the next command.
- A natural Vosk endpoint remains primary. An acoustic `silence` endpoint
  serially performs bounded `getFinalResult`, result arbitration, utterance
  finalization, and `reset` before subsequent PCM. `maxDuration` does not force
  a decoder boundary.
- Grammar changes commit route and grammar revisions only after successful
  bounded `reset`/`setGrammar`; timeout recovery configures a replacement with
  the requested target grammar before committing revisions.
- Only `up` and `down` execute from exact partials. Every other production
  command is endpoint-only, and catalog validation rejects any partial policy
  outside that explicit allowlist. No production action uses the existing
  stable-partial timer.
- Typed commands are revalidated against screen, route revision, and grammar
  revision immediately before UI execution.
- Typed free-text phrases receive the same consumer-side context validation.
- A failed free-text factory call remains retryable; a timed-out native
  recognizer is detached and replaced before the next replay.
- A timed-out command recognizer is disposed only after its pending native
  operation completes; exhausted grammar recovery marks the session unavailable.
- Per-utterance partial state is bounded to 128 entries.
- `WearVoiceSession` serializes screen configuration and applies latest-wins
  semantics to rapid route changes.
- Live PCM is not sent to free text in parallel. A no-command endpoint replays
  a bounded five-second utterance snapshot through the free-text serial queue.

## Verification

| Command | Result |
|---|---|
| `fvm dart format <changed Dart files>` | Passed |
| Recovery and integration tests | Passed: 81 tests (26 pipeline + 55 voice/session/integration) |
| `fvm flutter test` | Passed: 241 tests |
| `fvm flutter analyze` | Completed with 311 existing project issues and no compile error |
| `./gradlew :app:compileDebugKotlin` | Passed |
| `git diff --check` | Passed |

## T2151 Dual-Endpoint Check (2026-07-29)

- Profile: `VOICE_DEVICE_PROFILE=t2151_voice_recognition` with WAV diagnostics.
- Device: Movfast T2151, Android SDK 33.
- Evidence: `docs/voice_recovery/evidence/t2151_dual_endpoint_2026-07-29.log`.
- Evidence SHA-256: `b94fb29cb362838aacc7d55cd733dce164e9a54974c0f0406b8273a4dc3ed72a`.
- Controlled menu sequence `down, down, up, down, up` executed once per phrase
  with command utterance IDs `6, 7, 8, 9, 10`.
- No `вниз вниз`, `вниз вверх`, or `вверх назад` recognition result occurred.
- Every controlled utterance closed through `utteranceEndOwner=vad_silence`;
  forced-close duration was 27-52 ms with no recognizer replacement.
- `acousticSpeechToCommandMs` p50/p95: 550/575 ms.
- Command-to-glasses-frame p50/p95: 15/22 ms.
- This check does not close the remaining profile, noise, false-command,
  corpus, CPU/GC, memory, or long-run requirements.

## Remaining External Validation

- `DEVICE_PENDING`: rerun the partial-policy safety matrix on a clean release
  build from a physical T2151. Verify zero route-changing
  `source=stable_partial` emissions and count false endpoint commands separately.
- A false `streamFinal="выбрать"` has already been observed. This policy patch
  does not correct false endpoint recognition. Acoustic verification, phrase
  hardening, and speaker gating remain separate follow-up work.
- Replay a committed real WAV/UAC PCM corpus.
- Run the documented T2151 noise and false-command matrix.
- Measure command and grammar-switch p50/p95 on T2151.
- Measure CPU, GC, and memory during a long UAC4 session.
- Record the real-store false-command rate.
