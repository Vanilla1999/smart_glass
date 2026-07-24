# Voice Recovery Code Review Critique

## Verdict

The implementation is not ready to be accepted as complete. The full Flutter suite passes, but the recovery state machine itself is not exercised through production dependencies. Several `DONE` statuses in `IMPLEMENTATION_STATUS.md` must be reopened.

## Remediation

The code changes addressing the findings below are implemented. `IMPLEMENTATION_STATUS.md` records the remaining gaps conservatively: production-path retry and recognizer tests are still required, and all T2151 checks remain device-pending.

- Current-capture readiness, cancellation/silencing checks, retry ownership, and initial cleanup handling were added to `WearVoiceSession`.
- Timed-out recognizer work is isolated from replacement captures in `SpeechRecognitionService`.
- Overlay revisions are process-wide; native overlay replay handles Presentation detachment.
- Native capture monitoring accepts the active profile source and Dart capture ID.

Review scope:

- `docs/voice_recovery/IMPLEMENTATION_STATUS.md`
- `docs/voice_recovery/T2151_TEST_PLAN.md`
- current uncommitted Flutter and Android voice-recovery changes
- unit, widget, and integration-test evidence recorded by the plan

## Findings

### CRITICAL-01: Restart readiness uses a counter from the previous capture

References:

- `lib/modules/wear/services/wear_voice_session.dart:84-95`
- `lib/modules/wear/services/wear_voice_session.dart:150-164`
- `lib/modules/wear/domain/service/voice_typing/audio_stream_service.dart:127-129`
- `lib/modules/wear/services/wear_voice_session.dart:454-458`

`WearVoiceSession` reads `chunksAtStart` before `startListening()` or `restartListening()`. `AudioStreamService.start()` then resets `_chunksReceived` to zero. After an earlier capture has received `N` chunks, readiness requires the new capture to reach `N + 3` chunks within two seconds.

Failure scenario: an old capture has 5,000 chunks, recovery starts, the counter resets to zero, and the startup gate cannot satisfy `chunksReceived - 5000 >= 3`. Recovery times out and enters `unavailable` even though the replacement recorder is producing PCM.

Impact: central startup-after-stop and restart flows are broken after a sufficiently long prior capture.

Affected plan items: V04, V06, V07, V10, V20, V21.

Required action: use a per-capture counter or capture ID measured after the new stream resets its metrics. Add a production-path test that starts two captures and verifies readiness of the second capture.

### HIGH-01: Retry backoff is bypassed and stale retry timers survive recovery

References:

- `lib/modules/wear/services/wear_voice_session.dart:130-187`
- `lib/modules/wear/services/wear_voice_session.dart:289-296`
- `lib/modules/wear/services/wear_voice_session.dart:333-354`
- `lib/modules/wear/presentation/widgets/wear_module_app.dart:410-420`

`restart()` does not cancel an existing `_retryTimer`. The periodic three-second health check also continues while state is `unavailable` and immediately restarts when the recorder is stopped.

Failure scenarios:

- A failed attempt schedules a 10/30/60-second retry, but the health timer retries after at most about three seconds.
- A lifecycle or health recovery succeeds while an old retry remains armed; that timer later hard-restarts the healthy recorder.

Impact: the documented backoff is not respected and one failure can cause duplicate sequential recoveries.

Affected plan items: V08 and V09 must not be `DONE`; V10 is also affected.

Required action: make retry ownership part of the state machine. Cancel scheduled retry when any restart begins or succeeds, and suppress periodic health recovery while `unavailable` has a scheduled retry. Test with a fake clock/timer.

### HIGH-02: Cancelled startup or restart can emit a false `ready`

References:

- `lib/modules/wear/services/wear_voice_session.dart:111-123`
- `lib/modules/wear/services/wear_voice_session.dart:213-250`
- `lib/modules/wear/services/wear_voice_session.dart:96-97`
- `lib/modules/wear/services/wear_voice_session.dart:165-166`

When a generation becomes stale, `_waitForCaptureReady()` exits normally. Both callers then emit `ready` unconditionally. `stop()` invalidates the generation before its queued stop operation executes.

Failure scenario: logout occurs while startup is waiting for PCM. The wait returns because its generation is stale, emits `ready`, and only afterward does the queued stop emit `disabled`.

Impact: commands and overlays can briefly report healthy voice after logout or cancellation.

Affected plan items: V03, V04, V12, V16, V20, V21.

Required action: return an explicit ready/cancelled result or throw an internal cancellation. Never emit `ready` without rechecking generation and `_shouldListen`. Add start-versus-stop and restart-versus-stop race tests.

### HIGH-03: Android silencing can be overwritten by startup `ready`

References:

- `lib/modules/wear/services/wear_voice_session.dart:41-50`
- `lib/modules/wear/services/wear_voice_session.dart:91-97`
- `lib/modules/wear/services/wear_voice_session.dart:160-166`
- `lib/modules/wear/services/wear_voice_session.dart:221-248`

`setCaptureSilenced(true)` emits `suspendedBySystem`, but startup readiness does not check `_captureSilenced`. Three stream events, including zero PCM, can then overwrite the state with `ready` while Android still reports the capture as silenced.

Impact: command gating can reopen while microphone capture is unavailable.

Affected plan items: V03, V06, V12.

Required action: startup/restart readiness must not transition to `ready` while capture is silenced. Cover silencing during startup and during restart.

### HIGH-04: Vosk timeout permits concurrent use of the same recognizer

References:

- `lib/modules/wear/domain/service/voice_typing/speech_recognition_service.dart:293-317`
- `lib/modules/wear/domain/service/voice_typing/speech_recognition_service.dart:373-417`
- `lib/modules/wear/domain/service/voice_typing/speech_recognition_service.dart:419-520`
- `test/voice_recovery_primitives_test.dart:70-90`

After two seconds the code replaces the Dart queue futures, but it does not cancel the old native Vosk operation or recreate the recognizers. A replacement capture can reset and reuse a recognizer while the old `acceptWaveformBytes()` or result call is still running.

Epoch checks suppress stale stream emission, but they do not make native recognizer access safe. Old work can also still execute `_setPartialText()` after the asynchronous recognizer call and overwrite partial state for the new capture.

The current test times out an unrelated `Completer` and validates an integer epoch. It does not exercise `SpeechRecognitionService` or a delayed recognizer.

Impact: overlapping reset/accept calls can hang or corrupt recognition state after recovery.

Affected plan items: V11 and V20 must not be `DONE`; V12 and V21 are also affected.

Required action: do not reuse a recognizer with timed-out work. Recreate or isolate recognizers per capture, and test with a blocking fake recognizer.

### HIGH-05: Overlay revisions reset for every Wear module instance

References:

- `lib/modules/wear/presentation/widgets/wear_module_app.dart:459-475`
- `lib/modules/wear/presentation/widgets/wear_module_app.dart:643-647`
- `lib/features/glasses/presentation/cubit/wear/wear_voice_overlay_cubit.dart:33-52`

`_voiceOverlayRevision` starts at zero for each `WearModuleApp`, while the glasses cubit can survive module recreation and rejects lower revisions.

Failure scenario: the previous session ends at revision 12; reopening the module starts at revision 1, so the glasses runtime ignores all new overlay updates until revision 12 is reached.

Impact: phone overlay can work while the glasses overlay is absent or stale.

Affected plan items: V14 must not be `DONE`; V15 is not only device-pending because implementation work remains.

Required action: use a process-global monotonic revision or include a session/epoch identifier that the receiver compares before revision. Reject equal stale revisions as well. Test sender recreation while retaining the cubit.

### HIGH-06: Native capture monitor is hard-coded to one A/B source and does not identify this recorder

References:

- `android/app/src/main/kotlin/ru/tander/smart_glasses/MainActivity.kt:141-176`
- `lib/modules/wear/domain/service/voice_typing/voice_device_profile.dart:43-63`

Android filters active recordings only by `VOICE_COMMUNICATION`. The `voiceRecognition` and `mic` profiles are therefore invisible to silencing diagnostics. The filter also does not correlate the Android recording configuration with the app's current recorder session.

Impact:

- A/B profiles do not receive equivalent silencing diagnostics.
- Another matching recording can incorrectly suspend or restart the wear session.
- V17 evidence cannot reliably be tied to a specific Dart `captureId`.

Affected plan items: V06, V17, V18.

Required action: pass selected source/session identity to native monitoring or add a minimal native recorder bridge that exposes a stable session identifier.

### HIGH-07: Presentation recreation does not actively restore the cached overlay

References:

- `android/app/src/main/kotlin/ru/tander/smart_glasses/MainActivity.kt:260-328`
- `android/app/src/main/kotlin/ru/tander/smart_glasses/MainActivity.kt:330-388`
- `android/app/src/main/kotlin/ru/tander/smart_glasses/MainActivity.kt:476-489`

The cached overlay is reapplied only after a later `showWearGlasses` navigation or `updateWearGlasses` acknowledgement. There is no restoration hook in Presentation creation, no dismissal/recreation detection, and Activity recreation loses the in-memory cache.

Impact: the explicit T2151 scenario "recreate Presentation while overlay is visible" is not fully implemented. Device testing alone cannot close this item.

Affected plan item: V15 must be `IN_PROGRESS`, not `DEVICE_PENDING`.

Required action: reapply current wear payload and overlay when the Presentation/secondary engine becomes ready, then add a native or bridge-level lifecycle test.

### MEDIUM-01: `VoiceState` is not the single authority claimed by V03

References:

- `lib/modules/wear/presentation/widgets/wear_module_app.dart:335-407`
- `lib/modules/wear/presentation/widgets/wear_module_app.dart:436-456`
- `lib/modules/wear/presentation/widgets/wear_module_app.dart:524-553`

`WearModuleApp` consumes session state but also synthesizes `preparing`, `ready`, `unavailable`, and reconnect states around callbacks and legacy test streams. A completed callback can overwrite a more recent production session state.

Impact: UI state, command gating, and session state can diverge.

Affected plan items: V03 and V12.

Required action: production mode must render only `WearVoiceSession.stateStream`. Keep a single typed test-state injection seam instead of legacy boolean/error adapters and callback-derived states.

### MEDIUM-02: Device profile recovery flags are dead configuration

References:

- `lib/modules/wear/domain/service/voice_typing/voice_device_profile.dart:65-72`
- `lib/modules/wear/presentation/widgets/wear_module_app.dart:582-630`
- `lib/modules/wear/services/wear_voice_session.dart:41-50`

`forceHardRestartOnResume`, `forceHardRestartAfterUnsilence`, and `forceHardRestartOnRouteChange` are defined and tested as values, but production code does not read them.

Impact: the profile advertises recovery behavior that it does not control. T2151 route-change policy is not implemented.

Affected plan item: V18 remains `IN_PROGRESS` plus device validation, not merely `DEVICE_PENDING`.

Required action: either use these flags in lifecycle/route/unsilence decisions or remove them from the profile and documentation.

### MEDIUM-03: Startup cleanup failure prevents automatic retry

References:

- `lib/modules/wear/services/wear_voice_session.dart:98-102`
- `lib/modules/wear/domain/service/voice_typing/speech_recognition_service.dart:284-289`

The startup catch awaits `stopListening()` before `_markUnavailable()`. If cleanup throws, the original failure is masked and no retry timer is installed. The restart path protects cleanup, but initial startup does not.

Impact: an initial recorder failure can leave the session permanently in `preparing` without automatic retry.

Affected plan items: V03 and V09.

Required action: protect cleanup with its own try/catch/finally and always publish unavailable/retry state.

### MEDIUM-04: Ordinary wear updates lost their native timeout

References:

- `android/app/src/main/kotlin/ru/tander/smart_glasses/MainActivity.kt:330-351`
- `android/app/src/main/kotlin/ru/tander/smart_glasses/MainActivity.kt:413-465`

`updateWearGlasses()` forwards through an anonymous `MethodChannel.Result` instead of `BoundedResult`. If the secondary engine does not acknowledge the call, the native result remains pending indefinitely and cannot be superseded through `pendingWearResults`.

Impact: overlay replay introduced a MethodChannel robustness regression.

Affected plan items: V14, V15, V21.

Required action: retain `BoundedResult` while applying the overlay after successful completion.

### MEDIUM-05: Empty stream events count as healthy PCM chunks

References:

- `lib/modules/wear/domain/service/voice_typing/audio_stream_service.dart:152-183`
- `integration_test/audio_capture_test.dart:11-40`

Every stream event increments `_chunksReceived`, including buffers shorter than one PCM16 sample. The device integration test also accepts the first callback without validating byte length or the required three chunks.

Impact: repeated empty buffers can satisfy startup readiness without any PCM samples.

Affected plan items: V04, V05, V20, V21.

Required action: count only valid, non-empty PCM16 buffers and make the integration test require three valid current-capture chunks.

### MEDIUM-06: Build fingerprint cannot identify the reviewed source

References:

- `lib/main.dart:13-16`
- `lib/main.dart:68-78`
- `docs/voice_recovery/IMPLEMENTATION_STATUS.md:62-69`

The APK records baseline SHA `14899f0...`, but all reviewed voice changes are uncommitted relative to that SHA. There is no dirty marker or content hash.

Impact: different uncommitted APKs can produce the same fingerprint, so T2151 evidence cannot be reliably mapped to source.

Affected plan items: V02 and V23.

Required action: build from a committed review SHA or include a dirty marker plus patch/content hash.

## Test Evidence Critique

The new tests validate extracted helpers, not the production state machine:

| Test | What it proves | What it does not prove |
|---|---|---|
| `voice_capture_recovery_gate_test.dart` | Arithmetic of startup and zero-audio gates | Actual recorder reset, capture identity, cancellation, or state transitions |
| `voice_recovery_primitives_test.dart` | Isolated delay table, callback order, single-flight helper, and integer epoch | `WearVoiceSession` retries, real recorder lifecycle, delayed recognizer safety, or production wiring |
| `voice_state_test.dart` | `acceptsCommands` getter | UI stream ordering or command suppression in every phase |
| `wear_flow_coordinator_integration_test.dart` | Widget overlays through injected callbacks/legacy streams | Recovery driven by `WearVoiceSession.stateStream` and real failure/retry flow |
| `audio_capture_test.dart` | At least one recorder callback | Three valid PCM chunks, second capture readiness, or recovery |

No test invokes the complete production sequence:

`PCM or failure -> WearVoiceSession -> VoiceState -> command gate -> phone overlay -> MethodChannel -> glasses overlay`.

The singleton `WearVoiceSession` and direct `WearDependencies.I` access prevent deterministic fake-recorder/fake-Vosk state-machine tests. Extracting helpers does not replace a test seam at the orchestration boundary.

## Required Status Corrections

| ID | Current | Review status | Reason |
|---|---|---|---|
| V03 | DONE | IN_PROGRESS | Multiple state authorities and false-ready races remain. |
| V04 | DONE | IN_PROGRESS | Restart chunk baseline is broken; only helper arithmetic is tested. |
| V05 | DONE | IN_PROGRESS | PCM tracking and `ensureHealthy()` production flow are untested. |
| V06 | DEVICE_PENDING | IN_PROGRESS + DEVICE_PENDING | Silencing race and native source/ownership gaps require code changes. |
| V07 | DONE | IN_PROGRESS | Callback-order helper does not prove production recreation/restart. |
| V08 | DONE | IN_PROGRESS | Stale retry timer can cause duplicate sequential recovery. |
| V09 | DONE | IN_PROGRESS | Backoff is bypassed and timer lifecycle is untested. |
| V11 | DONE | IN_PROGRESS | Timed-out Vosk work can overlap the replacement capture. |
| V12 | DONE | IN_PROGRESS | False `ready`, silencing race, and incomplete phase coverage remain. |
| V13 | DONE | IN_PROGRESS | UI is covered through adapters, not production recovery state. |
| V14 | DONE | IN_PROGRESS | Revision resets across module instances; version contract is not enforced. |
| V15 | DEVICE_PENDING | IN_PROGRESS + DEVICE_PENDING | Presentation restoration hook is missing. |
| V16 | DONE | IN_PROGRESS | Cancellation/silencing races remain and targeted navigation test is absent. |
| V17 | DEVICE_PENDING | IN_PROGRESS + DEVICE_PENDING | Native recording ownership is not correlated with capture ID. |
| V18 | DEVICE_PENDING | IN_PROGRESS + DEVICE_PENDING | Recovery policy flags are unused; A/B native monitoring is source-incomplete. |
| V20 | DONE | IN_PROGRESS | Helpers are tested, not the state machine. |
| V21 | DONE | IN_PROGRESS | `fvm flutter test` is green, but no full recovery integration test exists. |
| V23 | DONE | IN_PROGRESS | Status evidence and APK provenance are inaccurate. |

V10 and V19 correctly remain device-dependent, but V10 must be retested after retry and restart fixes.

## Required Fix Order

1. Fix the per-capture readiness baseline and cancellation semantics.
2. Introduce injectable speech/audio dependencies, clock, and timer scheduling for `WearVoiceSession`.
3. Fix retry ownership and add full failure/recovery/stop race tests.
4. Make delayed Vosk shutdown safe by isolating or recreating recognizers.
5. Make one `VoiceState` source authoritative in production UI.
6. Make overlay ordering monotonic across module/engine recreation and restore overlay on Presentation readiness.
7. Correlate native audio diagnostics with selected profile and recorder identity.
8. Rebuild from an identifiable source revision, rerun automated checks, then execute the physical T2151 plan.

## Acceptance Gate

Do not mark the implementation complete until all of the following are true:

- Two consecutive captures both become ready after exactly three valid current-capture PCM chunks.
- Stop/logout during startup or restart never emits `ready` afterward.
- One failure produces one scheduled retry, and successful recovery cancels all older retries.
- A delayed old Vosk operation cannot overlap or mutate a new recognizer/capture.
- Every non-ready phase blocks commands, final phrases, partial phrases, and system back.
- Recreating `WearModuleApp`, Presentation, and the secondary engine preserves correct overlay ordering.
- Native diagnostics identify the selected profile and the app's actual recorder session.
- The APK fingerprint uniquely identifies the reviewed source.
- All automated tests pass and every remaining T2151 item has recorded device evidence.
