# Voice Recovery Implementation Status

## Noise-Robust Screen-Scoped Voice Grammar

Baseline: `7c09b083190d925e75288acfb3e0547e8e1f418b` on
`feature/native-uac4-voice`. Hardware validation is not part of this run.

| Area | Status | Changed files | Automated evidence | Hardware | Limitations |
|---|---|---|---|---|---|
| Immutable screen grammar and validation | DONE | `voice_action_catalog.dart`, `voice_command_parser_service.dart`, `wear_flow_controller.dart` | Catalog, collision, root-back, and dynamic callback tests passed | DEVICE_PENDING | Grammar membership follows registered `WearScreenActionHandler` callbacks plus explicit built-in navigation actions. |
| Vosk endpoint utterances | DONE | `segmented_recognition_result.dart`, `speech_recognition_service.dart`, `recognition_arbiter.dart`, `wear_voice_control_service.dart` | `test/wear_voice_control_service_test.dart`; targeted run passed 9 tests | DEVICE_PENDING | Stable-partial latency and false-positive rate require noisy T2151 measurement. |
| Runtime grammar switching | DONE | `wear_actual_screen_store.dart`, `speech_recognition_service.dart`, `wear_voice_session.dart`, `wear_module_app.dart` | Actual-route, 100-switch, stale revision, and integration tests passed | DEVICE_PENDING | Device-only grammar-switch p95 remains unmeasured. A 200 ms PCM transition buffer bridges serial `reset` + `setGrammar`. |
| Grammar-first free-text | DONE | `speech_recognition_service.dart`, `wear_voice_session.dart` | Bounded buffer and synthetic PCM replay tests passed | DEVICE_PENDING | Real Vosk accuracy still requires recorded speech corpus/device run. |
| Fixed 20 ms PCM framing | DONE | Existing `PcmFrameAccumulator` in `speech_recognition_service.dart`; expanded test | `fvm flutter test test/pcm_frame_accumulator_test.dart` | DEVICE_PENDING | UAC4 format and resampling still require device log confirmation. |
| Robust VAD calibration | DONE | `speech_segmenter.dart`, `speech_recognition_service.dart` | p20/outlier test passed; p10/p50/p90 are logged | DEVICE_PENDING | Threshold quality still requires T2151 A/B. |
| Host `VoiceReplayRunner` | DONE | `voice_replay_runner.dart` | Synthetic PCM tests cover noise, multiple utterances, `[unk]`, pagination, free text, common words, and no cooldown | DEVICE_PENDING | Real diagnostic WAV/UAC PCM corpus is absent and remains DEVICE_PENDING. |
| T2151 scenario matrix | DEVICE_PENDING | `docs/voice_recovery/T2151_TEST_PLAN.md` | Not run | DEVICE_PENDING | A single microphone cannot identify the wearer. Exact allowed speech from a nearby person can still trigger a command. |

Implementation rules now enforced:

- `acceptWaveformBytes() == true` is logged as `ENDPOINT_RESULT`, calls
  `getResult()`, closes one `commandUtteranceId`, and permits the next command
  while the acoustic VAD segment remains open.
- `getFinalResult()` is logged as `STREAM_FINAL` and is reserved for forced
  segment/stream flush and free-text replay.
- Confirmed GoRouter locations select a small grammar with `[unk]`; grammar
  changes do not stop UAC4 capture or reload the model.
- Immediate partial execution is limited to exact `вверх`/`вниз`; navigation
  aliases use a 150 ms stability timer; effectful actions are endpoint-only.
- Live PCM is not sent to free-text in parallel. A no-command endpoint replays
  a bounded five-second utterance snapshot in 80 ms batches on the lower
  priority free-text serial queue.
- `[unk]` is controlled by `VOICE_GRAMMAR_INCLUDE_UNKNOWN` (default `true`).

Fundamental limitation: one microphone plus grammar filtering cannot determine
whether the wearer or a nearby person spoke an exact active command. Risky
actions must remain endpoint-only, require confirmation or an additional user
action, and use longer distinctive phrases.

### Verification 2026-07-29

| Command | Result |
|---|---|
| `fvm dart format <changed Dart files>` | Passed. |
| `fvm flutter test test/voice_command_parser_service_test.dart test/pcm_frame_accumulator_test.dart test/wear_voice_control_service_test.dart test/wear_flow_coordinator_integration_test.dart` | Passed after updating the direct-scan test for the intentional 150 ms stability policy. |
| `fvm flutter test` | Passed: 205 tests. |
| `fvm flutter analyze` | Completed with 313 existing/project info and warnings; no compile error. This is not a clean analyzer result. |
| `./gradlew :app:compileDebugKotlin` | Passed. Existing Kotlin plugin, `flatDir`, and Gradle deprecation warnings remain. |
| Synthetic PCM replay | Passed. Real regression PCM/WAV corpus is DEVICE_PENDING because no recordings are committed. |
| T2151 hardware plan | DEVICE_PENDING: not run. |

## Strict VOICE_RECOGNITION update

- Current base HEAD: `a9fbf5d`; strict changes are uncommitted work in progress.
- Startup is post-authorization only, uses mandatory `USB-Audio - UVC`, and
  rejects missing/ambiguous UVC instead of using the T2151 built-in microphone.
- Automatic `VOICE_COMMUNICATION` fallback is disabled. Initial grace is 1500
  ms; one recreate is allowed; post-recreate grace/timeout are 3000/4000 ms.
- WAV is disabled in ordinary release builds and requires
  `VOICE_CAPTURE_WAV_DIAGNOSTICS=true`.
- Hardware validation remains `DEVICE_PENDING`.

## Baseline

- Branch: `main`
- HEAD: `9d0273daa6312e451e8b3300e5331d47d4023f8b`
- Baseline command: `git status --short && git branch --show-current && git rev-parse HEAD`
- Baseline result: clean worktree, branch `main`, SHA above. `git diff --check` returned no output.

`DONE` requires implemented code, formatting, an automated test that was run, and no known code-level defect. T2151-only validation remains `DEVICE_PENDING`.

## Final T2151 remediation

The current remediation is governed by `docs/voice_recovery/T2151_REMEDIATION_PLAN.md`.

`docs/voice_recovery/T2151_VOICE_RECOGNITION_ROLLOUT.md` records the
VOICE_RECOGNITION experiment, its ready contract, recovery rules, native work,
and device-validation matrix. It is `DEVICE_PENDING`; the existing
VOICE_COMMUNICATION selection remains the release choice until that matrix
passes.

### VOICE_RECOGNITION startup experiment (2026-07-27)

- Status: `IN_PROGRESS`; hardware validation is `DEVICE_PENDING`.
- `t2151_voice_recognition` now requires non-zero raw PCM before `ready`.
  Three exact-zero chunks keep the session in `waitingForAudioRoute`.
- After 1200 ms of continuous exact-zero PCM, startup performs at most one
  stop/dispose/recreate attempt after a 300 ms pause. A second exact-zero
  startup switches to `t2151` / `VOICE_COMMUNICATION`.
- `VoiceState` records requested profile, active profile, and
  `startupExactZeroPcm` fallback reason. The next explicit cold start restores
  the requested experimental profile.
- Covered by `voice_capture_recovery_gate_test.dart`,
  `voice_device_profile_test.dart`, `voice_state_test.dart`,
  `wear_voice_session_test.dart`, and `voice_recovery_primitives_test.dart`.
- Native UVC device selection, session diagnostics, USB device callbacks, WAV
  capture, and post-authorization Vosk preparation/lazy free-text recognizer
  are implemented. Their T2151 validation and the device matrix remain pending.

### Preliminary audio-source decision (2026-07-27)

- Selected profile: `VOICE_DEVICE_PROFILE=t2151` (`voiceCommunication`).
- Evidence: one cold-start command run per profile on the connected T2151.
- `voiceCommunication` delivered non-zero PCM immediately and dispatched five observed `up`/`down` commands in 425-708 ms from `VAD_START`.
- `voiceRecognition` and `mic` both emitted exact-zero PCM for approximately 5-6 seconds after startup before speech was available.
- This selects the release profile for continued device validation; it does not complete the full scenario matrix in `T2151_TEST_PLAN.md`.

| Area | Status | Changed files | Tests | Remaining hardware validation | Known limitations |
|---|---|---|---|---|---|
| P0 correctness | IN_PROGRESS | `voice_device_profile.dart`, `wear_voice_session.dart`, `wear_module_app.dart`, `wear_voice_control_service.dart` | `voice_device_profile_test.dart`, `wear_voice_control_service_test.dart`, `wear_flow_coordinator_integration_test.dart` | T2151 route/lifecycle behavior | Navigation transaction, capture validation, and retry-owner work remain. |
| Navigation transaction | IN_PROGRESS | `wear_navigation_request.dart`, `wear_flow_controller.dart`, `wear_module_app.dart` | `wear_flow_controller_test.dart`, `wear_flow_coordinator_integration_test.dart` | Phone/glasses convergence on T2151 | Delivery is request-ID guarded and acknowledged by the matching route; optimistic flow/glasses projection is intentionally retained. |
| P1 responsiveness | IN_PROGRESS | `wear_flow_controller.dart` | `wear_flow_controller_test.dart` | Command latency on T2151 | Latest-wins selection channel and rendering isolation remain. |
| Vosk startup | IN_PROGRESS | Existing service | Existing tests only | Startup latency on T2151 | Free-text recognizer is currently eagerly created. |
| P2 UVC recovery | IN_PROGRESS | Existing capture monitor | Existing recovery-gate tests | All USB/UVC claims | Native monitor is source-filtered, not session-correlated. |
| Overlays | IN_PROGRESS | Existing overlay bridge | Existing cubit tests | Secondary engine recreation | Overlay behavior is not yet verified on T2151. |
| Hardware | DEVICE_PENDING | N/A | N/A | Full T2151 matrix | ADB connection is available; validation has not been run. |

### Remediation execution log

#### P0.1 Route, profile, lifecycle, and command correction

- Status: `IN_PROGRESS`.
- Changed files: `lib/modules/wear/domain/service/voice_typing/voice_device_profile.dart`, `lib/modules/wear/services/wear_voice_session.dart`, `lib/modules/wear/presentation/widgets/wear_module_app.dart`, `lib/modules/wear/domain/service/voice_command/wear_voice_control_service.dart`.
- Added/updated tests: `test/voice_device_profile_test.dart`, `test/wear_voice_control_service_test.dart`.
- Commands run: `fvm flutter test test/voice_device_profile_test.dart test/wear_voice_control_service_test.dart`; `fvm flutter test test/wear_flow_coordinator_integration_test.dart`.
- Result: 18 and 29 tests passed, respectively.
- Implemented behavior: GoRouter changes no longer invoke microphone restart; the profile capability is named for native audio-route events; all T2151 profiles disable Bluetooth SCO management; `inactive` does not background the flow; `hidden`/`paused` suspend health checks and arm one resume recovery; partial/final command suppression now requires equal parsed commands.
- Focused review: removed the obsolete session route-policy getter after verifying it had no valid caller.
- Hardware remaining: verify T2151 USB/UVC routing and lifecycle behavior. `manageBluetooth: false` is safe configuration for an expected USB/UVC input but remains `DEVICE_PENDING` until tested.
- Known limitations: no native audio-route event stream exists yet, so the renamed capability is not consumed.

#### P1.1 Command/render decoupling

- Status: `IN_PROGRESS`.
- Changed files: `lib/modules/wear/application/wear_flow_controller.dart`.
- Added test: `test/wear_flow_controller_test.dart` verifies menu down completes while glasses output remains blocked.
- Command run: `fvm flutter test test/wear_flow_controller_test.dart`.
- Result: 56 tests passed.
- Implemented behavior: menu `up`/`down` updates local flow state immediately and sends glasses projection asynchronously.
- Focused review: no follow-up code defect found; full-payload projection is still unbounded, therefore the revisioned latest-wins selection protocol remains `TODO`.
- Hardware remaining: measure command handler and glasses frame latency on T2151.

#### P0.2 Transactional navigation delivery

- `WearNavigationRequest` now carries a monotonically increasing `requestId`.
- Pending navigation remains stored until `WearModuleApp` observes the matching GoRouter route and calls `acknowledgeNavigation`.
- A delivered request ID prevents duplicate dispatch during repeated lifecycle flushes; a delivery error restores eligibility for a later flush.
- Newer requests replace older inactive requests, and stale acknowledgements are rejected.
- The controller continues optimistic flow/glasses projection before route acknowledgement. Attempting strict post-ack projection caused 23 existing controller/integration regressions because screen actions depend on immediate destination state; this is now an explicit contract rather than an implicit race.
- Review: no new correctness finding after the integration test confirmed `controller request -> GoRouter route -> matching ack -> pending clear`.
- Verification: `fvm flutter test test/wear_flow_controller_test.dart test/wear_flow_coordinator_integration_test.dart` passed (88 tests); `git diff --check` passed.

#### P0.3 Health-check ownership

- `WearVoiceSession.ensureHealthy` now joins an existing health check through `VoiceSingleFlight`; concurrent timer/resume/capture-event checks cannot independently trigger sequential recovery decisions.
- Existing restart single-flight remains the sole owner of an actual restart, and scheduled retries are cancelled when a restart begins.
- Review: no new correctness finding. The guard covers concurrent health decisions; start/restart lifecycle ownership and T2151 hardware validation remain in progress.
- Verification: `fvm flutter test test/wear_voice_session_test.dart test/voice_recovery_primitives_test.dart` passed (8 tests); targeted analyze reported only 22 existing `avoid_print` info; `git diff --check` passed.

#### Current verification run

- `fvm flutter pub get`: passed; 53 packages have newer incompatible versions and were not changed.
- `fvm flutter analyze`: completed with 322 existing project info/warnings, primarily `avoid_print`; no compile error was reported. This is not a clean analyzer result.
- `fvm flutter test`: passed, 163 tests.
- `./gradlew :app:compileDebugKotlin`: passed. Gradle reported existing Kotlin-plugin, flat-directory, and deprecation warnings.
- `./tool/build_voice_recovery_apk.sh t2151`: passed; output `build/app/outputs/flutter-apk/app-debug.apk`.
- APK fingerprint: `sha=9d0273daa6312e451e8b3300e5331d47d4023f8b`, `dirty=true`, `patch=30966ef22f2cbb498d02ce4f36fbd707eb1f1b95b1dc06f1f54a92be4e328ed0`, `profile=t2151`.
- `git diff --check`: passed.
- Control-build fingerprint with `dirty=false`: `BLOCKED` because this remediation intentionally leaves uncommitted work and no separate clean checkout was created. The script output did not print a build timestamp, so timestamp presence is `TODO`.

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
| V09 | Retry with backoff | DONE | `wear_voice_session_test.dart` verifies failed startup schedules the configured retry and only its callback initiates the next restart. |
| V10 | Correct app lifecycle handling | DEVICE_PENDING | Only hidden/paused arm the resume restart; widget test passed for paused/resumed, T2151 validation remains. |
| V11 | Safe Vosk pipeline stop | DONE | `voice_recovery_primitives_test.dart` verifies timed-out processing isolation and capture-epoch invalidation before replacement capture work. |
| V12 | Block commands outside ready | DONE | UI suppresses commands during reconnect/unavailable; full test suite passed. |
| V13 | Phone overlay | DONE | Overlay derives from startup/recovery/unavailable state and preserves route; integration tests passed. |
| V14 | Independent glasses overlay | DONE | `wear_flow_coordinator_integration_test.dart` verifies a new fast payload reopens the projection after an older refresh is delayed, preserving only the newest payload. |
| V15 | Restore overlay after Presentation | DEVICE_PENDING | `MainActivity` recreates the wear Presentation after detach, restores its payload, and reapplies the visible overlay; requires secondary-display validation. |
| V16 | Authentication and navigation independence | DONE | Removed `waitForStartup()` from success status pop; integration suite passed. |
| V17 | Native audio diagnostics | DEVICE_PENDING | Flutter now supplies active capture ID/source to native monitoring; inspect source, silencing, format, and routed-device values on T2151. |
| V18 | Audio source/device profile | IN_PROGRESS | Preliminary T2151 A/B selects `t2151`/`voiceCommunication`: immediate non-zero PCM and 425-708 ms command dispatch from `VAD_START`; `voiceRecognition` and `mic` had 5-6 s exact-zero startup PCM. Full scenario matrix remains pending. |
| V19 | Verify microphone foreground service | DEVICE_PENDING | Manifest has microphone permissions and `foregroundServiceType`; validate runtime service behavior on T2151. |
| V20 | State-machine unit tests | DONE | Voice state, startup/health gates, recorder lifecycle, single-flight, production retry ownership, overlay revision, and delayed-Vosk timeout primitives are covered by targeted tests. |
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
