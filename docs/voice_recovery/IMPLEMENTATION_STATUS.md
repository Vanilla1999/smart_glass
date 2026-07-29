# Voice Recovery Implementation Status

## Noise-Robust Screen-Scoped Voice Grammar

Reviewed artifact: `f1e26f60161b3fdd0648b042ec7969dd254a3cae` on
`feature/native-uac4-voice`. Hardware validation is not part of this run.

| Area | Status | Automated evidence | External validation |
|---|---|---|---|
| Immutable screen grammar and validation | DONE | Catalog, collision, root-back, and dynamic callback tests | T2151 grammar accuracy |
| Vosk endpoint utterances | DONE | Production control-service, endpoint-boundary, max-duration, and partial-retraction tests | Real Vosk accuracy |
| Runtime grammar switching | DONE | 100 switches, no-op, failure recovery, rollback, latest-wins, and PCM cutover tests | Device p50/p95 |
| Grammar-first free text | DONE | Readiness, endpoint aggregation, epoch cancellation, and timeout tests | Real WAV/UAC corpus |
| Fixed 20 ms PCM framing | DONE | `pcm_frame_accumulator_test.dart` | UAC4 format confirmation |
| Robust VAD calibration | DONE | Time-based calibration and percentile tests | T2151 noise A/B |
| Host `VoiceReplayRunner` | DONE | Synthetic PCM replay suite | Real WAV/UAC corpus |
| T2151 scenario matrix | DEVICE_PENDING | Test plan exists | Full hardware run |

Implementation rules now enforced:

- `acceptWaveformBytes() == true` calls `getResult()`, closes one
  `commandUtteranceId`, clears its PCM, and permits the next command.
- External acoustic VAD endpoints do not finalize or reset the command
  recognizer.
- Grammar changes commit route and grammar revisions only after successful
  bounded `reset`/`setGrammar`; timeout recovery configures a replacement with
  the requested target grammar before committing revisions.
- Stable partial execution uses a 150 ms timer with an explicit
  `partialRevision` guard. Tests advance an injected manual clock.
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
| Recovery and integration tests | Passed: 73 tests |
| `fvm flutter test` | Passed: 233 tests |
| `fvm flutter analyze` | Completed with 311 existing project issues and no compile error |
| `./gradlew :app:compileDebugKotlin` | Passed |
| `git diff --check` | Passed |

## Remaining External Validation

- Replay a committed real WAV/UAC PCM corpus.
- Run the documented T2151 noise and false-command matrix.
- Measure command and grammar-switch p50/p95 on T2151.
- Measure CPU, GC, and memory during a long UAC4 session.
- Record the real-store false-command rate.
