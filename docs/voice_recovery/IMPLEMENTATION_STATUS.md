# Voice Recovery Implementation Status

## Baseline

- Branch: `main`
- HEAD: `14899f0bd1467766c314b8a962863039923346c7`
- Baseline command: `git status --short && git branch --show-current && git rev-parse HEAD`
- Baseline result: clean worktree, branch `main`, SHA above.

`DONE` requires implemented code, formatting, an automated test that was run, and no known code-level defect. T2151-only validation remains `DEVICE_PENDING`.

| ID | Task | Status | Evidence |
|---|---|---|---|
| V01 | Audit current implementation and baseline | DONE | Audit completed against HEAD `14899f0`; historic APK identity not assumed. |
| V02 | Build fingerprint and capture ID in logs | DEVICE_PENDING | Dart and Android build logs plus per-recorder capture ID added; verify output on T2151. |
| V03 | Unified VoiceState state machine | DONE | Production `WearModuleApp` renders only `WearVoiceSession.stateStream`; callback-derived state remains limited to explicit test injection. |
| V04 | Startup without speech or RMS requirement | DONE | Startup gate requires 3 valid chunks from the active capture in 2 seconds; `voice_capture_recovery_gate_test.dart` passed. |
| V05 | Health check for stale/missing/zero PCM | DONE | Missing/stale PCM and exact-zero gate thresholds are covered by deterministic unit tests. |
| V06 | Android capture silenced handling | DEVICE_PENDING | State moves to suspended and unsilence schedules one restart; widget coverage exists, native behavior requires T2151. |
| V07 | Hard recorder recreation | DONE | `VoiceRecorderLifecycle` stops, disposes, then creates the replacement recorder; order is unit-tested. |
| V08 | Single-flight recovery | DONE | `VoiceSingleFlight` is used by restart and tested with concurrent requests plus a later restart. Scheduled retry is cancelled when a restart begins. |
| V09 | Retry with backoff | IN_PROGRESS | Health checks defer while an unavailable retry is scheduled and stale retry timers are cancelled, but production-path timer tests are still missing. |
| V10 | Correct app lifecycle handling | DEVICE_PENDING | Only hidden/paused arm the resume restart; widget test passed for paused/resumed, T2151 validation remains. |
| V11 | Safe Vosk pipeline stop | IN_PROGRESS | Timed-out work is isolated on replaced recognizers and stale partial mutations are suppressed; a blocking-recognizer integration test is still missing. |
| V12 | Block commands outside ready | DONE | UI suppresses commands during reconnect/unavailable; full test suite passed. |
| V13 | Phone overlay | DONE | Overlay derives from startup/recovery/unavailable state and preserves route; integration tests passed. |
| V14 | Independent glasses overlay | IN_PROGRESS | Overlay revision is process-global and the cubit rejects equal/stale revisions; sender recreation is not yet tested through the bridge. |
| V15 | Restore overlay after Presentation | DEVICE_PENDING | `MainActivity` recreates the wear Presentation after detach, restores its payload, and reapplies the visible overlay; requires secondary-display validation. |
| V16 | Authentication and navigation independence | DONE | Removed `waitForStartup()` from success status pop; integration suite passed. |
| V17 | Native audio diagnostics | DEVICE_PENDING | Flutter now supplies active capture ID/source to native monitoring; inspect source, silencing, format, and routed-device values on T2151. |
| V18 | Audio source/device profile | DEVICE_PENDING | `default`, `t2151`, `t2151_voice_recognition`, and `t2151_microphone` profiles select source and hard-restart policy; A/B hardware results are pending. |
| V19 | Verify microphone foreground service | DEVICE_PENDING | Manifest has microphone permissions and `foregroundServiceType`; validate runtime service behavior on T2151. |
| V20 | State-machine unit tests | IN_PROGRESS | Voice state, startup/health gates, recorder lifecycle, single-flight, retry, overlay revision, and delayed-Vosk primitives are covered; production session and blocking-recognizer tests remain. |
| V21 | Integration tests | DONE | `fvm flutter test`: 160 passed. |
| V22 | T2151 hardware verification plan | DONE | `docs/voice_recovery/T2151_TEST_PLAN.md` created. |
| V23 | Final documentation | DONE | This status file and test plan contain implementation evidence and remaining constraints. |

## Execution Log

### V01 - Audit current implementation and baseline

- Status: `DONE`
- Changed files: `lib/modules/wear/services/wear_voice_session.dart`, `lib/modules/wear/domain/service/voice_typing/audio_stream_service.dart`, `lib/modules/wear/domain/service/voice_typing/speech_recognition_service.dart`, `lib/modules/wear/presentation/widgets/wear_module_app.dart`, `android/app/src/main/kotlin/ru/tander/smart_glasses/MainActivity.kt`.
- Automated tests: `fvm flutter test`.
- Command result: 160 tests passed.
- T2151 remaining: run the documented hardware plan.
- Known limitations: no claim is made that the APK associated with historic logs was built from this HEAD.

### Implementation delivered after baseline audit

- `VoiceState` is the authoritative state for the wear voice session; `WearModuleApp` gates commands and renders overlays from its phase.
- Startup is healthy after three PCM chunks from the active capture generation. It does not depend on speech, a Vosk result, RMS, or non-zero PCM.
- The session detects stale and exact-zero PCM, recreates the recorder for recovery, and uses a capped retry schedule after failed startup.
- Vosk callbacks are capture-epoch scoped and queue shutdown is bounded so a previous capture cannot deliver results to a replacement capture.
- Native glasses overlay state is cached independently of regular wear payloads, applied after `/wear` navigation, and cleared by `visible=false`.
- `VOICE_DEVICE_PROFILE` supports T2151 `voiceCommunication`, `voiceRecognition`, and `mic` A/B builds. Profile resolution is unit-tested.
- `VoiceSingleFlight` prevents concurrent restart operations; `VoiceRecorderLifecycle` makes recorder stop/dispose/create ordering explicit and testable.
- Delayed Vosk processing is bounded by `VoiceRecognitionProcessingQueue`; invalidated `VoiceRecognitionCaptureEpoch` values suppress stale capture work.

## Review Remediation

- Startup and restart readiness use the replacement capture's own chunk counter, not the counter from a prior recorder.
- Cancellation and Android silencing stop readiness before `ready` can be emitted.
- Recovery owns retry scheduling: a new restart cancels stale retry work, while periodic health checks defer to a scheduled retry.
- A timed-out Vosk operation keeps its old recognizer isolated; a replacement capture receives fresh recognizers and stale work cannot update partial text.
- Overlay revisions are monotonic for the process, and the glasses cubit rejects duplicate revisions.
- Native silencing monitoring receives the selected source and capture ID; all supported profiles are monitored by their configured source.
- A detached glasses Presentation is recreated with the cached wear payload and current voice overlay.

## Verification Log

| Command | Result |
|---|---|
| `fvm dart format` on changed Dart files | Passed. |
| `fvm flutter pub get` | Passed; 53 dependency updates are available but not applied. |
| `fvm flutter test` | Passed: 160 tests. |
| `fvm flutter analyze` | Completed with 315 pre-existing/project lint warnings and no compile errors. |
| `./gradlew :app:compileDebugKotlin` | Passed before final APK build; Gradle reports existing deprecation warnings. |
| `fvm flutter build apk --debug --dart-define=GIT_SHA=14899f0bd1467766c314b8a962863039923346c7 --dart-define=BUILD_TIMESTAMP=2026-07-24 --dart-define=VOICE_DEVICE_PROFILE=t2151` | Passed; output `build/app/outputs/flutter-apk/app-debug.apk`. |

## Changed Behavior

- Startup accepts technically healthy capture after three current-generation PCM chunks; it does not require speech, a Vosk result, high RMS, or non-silent PCM.
- Low RMS is diagnostic-only. Missing chunks and prolonged exact-zero raw PCM remain recovery triggers.
- Recovery stops the old stream, releases its recorder, creates a new recorder, changes capture epoch, and retries with capped backoff after failure.
- Startup/recovery/unavailable state is streamed as `VoiceState`; UI blocks commands outside `ready` and renders independent overlays.
- `WearModuleApp` uses a scheduling guard to coalesce simultaneous router and post-frame startup requests without calling `setState` during router construction.
- Glasses overlay messages now carry typed phase and monotonic revision, remain above normal wear payloads, and are reapplied by `MainActivity` after wear navigation.
- `MainActivity` applies a visible overlay only after `/wear` navigation acknowledges and clears its cached overlay when Flutter sends `visible=false`.
- `VoiceDeviceProfile` selects `voiceCommunication`, `voiceRecognition`, or `mic` through `VOICE_DEVICE_PROFILE`; the T2151 A/B matrix is documented in `T2151_TEST_PLAN.md`.
- Successful status navigation no longer waits for voice startup.

## Remaining Device Validation Work

- Strengthen Android recording ownership correlation beyond source matching when the `record` package exposes a stable session identifier or a minimal local bridge is introduced.
- Run and record the T2151 plan for every supported voice profile. Do not change the default `voiceCommunication` source without that evidence.
