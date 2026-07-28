# Native UAC4 Voice Migration Plan

## Document Status

- Status: `PLANNED`
- Target branch: `feature/native-uac4-voice`
- Baseline branch: `main`
- Baseline commit: `a5fe754105c9b702e4d5b18db5fd8b2571b7c827`
- Created: `2026-07-28`
- Reference demo: `/home/viadmin/Загрузки/Telegram Desktop/FourMicDemo(1)/FourMicDemo`
- Hardware validation status: `DEVICE_PENDING`

This document is the execution checklist and source of truth for replacing all
Flutter `record`-based capture with the native four-microphone UAC4 path.

## Agent Operating Rules

- Execute phases in order unless a phase explicitly says it can run in parallel.
- Do not mark a checkbox complete without recording evidence in the Implementation Log.
- Use `DEVICE_PENDING` for every statement that was not verified on a physical T2151.
- Stop on a missing vendor prerequisite. Do not invent service behavior, return codes,
  channel order, credentials, or licensing rules.
- Never copy the demo application key, secret, or test UDID into project code.
- Never add a `record`, direct `AudioRecord`, direct `MediaRecorder`, or legacy microphone
  fallback.
- Keep the PCM contract at the Vosk boundary unchanged: mono PCM16 LE at 16 kHz.
- Do not pass four-channel PCM through Flutter platform channels or into Vosk.
- Do not process PCM on the Android main thread.
- Do not register the native voice bridge on the secondary glasses Flutter engine.
- Do not modify scanner, printing, availability, navigation, or glasses projection
  behavior unless a directly related test proves it is required.
- Run focused tests after each phase and the full verification suite before completion.
- If implementation changes a locked decision below, update this document first and
  record the reason in the Implementation Log.

Checkbox meanings:

- `[ ]` not started
- `[x]` completed with evidence
- `DEVICE_PENDING` implemented but not verified on target hardware
- `BLOCKED` cannot proceed without an external dependency or decision

## Goal

Replace every use of the Flutter `record` package with one native Android voice
capture owner that:

1. Binds to `com.xcheng.uac4client.Uac4ClientService`.
2. Receives synchronized 16 kHz, four-channel, PCM16 little-endian audio over AIDL.
3. Processes all four microphone channels through the vendor Unisound SSP library.
4. Publishes only processed 16 kHz mono PCM16 to Dart.
5. Feeds the existing VAD and Vosk recognition pipeline without changing their PCM
   timing assumptions.
6. Fails explicitly on unsupported firmware instead of falling back to `record`.
7. Provides deterministic lifecycle, recovery, diagnostics, and test seams.

## Non-Goals

- Supporting firmware that does not provide `Uac4ClientService` for voice capture.
- Implementing a direct Android `AudioRecord` fallback.
- Implementing four independent recorder instances.
- Sending raw four-channel audio to Dart.
- Replacing Vosk or changing command grammar.
- Reimplementing the proprietary SSP algorithm.
- Changing the physical microphone array model or channel mapping without vendor data.
- Preserving voice memo output at 44.1 kHz. The migrated voice memo format is processed
  mono PCM16 at 16 kHz unless a separate business requirement is approved.

## Locked Architecture Decisions

### Capture source

- Production capture uses only the external UAC4 AIDL service.
- Service package: `com.xcheng.uac4client`.
- Service class: `com.xcheng.uac4client.Uac4ClientService`.
- Missing service means `unsupportedFirmware` and voice controls remain unavailable.
- A service that exists but fails activation, binding, initialization, or startup is
  an explicit error. It must not trigger a hidden legacy fallback.

### Provisional vendor PCM contract

The AIDL signature contains only `byte[]`; it does not prove the audio format. The
following input contract is inferred from FourMicDemo and remains `BLOCKED` until the
vendor confirms every field in Phase 0.

Raw service input:

```text
sample rate: 16000 Hz
channels: 4
encoding: signed PCM16
byte order: little-endian
layout: interleaved channel samples
bytes per sample frame: 8
SSP frame duration: 16 ms
SSP input bytes per frame: 2048
```

Flutter/Vosk output:

```text
sample rate: 16000 Hz
channels: 1
encoding: signed PCM16
byte order: little-endian
SSP output bytes per 16 ms: 512
```

- SSP processing happens in Kotlin before Flutter delivery.
- The Dart stream receives arbitrary chunk boundaries but always complete PCM16 samples.
- The first implementation batches at most two SSP output frames per Flutter event:
  1024 bytes / 32 ms maximum batching latency.
- The existing VAD may continue accumulating 640-byte, 20 ms frames.
- The existing Vosk recognizers remain configured at 16 kHz.
- Initial post-SSP gain is `1.0`. Gain may be tuned only from measured clipping, RMS,
  and recognition evidence on the target device.

### Ownership

- There is one application-scoped native capture manager and exactly one primary-isolate
  Dart bridge.
- Only one logical owner may hold capture at a time.
- Required owner identities: `wearRecognition`, `legacyRecognition`, `voiceMemo`.
- A second owner receives `CAPTURE_BUSY`; it must not start another microphone stream.
- Native `start` creates and returns an opaque monotonic `leaseId`; Dart never chooses it.
- Stop requires the matching `{owner, leaseId}` pair. Stale or mismatched stop requests are
  rejected without affecting the current owner.
- Plugin detachment stops the current lease and detaches channels, but does not permanently
  dispose the application-scoped manager. A recreated primary engine may attach again.
- Fatal Binder failure invalidates the lease. Process-terminal shutdown exists only for
  tests or actual application-process teardown.

### Transport

- Control uses a dedicated `MethodChannel`.
- PCM uses a dedicated acknowledged `BasicMessageChannel<ByteData>` with `BinaryCodec`.
- State and diagnostic events use a separate `EventChannel` carrying maps.
- Required channel names:

```text
ru.tander.smart_glasses/native_voice/control
ru.tander.smart_glasses/native_voice/pcm
ru.tander.smart_glasses/native_voice/events
```

- Every PCM message atomically carries protocol version, lease ID, sequence, monotonic
  timestamp, and mono PCM bytes.
- Native sends at most one unacknowledged PCM message. Dart replies only after accepting or
  rejecting that message for the current lease. This bounds cross-engine delivery.
- A missing or timed-out acknowledgement is a typed bridge failure; native does not build
  an unbounded channel backlog.

- The bridge is registered only against the primary Flutter engine passed to
  `MainActivity.configureFlutterEngine`.
- The glasses engine continues to use `glasses_channel` and receives no PCM.

## Evidence From FourMicDemo

- `IUac4AppService.aidl` defines `initUac4`, `startUac4Mic`, `stopUac4Mic`, and
  `deinitUac4`.
- `IUac4AppCallback.aidl` defines a one-way `onAudioData(byte[])` callback.
- `Uac4ServiceClient.kt` binds explicitly to the package and service class above.
- `MainViewModel.kt` defines a 2048-byte input frame for 16 ms of four-channel audio.
- `SspManager.processData` returns a nominal 512-byte mono frame.
- `glasses4mic-ssp-1.0.2.aar` contains the four-microphone SSP native library,
  `FDMicArrayConfig.ini`, and `model4.bin`.
- The SSP native binary is available only for `arm64-v8a`.
- The demo performs vendor activation before `SspManager.init`.
- The demo manifest does not request microphone permission, indicating that the external
  service owns hardware capture and its permissions.

Do not copy these demo defects:

- Audio processing on the Android main thread.
- An unbounded one-way Binder callback backlog.
- Dropping 1-7 trailing bytes when a callback is not aligned to an 8-byte sample frame.
- Shifting the complete accumulation buffer for every 16 ms frame.
- Repeated frame allocations in the hot path.
- In-memory accumulation of an entire diagnostic recording.
- Manual lifecycle ordering without a state machine.
- Hard-coded test credentials and UDID.

## Current Project Impact

Current `record` owners that must be migrated:

- `lib/modules/wear/domain/service/voice_typing/audio_stream_service.dart`
- `lib/modules/wear/domain/service/voice_typing/voice_device_profile.dart`
- `lib/features/voice/presentation/cubit/voice_cubit.dart`
- `lib/features/voice_memo/presentation/cubit/voice_memo_cubit.dart`
- Tests importing `package:record/record.dart`
- `pubspec.yaml` and `pubspec.lock`
- `com.llfbandit.record.service.AudioRecordingService` in AndroidManifest.xml
- AudioRecord-specific monitoring in `MainActivity.kt`
- AudioRecord-specific events in `MethodChannelService`
- AudioRecord-specific recovery assumptions in `WearVoiceSession`

Current downstream code that should remain conceptually unchanged:

- `SpeechRecognitionService` VAD and dual Vosk lanes.
- `SpeechSegmenter` 16 kHz mono timing.
- Voice command grammar and arbitration.
- Wear flow command routing.
- Glasses voice-state projection.

## Target Components

### Android

Suggested files:

```text
android/app/src/main/aidl/com/xcheng/uac4client/IUac4AppCallback.aidl
android/app/src/main/aidl/com/xcheng/uac4client/IUac4AppService.aidl
android/app/src/main/kotlin/ru/tander/smart_glasses/voice/NativeVoicePlugin.kt
android/app/src/main/kotlin/ru/tander/smart_glasses/voice/NativeVoiceCaptureManager.kt
android/app/src/main/kotlin/ru/tander/smart_glasses/voice/Uac4ServiceClient.kt
android/app/src/main/kotlin/ru/tander/smart_glasses/voice/SspFrameProcessor.kt
android/app/src/main/kotlin/ru/tander/smart_glasses/voice/PcmRingBuffer.kt
android/app/src/main/kotlin/ru/tander/smart_glasses/voice/VoiceCaptureState.kt
android/app/src/main/kotlin/ru/tander/smart_glasses/voice/VoiceCaptureError.kt
android/app/libs/glasses4mic-ssp-1.0.2.aar
android/app/libs/unisound-active-release-v1.0.2-20260316.aar
```

Responsibilities:

- `NativeVoicePlugin`: channel registration and Flutter engine lifecycle only.
- `NativeVoiceCaptureManager`: state machine, single owner, activation, bind/start/stop,
  watchdog, diagnostics, and cleanup.
- `Uac4ServiceClient`: AIDL binding, Binder death handling, and typed service calls.
- `SspFrameProcessor`: worker-thread framing and SSP calls.
- `PcmRingBuffer`: allocation-bounded accumulation that applies the vendor-confirmed
  contiguous-stream or independent-frame policy.
- `VoiceCaptureState`: exhaustive native lifecycle state.
- `VoiceCaptureError`: stable error codes and safe details for Dart.

### Dart

Suggested files:

```text
lib/core/voice/native_voice_capture_port.dart
lib/core/voice/native_voice_capture_models.dart
lib/core/voice/flutter_native_voice_capture_adapter.dart
```

Responsibilities:

- `native_voice_capture_port.dart` and models are pure Dart and import no Flutter APIs.
- `flutter_native_voice_capture_adapter.dart` owns Flutter channels and implements the port.
- Expose typed `NativePcmPacket` objects containing lease ID, sequence, monotonic timestamp,
  and normalized mono PCM.
- Expose typed state, diagnostics, and fatal errors.
- Serialize `prepare`, `start`, `stop`, and `detach` calls.
- Admit packets through one asynchronous consumer callback, not an unbounded
  `StreamController`. Return native acknowledgement only after that packet enters the
  consumer's explicitly bounded queue.
- Reject stale PCM from previous capture epochs.
- Provide a fakeable Dart interface for unit tests without importing Flutter services into
  the wear domain layer.
- The root `DependenciesContainer` creates the only adapter and injects its port into wear,
  legacy recognition, and voice memo. Remove all implicit audio-source constructors.

Root lifecycle is explicit:

1. Convert `AppScope` to a `StatefulWidget`; its state is the primary-isolate lifecycle
   owner and invokes idempotent `DependenciesContainer.dispose()` from `dispose` using
   `unawaited` with error logging.
2. `DependenciesContainer.dispose()` first blocks new capture leases.
3. Stop `WearVoiceSession`, then close `VoiceCubit` and `VoiceMemoCubit`; each must await
   release of its matching lease.
4. Dispose Vosk recognizers/models and drain bounded recognition or memo queues.
5. Detach the Flutter native voice adapter and remove channel handlers.
6. Close unrelated cubits last. Native plugin detachment remains a best-effort safety net
   if Dart teardown did not run.

The secondary `glassesMain` isolate never creates, owns, or disposes this adapter.

## Native State Machine

Required states:

```text
idle
checkingCapabilities
unsupportedFirmware
activating
activated
binding
bound
initializing
initialized
starting
streaming
stopping
deinitializing
unbinding
error
terminalAbandoned
disposed
```

Allowed primary transition:

```text
idle
→ checkingCapabilities
→ activating
→ activated
→ binding
→ bound
→ initializing
→ initialized
→ starting
→ streaming
```

Normal stop transition:

```text
streaming
→ stopping
→ initialized
→ deinitializing
→ bound
→ unbinding
→ activated
```

Rules:

- Every public operation is serialized on one control executor.
- Duplicate `prepare` and `start` calls join the in-flight operation.
- Every asynchronous callback and Binder completion carries an operation generation. Late
  activation/bind results are cleaned up and cannot revive a timed-out generation.
- Synchronous Binder calls run away from the control executor. A timeout cannot cancel a
  blocked Binder transaction; it therefore makes capture terminally unavailable for the
  current process after best-effort cleanup. Do not start another capture on a thread
  abandoned inside a vendor call.
- `stop` is idempotent for the matching lease and has a bounded wait.
- Plugin `detach` attempts stop, deinit, unbind, worker shutdown, and SSP release but leaves
  the application manager attachable by a recreated primary engine.
- Binder death invalidates the capture epoch and emits a fatal state event.
- PCM callbacks are accepted only for the current capture epoch and `streaming` state.
- A late callback after stop is discarded and counted.
- Accepted result codes are defined separately for each vendor operation after Phase 0
  documentation. No generic `zero means success` rule is allowed before that evidence.
- Undocumented result codes become typed errors containing operation and exact code.
- SSP release follows a strict barrier: invalidate lease, reject callbacks, stop UAC4,
  clear queued frames, await the in-flight SSP call, then deinit, unbind, and release SSP.
- A hung SSP call is terminal for the process and must never race `SspManager.release`.
- Normal detach reaches a reusable idle/activated state and proves all resources released.
  Binder or SSP hangs enter `terminalAbandoned`: re-attachment may restore UI channels but
  every capture operation is rejected until process restart. Resources blocked inside
  vendor code are reported as abandoned, not falsely reported as released.

## Channel API Contract

Required control methods:

```text
getCapabilities
requestClientRecordAudioPermission
prepare
start
stop
getDiagnostics
detach
```

`getCapabilities` result fields:

```text
serviceAvailable: bool
servicePackage: String
serviceClass: String
abi: String
sampleRate: int
inputChannels: int
outputChannels: int
sspFrameBytes: int
permissionOwner: externalService | client
clientRecordAudioPermissionRequired: bool
clientRecordAudioPermissionGranted: bool
clientRecordAudioPermissionCanRequest: bool
```

If `permissionOwner=client`, the native plugin requests `RECORD_AUDIO` through
`requestClientRecordAudioPermission` using the primary Activity and returns the final
granted/denied status. Dart `permission_handler` must not independently request microphone
permission for voice capture. If `permissionOwner=externalService`, no client microphone
prompt is shown.

`start` arguments:

```text
owner: wearRecognition | legacyRecognition | voiceMemo
diagnosticsEnabled: bool
```

`start` result:

```text
leaseId: int64 generated by native
captureRevision: int64
```

`stop` arguments:

```text
owner: wearRecognition | legacyRecognition | voiceMemo
leaseId: int64
```

PCM binary packet, big-endian fixed header followed by payload:

```text
offset 0:  uint32 protocolVersion
offset 4:  uint32 headerBytes
offset 8:  int64 leaseId
offset 16: int64 sequence
offset 24: int64 elapsedRealtimeNanos
offset 32: mono PCM16 LE payload at 16000 Hz
```

PCM acknowledgement contains protocol version, lease ID, sequence, and one status:
`accepted`, `staleLease`, `invalidPacket`, `consumerUnavailable`, or `backpressure`.

Acknowledgement is a 24-byte big-endian packet:

```text
offset 0:  uint32 protocolVersion
offset 4:  uint32 statusCode
offset 8:  int64 leaseId
offset 16: int64 sequence
```

Status encoding is stable: `0=accepted`, `1=staleLease`, `2=invalidPacket`,
`3=consumerUnavailable`, `4=backpressure`.

State event fields:

```text
state: String
leaseId: int?
owner: String?
revision: int
timestampMs: int
reason: String?
errorCode: String?
vendorOperation: String?
vendorCode: int?
```

Required stable errors:

```text
UNSUPPORTED_FIRMWARE
ACTIVATION_FAILED
ACTIVATION_TIMEOUT
SSP_INIT_FAILED
SSP_PROCESS_FAILED
SSP_RELEASE_FAILED
SERVICE_BIND_FAILED
SERVICE_BIND_TIMEOUT
SERVICE_DISCONNECTED
BINDER_DIED
UAC4_INIT_FAILED
UAC4_INIT_TIMEOUT
UAC4_START_FAILED
UAC4_START_TIMEOUT
UAC4_STOP_FAILED
UAC4_STOP_TIMEOUT
UAC4_DEINIT_FAILED
UAC4_DEINIT_TIMEOUT
CAPTURE_BUSY
STALE_LEASE
OWNER_MISMATCH
PCM_TIMEOUT
PCM_QUEUE_OVERRUN
PCM_ACK_TIMEOUT
INVALID_PCM_FRAME
INVALID_SSP_OUTPUT
RECOGNITION_BACKLOG
DISPOSED
```

Each error definition includes severity (`diagnostic`, `recoverable`, `terminal`) and the
required `WearVoiceSession` action. Watchdogs use a monotonic injectable clock. Initial
values to validate on hardware are: first callback 15 seconds, streaming callback gap
500 ms, and PCM acknowledgement 500 ms.

Stop outcomes are exact:

- Active matching `{owner, leaseId}`: stop and return `stopped=true`.
- Most recently completed matching lease: idempotent success with `stopped=false`.
- Older or unknown lease: `STALE_LEASE` without touching current capture.
- Matching lease ID with wrong owner: `OWNER_MISMATCH` without touching current capture.
- No active lease and no matching completed lease: `STALE_LEASE`.

Error policy:

| Error | Severity | Session action |
|---|---|---|
| `UNSUPPORTED_FIRMWARE` | terminal | Disable voice; no retry |
| `ACTIVATION_FAILED` | terminal | Disable voice; require explicit app relaunch after cause is fixed |
| `ACTIVATION_TIMEOUT` | terminal | Best-effort cleanup; require process restart |
| `SSP_INIT_FAILED` | terminal | Disable voice; no retry |
| `SSP_PROCESS_FAILED` | terminal | Stop lease; require process restart |
| `SSP_RELEASE_FAILED` | terminal | Report leaked vendor state; require process restart |
| `SERVICE_BIND_FAILED` | recoverable | One full prepare/start retry, then unavailable |
| `SERVICE_BIND_TIMEOUT` | recoverable | Cancel generation; one full retry, then unavailable |
| `SERVICE_DISCONNECTED` | recoverable | One full rebind/start retry, then unavailable |
| `BINDER_DIED` | recoverable | One full rebind/start retry, then unavailable |
| `UAC4_INIT_FAILED` | recoverable | One full prepare/start retry, then unavailable |
| `UAC4_INIT_TIMEOUT` | terminal | Best-effort cleanup; require process restart |
| `UAC4_START_FAILED` | recoverable | One full prepare/start retry, then unavailable |
| `UAC4_START_TIMEOUT` | terminal | Best-effort cleanup; require process restart |
| `UAC4_STOP_FAILED` | terminal | Invalidate lease; best-effort deinit; require process restart |
| `UAC4_STOP_TIMEOUT` | terminal | Invalidate lease; require process restart |
| `UAC4_DEINIT_FAILED` | terminal | Unbind best effort; require process restart |
| `UAC4_DEINIT_TIMEOUT` | terminal | Unbind best effort; require process restart |
| `CAPTURE_BUSY` | diagnostic | Keep current owner; reject requester |
| `STALE_LEASE` | diagnostic | Reject request; keep current owner |
| `OWNER_MISMATCH` | diagnostic | Reject request; keep current owner |
| `PCM_TIMEOUT` | recoverable | One full restart, then unavailable |
| `PCM_QUEUE_OVERRUN` | recoverable | Stop current lease; one full restart, then unavailable |
| `PCM_ACK_TIMEOUT` | terminal | Stop best effort; detach bridge; require engine/app restart |
| `INVALID_PCM_FRAME` | terminal | Stop lease; report vendor contract mismatch |
| `INVALID_SSP_OUTPUT` | terminal | Stop lease; require process restart |
| `RECOGNITION_BACKLOG` | recoverable | Stop current lease; one full restart, then unavailable |
| `DISPOSED` | terminal | Reject operation; no retry in current manager instance |

The single retry budget is shared across all recoverable native/capture errors and resets
only after 60 seconds of healthy streaming with non-zero processed PCM.

## Processing And Backpressure Contract

- AIDL callback work is limited to capture-epoch validation and bounded queue insertion.
- DSP runs on one dedicated high-priority worker thread, never the main thread.
- Queue capacity is eight 16 ms input frames, equal to 128 ms.
- Queue overflow drops the oldest complete frame, increments `droppedInputFrames`, and
  emits a throttled `PCM_QUEUE_OVERRUN` diagnostic.
- The implementation must not allow queue growth beyond the configured capacity.
- If Phase 0 confirms one contiguous byte stream, the ring buffer preserves callback
  remainders across calls. If each callback is independently framed, a non-aligned callback
  is rejected and the frame accumulator is reset according to the vendor contract.
- Only complete 2048-byte SSP input frames are processed.
- Phase 0 must confirm the SSP return contract. If it guarantees fixed-rate output, require
  exactly 512 bytes; otherwise preserve and account for the documented sample count.
- Two 512-byte SSP outputs are batched into one 1024-byte Flutter PCM event.
- Every complete final SSP frame is delivered and acknowledged before normal stop completes.
- At most one PCM message is unacknowledged across the engine boundary. No EventChannel is
  used for PCM because it cannot provide end-to-end backpressure.
- PCM counters are monotonic within a capture epoch.

Required native metrics:

```text
callbacksReceived
inputBytesReceived
inputFramesProcessed
outputBytesProduced
pcmEventsDelivered
droppedInputFrames
droppedOutputEvents
lateCallbacks
invalidFrames
lastCallbackAtMs
lastOutputAtMs
queueDepth
maxQueueDepth
perChannelRms[4]
perChannelPeak[4]
processedMonoRms
processedMonoPeak
```

Per-channel metrics show whether four channel slots contain signal; isolated-stimulus and
non-identical-stream hardware checks are still required to detect duplicated or cross-wired
channels. Metrics are diagnostics only and must not expose raw audio outside app-private
storage.

## Implementation Phases

### Phase 0: Vendor And Firmware Prerequisites

- [ ] Confirm `com.xcheng.uac4client` is installed on the target T2151.
- [ ] Confirm `com.xcheng.uac4client.Uac4ClientService` is enabled and bindable.
- [ ] Record package version, firmware fingerprint, ABI, and Android SDK level.
- [ ] Obtain the production Unisound app key and secret through an approved secret path.
- [ ] Obtain the production UDID derivation rule.
- [ ] Confirm whether activation requires network access on first and subsequent starts.
- [ ] Confirm redistribution rights for both vendor AAR files and bundled models.
- [ ] Obtain a vendor/security decision on embedding activation credentials in a client APK;
  Gradle properties prevent Git leakage but do not prevent APK extraction.
- [ ] Obtain documented meanings for all UAC4 service return codes.
- [ ] Obtain authoritative input format: sample rate, signedness, byte order, channel count,
  interleave layout, callback continuity, legal callback lengths, and whether one sample
  frame may be split across callbacks.
- [ ] Obtain the exact SSP return-length and error-code contract.
- [ ] Confirm four-channel ordering and physical microphone positions.
- [ ] Confirm `model4.bin` and `FDMicArrayConfig.ini` match production glasses.
- [ ] Ask the vendor to confirm the apparent native library SONAME collision between the
  activation and SSP AARs.
- [ ] Save a successful FourMicDemo before/after WAV pair from the same physical device.

Exit criterion: all vendor inputs needed for deterministic integration are available.
If credentials, service access, or channel mapping is missing, mark this phase `BLOCKED`.

### Phase 1: Android Build Integration

- [ ] Copy the two AIDL interfaces without changing package or method signatures.
- [ ] Add the two approved AARs under `android/app/libs`.
- [ ] Enable `aidl = true` in `android/app/build.gradle.kts`.
- [ ] Add explicit local AAR dependencies instead of a broad unrelated file tree.
- [ ] Add package visibility for `com.xcheng.uac4client` if capability detection requires it.
- [ ] Configure production credentials from CI/local Gradle properties, not source files.
- [ ] Make missing release credentials fail the release build with a clear message.
- [ ] Keep debug builds possible with an explicitly supplied approved test credential set.
- [ ] Confirm merged minimum SDK remains compatible with project devices.
- [ ] Make this voice build explicitly `arm64-v8a` through Gradle ABI filters and release
  with `--target-platform android-arm64`; do not load vendor classes on another ABI.
- [ ] Confirm the APK packages `arm64-v8a/libais-lite-Ual.so` exactly once.
- [ ] Confirm R8/proguard rules preserve AIDL stubs and vendor SDK entry points.
- [ ] Run Android dependency and manifest reports and inspect them for duplicate native libs.

Verification:

```bash
fvm flutter pub get
./android/gradlew -p android :app:dependencies
./android/gradlew -p android :app:processDebugMainManifest
./android/gradlew -p android :app:compileDebugKotlin
unzip -l build/app/outputs/flutter-apk/app-release.apk
```

Exit criterion: Android compilation succeeds with AIDL and vendor AARs before runtime code
is added.

### Phase 2: Native UAC4 Lifecycle

- [ ] Implement explicit service capability detection.
- [ ] Implement `Uac4ServiceClient` with explicit component binding.
- [ ] Register `IBinder.DeathRecipient` and handle Binder death once per revision.
- [ ] Implement typed wrappers for all four vendor calls.
- [ ] Implement idempotent unbind that handles never-bound and already-disconnected cases.
- [ ] Implement production activation without copying demo credentials.
- [ ] Make activation single-flight and cache only a confirmed successful result.
- [ ] Initialize SSP only after successful activation.
- [ ] Implement the complete state machine and validate every transition.
- [ ] Implement a single logical capture owner.
- [ ] Add operation timeouts for activation, bind, init, start, stop, deinit, and unbind.
- [ ] Make plugin `detach` release active capture/service/thread/SSP resources without making
  the application manager permanently unusable after primary-engine recreation.
- [ ] Ensure no UI or Activity reference is retained after engine detachment.
- [ ] Distinguish normal reusable detach from `terminalAbandoned`; reject re-attached capture
  until process restart after a hung Binder or SSP call.

Exit criterion: native lifecycle tests prove valid ordering, idempotency, timeout handling,
Binder death cleanup, and single-owner enforcement.

### Phase 3: Four-Channel SSP Processing

- [ ] Implement an allocation-bounded PCM ring buffer.
- [ ] Implement the Phase 0 framing contract: preserve 1-7 byte remainders only for a
  confirmed contiguous stream; otherwise reject/reset malformed independent callbacks.
- [ ] Validate input PCM sample alignment without silently shifting channel order.
- [ ] Process exactly 2048 input bytes per SSP call.
- [ ] Validate every SSP output length.
- [ ] Batch no more than two SSP outputs before Flutter delivery.
- [ ] Add the eight-frame bounded input queue.
- [ ] Permit exactly one unacknowledged PCM BasicMessageChannel packet.
- [ ] Add a 500 ms acknowledgement timeout and terminal bridge error.
- [ ] Reuse hot-path buffers and avoid per-frame list creation.
- [ ] Calculate RMS and peak separately for all four channels before SSP.
- [ ] Calculate processed mono RMS, peak, and clipping ratio after SSP.
- [ ] Reset all buffers and metrics on a new capture epoch.
- [ ] Reject callbacks from old capture epochs.
- [ ] Add a test-only SSP adapter so unit tests do not require the native library.
- [ ] Add optional startup WAV diagnostics capped at 10 seconds per stream: at most
  1,280,000 raw PCM bytes and 320,000 processed PCM bytes, excluding WAV headers.
- [ ] Write diagnostic WAV data incrementally to app-private cache, never fully in memory.
- [ ] Enable raw diagnostics only in debug or an explicitly approved diagnostic build.
- [ ] Retain at most one raw/processed pair, delete files older than 24 hours on startup,
  and never commit diagnostic audio or device identifiers.

Exit criterion: deterministic tests cover fragmented callbacks, multiple frames per callback,
queue overflow, stale callbacks, invalid SSP output, and all four channel metrics.

### Phase 4: Flutter Native Voice Bridge

- [ ] Implement `NativeVoicePlugin` outside `MainActivity`.
- [ ] Register the plugin only on the primary Flutter engine.
- [ ] Implement all control methods with typed success and error responses.
- [ ] Implement acknowledged mono PCM BasicMessageChannel delivery using the fixed binary
  packet and acknowledgement contracts.
- [ ] Implement state/diagnostic EventChannel delivery.
- [ ] Emit a typed terminal state on Binder death or unrecoverable native failure.
- [ ] Include native lease ID and revision in state events.
- [ ] Ensure late state events cannot revive a stopped Dart capture.
- [ ] Require explicit matching lease stop; channel detachment must not stop a newer lease.
- [ ] Add the pure Dart capture port and Flutter adapter defined above.
- [ ] Construct exactly one adapter in `DependenciesContainer`, inject it into
  `WearDependencies`, `VoiceCubit`, and `VoiceMemoCubit`, and define root disposal.
- [ ] Remove implicit `AudioStreamService` construction from `SpeechRecognitionService` and
  `VoiceTypingService`.
- [ ] Validate PCM byte count is even before publishing to consumers.
- [ ] Reject and acknowledge PCM if native state is not `streaming` or lease ID is stale.
- [ ] Acknowledge `accepted` only after bounded consumer admission, never immediately after
  Dart callback or stream publication.
- [ ] Test primary Flutter engine detach/reattach without Android process restart.

Exit criterion: a fake native bridge can start, stream mono chunks, stop, restart, emit errors,
and reject stale capture data in Dart tests.

### Phase 5: Replace Wear Audio Capture

- [ ] Inject the native PCM source into `AudioStreamService`.
- [ ] Remove `AudioRecorder`, factory, input-device selection, and `RecordConfig` code.
- [ ] Retain one place for PCM metrics, startup readiness, callbacks, and optional gain.
- [ ] Set initial post-SSP gain to `1.0`.
- [ ] Keep raw callback semantics as post-SSP/pre-gain mono PCM.
- [ ] Keep boosted callback semantics as post-SSP/post-gain mono PCM.
- [ ] Preserve lease ID, packet sequence, monotonic timestamp, non-zero timestamp, and
  zero-audio tracking.
- [ ] Replace recorder diagnostics with native UAC4 diagnostics.
- [ ] Replace `recreateRecorder` with a native capture restart operation.
- [ ] Remove USB label selection and expected `InputDevice` checks.
- [ ] Simplify `VoiceDeviceProfile` so it contains recognition thresholds and UAC4 recovery
  policy only, with no `record` package types.
- [ ] Keep `SpeechRecognitionService` recognizers at 16 kHz.
- [ ] Add an epoch-scoped mono accumulator before `SpeechSegmenter`; emit only exact
  640-byte/20 ms VAD frames and account for the final remainder at stop.
- [ ] Test 512-byte, 1024-byte, and irregular even-length packet sequences across boundaries.
- [ ] Prove Vosk receives only mono PCM from the active capture epoch.
- [ ] Remove `dart:io` and `path_provider` from domain audio services; file diagnostics belong
  in native or Flutter infrastructure.
- [ ] Add a bounded Vosk queue per recognition lane: maximum 64,000 pending PCM bytes
  (2 seconds). Overflow raises `RECOGNITION_BACKLOG` and restarts the capture instead of
  silently dropping speech.

Exit criterion: wear voice unit tests pass without importing or constructing `AudioRecorder`.

### Phase 6: Replace WearVoiceSession Recovery

- [ ] Remove AudioRecord silencing and Android audio-source monitoring dependencies.
- [ ] Consume native states: service disconnect, Binder death, PCM timeout, SSP failure,
  activation failure, unsupported firmware, and queue overrun.
- [ ] Define readiness as current epoch streaming plus fresh processed PCM.
- [ ] Require at least three current PCM events and one non-zero processed sample before ready.
- [ ] Keep the 15-second startup budget unless device measurements justify a smaller value.
- [ ] Implement one automatic full UAC4 restart for a recoverable PCM timeout.
- [ ] After a repeated failure, publish unavailable state with the exact native reason.
- [ ] Do not request physical USB reconnect unless the vendor service reports that condition.
- [ ] Keep restart, retry, health check, and lifecycle ownership single-flight.
- [ ] Stop the matching lease on primary engine detach while allowing a recreated engine to
  attach to the application manager.
- [ ] Verify background/resume policy against actual service behavior.
- [ ] Update glasses overlay reasons to UAC4 terminology.

Exit criterion: session tests cover all native terminal and recoverable states without
AudioRecord-specific assumptions.

### Phase 7: Migrate Remaining Record Owners

- [ ] Migrate `VoiceCubit` to the shared native capture owner `legacyRecognition`.
- [ ] Ensure `VoiceCubit.close()` stops its capture lease and disposes Vosk resources.
- [ ] Remove its chunk-dropping `_isProcessingAudioChunk` strategy and use the new bounded
  recognition queue.
- [ ] Migrate `VoiceMemoCubit` to owner `voiceMemo`.
- [ ] Write voice memo as mono PCM16 WAV at 16 kHz.
- [ ] Write voice memo incrementally instead of holding the entire recording in memory.
- [ ] Bound the voice memo write queue at 64,000 PCM bytes (2 seconds). PCM acknowledgement
  occurs only after write-queue admission.
- [ ] On queue overflow, acknowledge `backpressure`, stop the lease, report a memo I/O error,
  and delete the temporary file; do not drop middle audio and save a corrupted memo.
- [ ] On voice memo stop/close/error, drain the bounded write queue, finalize the WAV header,
  fsync, and atomically rename a temporary file.
- [ ] Limit memo stop/drain to 5 seconds; timeout deletes the temporary file and reports
  failure instead of publishing a partial memo.
- [ ] Delete incomplete temporary voice memo files after native failure or application start.
- [ ] Test `VoiceMemoCubit.close()` while writes and native stop are in flight.
- [ ] Keep normalization only if it is proven not to clip processed SSP output.
- [ ] Return `CAPTURE_BUSY` when voice memo and recognition overlap.
- [ ] Add user-visible messages for unsupported firmware and busy capture.
- [ ] Confirm no feature creates an independent microphone owner.

Exit criterion: all application voice features use the same native manager and enforce one
active logical owner.

### Phase 8: Remove record And Obsolete Android Monitoring

- [ ] Remove `record` from `pubspec.yaml`.
- [ ] Regenerate `pubspec.lock` and verify `record` and `record_android` are absent.
- [ ] Remove every `package:record/record.dart` import.
- [ ] Remove `com.llfbandit.record.service.AudioRecordingService` from the manifest.
- [ ] Remove `FOREGROUND_SERVICE_MICROPHONE` if no remaining native component requires it.
- [ ] Validate whether client `RECORD_AUDIO` is required by the vendor service; remove it only
  after a physical-device test proves it is unnecessary.
- [ ] Replace permission requests in `SpeechRecognitionService`, `VoiceTypingService`, and
  `ear_print_code_input_cubit.dart` with native capability/permission status.
- [ ] Define and test both vendor outcomes: client permission required and service-owned
  permission not required. Do not leave an unnecessary prompt.
- [ ] Remove AudioRecord-specific `AudioRecordingCallback` code from `MainActivity`.
- [ ] Remove `updateVoiceCaptureMonitor` from Kotlin and Dart.
- [ ] Remove obsolete `audioCaptureSilencedChanged` and record-route diagnostics streams.
- [ ] Keep unrelated USB/device monitoring only if another feature consumes it.
- [ ] Remove old build profile options tied to `VOICE_COMMUNICATION`, `VOICE_RECOGNITION`,
  and `MIC` AudioRecord sources.
- [ ] Remove obsolete record foreground-service notification text and configuration.

Required zero-match checks:

```bash
rg "package:record/record.dart|AudioRecorder|RecordConfig|AndroidRecordConfig" lib test integration_test
rg "com.llfbandit.record|updateVoiceCaptureMonitor|audioCaptureSilencedChanged" android lib test
rg "\bAudioRecord\b|\bMediaRecorder\b" android/app/src/main lib test integration_test
rg "VOICE_DEVICE_PROFILE|VOICE_COMMUNICATION|VOICE_RECOGNITION" .
fvm flutter pub deps | rg "record|record_android"
```

Exit criterion: every command above returns no record-related production dependency or code.

### Phase 9: Automated Tests

Native JVM tests:

- [ ] Ring buffer preserves fragmented and unaligned callbacks.
- [ ] Ring buffer extracts exact 2048-byte frames.
- [ ] Four-channel RMS assigns samples to the correct channel index.
- [ ] SSP adapter validates output sizes.
- [ ] Input queue never exceeds eight frames.
- [ ] Only one PCM packet can remain unacknowledged.
- [ ] Missing acknowledgement reaches `PCM_ACK_TIMEOUT` without accumulating packets.
- [ ] State machine rejects illegal transitions.
- [ ] Duplicate operations join one in-flight operation.
- [ ] Capture owner conflict returns `CAPTURE_BUSY`.
- [ ] Stale or mismatched lease stop cannot stop the active owner.
- [ ] Binder death performs one cleanup and one fatal event.
- [ ] Late callbacks after stop are discarded.
- [ ] SSP release waits for the in-flight process call.
- [ ] Late activation and service-bind callbacks cannot revive a timed-out generation.
- [ ] Normal detach releases resources and supports re-attach; terminal abandonment reports
  unreleased vendor work and rejects capture until simulated process restart.
- [ ] Pure fakes exist for vendor activation, UAC4 calls, SSP, monotonic clock, scheduler,
  executor, and Flutter packet/event sink.
- [ ] Android instrumentation test verifies actual AIDL binding and Flutter channel wiring;
  JVM tests do not claim to prove Binder registration.

Dart tests:

- [ ] Native event maps decode into exhaustive typed states.
- [ ] Unknown native state or error fails safely.
- [ ] Stale lease IDs are rejected and acknowledged as `staleLease`.
- [ ] Odd PCM byte lengths are rejected.
- [ ] Audio metrics use mono 16 kHz timing.
- [ ] VAD frame duration remains correct for 512-byte, 1024-byte, and irregular packets.
- [ ] A slow Dart PCM consumer never permits more than one outstanding native packet.
- [ ] Wear startup waits for fresh non-zero native PCM.
- [ ] UAC4 timeout triggers only one automatic restart.
- [ ] Unsupported firmware is terminal and does not schedule legacy fallback.
- [ ] Voice memo writes a valid 16 kHz mono PCM16 WAV.
- [ ] Voice memo finalizes or removes temporary output on close and fatal native error.
- [ ] Voice memo admits at most 64,000 pending PCM bytes and enforces the 5-second drain limit.
- [ ] Legacy voice and voice memo release capture ownership on close.
- [ ] Permission/capability behavior is tested for both vendor permission contracts.
- [ ] Focused tests exist for `VoiceCubit`, `VoiceMemoCubit`, scanner startup, printing flow,
  navigation, and glasses projection before final regression claims are checked.
- [ ] Existing command, free-text, navigation, and glasses projection tests remain green.

Required commands:

```bash
fvm dart format --set-exit-if-changed lib test integration_test
fvm flutter analyze
fvm flutter test
./android/gradlew -p android testDebugUnitTest
./android/gradlew -p android :app:compileDebugKotlin
git diff --check
```

Hardware integration commands are separate and require the explicit serial:

```bash
fvm flutter test integration_test/audio_capture_test.dart -d "<T2151_SERIAL>"
fvm flutter test integration_test -d "<T2151_SERIAL>"
```

Exit criterion: all commands pass and zero test is skipped without a written reason.

### Phase 10: Physical T2151 Verification

Preparation:

- [ ] Record `adb devices -l` and target serial.
- [ ] Record firmware fingerprint, package version, ABI, and Android SDK.
- [ ] Confirm FourMicDemo works before testing this application.
- [ ] Clear logcat and app data when the test case requires a cold state.
- [ ] Confirm no second application is holding UAC4 capture.

Functional matrix:

- [ ] Cold boot, first app launch, activation, bind, init, and start.
- [ ] Warm app launch after successful activation.
- [ ] Start and stop voice capture 20 times without process restart.
- [ ] Run continuous command recognition for 30 minutes.
- [ ] Background for 30 seconds and resume 10 times.
- [ ] Lock and unlock the device 10 times.
- [ ] Disconnect/reconnect the glasses audio hardware if physically supported.
- [ ] Kill and restart `Uac4ClientService` if test permissions permit.
- [ ] Force-stop and relaunch the application.
- [ ] Verify unsupported firmware behavior on a device without the service.
- [ ] Verify `CAPTURE_BUSY` using voice memo while recognition is active.

Audio quality matrix:

- [ ] Quiet-room baseline for 60 seconds.
- [ ] Speech from front, left, right, and behind at 0.5 m.
- [ ] Speech at 1 m and 2 m.
- [ ] Store-noise scenario with music and nearby speech.
- [ ] Apply a 10-second close stimulus to each microphone position separately; the nearest
  channel must rise at least 6 dB above its quiet baseline and no two raw channel byte
  streams may be identical.
- [ ] Verify processed mono is non-zero and has less than 1% clipped samples.
- [ ] Compare raw four-channel and SSP mono WAV against FourMicDemo output.
- [ ] Run 100 fixed command utterances in the agreed quiet 1 m setup; at least 90 must map
  to the intended command.
- [ ] Run 30 free-text inputs in the agreed quiet 1 m setup; at least 24 must be usable
  without manual re-entry.

Performance limits:

- [ ] Input queue depth may not stay above four frames for more than 1 second.
- [ ] Exactly zero input-frame drops and zero PCM acknowledgement timeouts occur during the
  30-minute steady-state run.
- [ ] At most one PCM packet is outstanding across the Flutter boundary.
- [ ] No PCM callback gap above 500 ms while streaming.
- [ ] No ANR, Binder transaction failure, native crash, or Flutter OOM.
- [ ] Across 20 warm starts, p95 fresh-PCM latency is at most 3 seconds; cold activation may
  take at most 15 seconds.

Evidence to retain:

- [ ] APK path and SHA-256.
- [ ] Git commit SHA.
- [ ] Device and firmware identity.
- [ ] Full logcat for each failed case.
- [ ] Native diagnostics snapshots at start, steady state, and stop.
- [ ] Bounded diagnostic WAV files.
- [ ] Recognition result table and measured rates.

Implementation may be reported as `IMPLEMENTED_DEVICE_PENDING`, but release acceptance
requires Phase 0 and every safety-critical Phase 10 item to pass on the named firmware.
`DEVICE_PENDING` and `BLOCKED` never satisfy release sign-off. No hardware claim may be
inferred from unit tests.

### Phase 11: Documentation And Release Readiness

- [ ] Update `ARCHITECTURE.md` with the native UAC4 voice path.
- [ ] Update `docs/wear_ARCHITECTURE.md` with capture ownership and failure states.
- [ ] Mark old AudioRecord recovery documents as historical.
- [ ] Remove old T2151 build profile scripts or replace them with one native UAC4 build.
- [ ] Document required CI secrets without recording secret values.
- [ ] Document supported firmware and service package version.
- [ ] Document how to collect bounded native diagnostics.
- [ ] Record final test commands and results in this document.
- [ ] Review final diff for accidental scanner, wear-flow, or glasses regressions.
- [ ] Build the release APK.
- [ ] Install only on the explicitly selected T2151 serial.

Release verification:

```bash
fvm flutter build apk --release --target-platform android-arm64
sha256sum build/app/outputs/flutter-apk/app-release.apk
adb -s "<T2151_SERIAL>" install -r build/app/outputs/flutter-apk/app-release.apk
adb -s "<T2151_SERIAL>" shell am start -n ru.tander.smart_glasses/.MainActivity
```

Exit criterion: release APK is reproducibly built, installed, and validated on the approved
firmware with evidence recorded below.

## Final Acceptance Checklist

- [ ] `record` and `record_android` are absent from dependency resolution.
- [ ] No Dart or Kotlin production code references the old recorder path.
- [ ] No direct `AudioRecord` or `MediaRecorder` fallback exists.
- [ ] UAC4 service absence produces `unsupportedFirmware`.
- [ ] All four native input channels pass the isolated-stimulus and non-identical-stream
  hardware checks.
- [ ] SSP receives exact 2048-byte four-channel frames.
- [ ] Flutter receives only mono PCM16 LE at 16 kHz.
- [ ] Vosk recognition receives only the current capture epoch.
- [ ] One application-scoped manager prevents concurrent microphone sessions.
- [ ] Binder death, service disconnect, PCM timeout, and SSP errors are typed and visible.
- [ ] Native queues and Flutter delivery are bounded.
- [ ] Normal Activity/engine teardown releases service, worker, SSP, and channels; terminal
  vendor hangs enter `terminalAbandoned`, report unreleased resources, and require process
  restart without racing unsafe release.
- [ ] Wear command recognition and free-text entry pass regression tests.
- [ ] Voice memo and legacy voice no longer instantiate recorders.
- [ ] Scanner, printing, navigation, and glasses projection regression tests pass.
- [ ] Full automated suite passes.
- [ ] Phase 0 prerequisites and the complete required physical T2151 matrix pass with
  evidence; no release item remains `DEVICE_PENDING` or `BLOCKED`.
- [ ] No test credentials, secrets, raw recordings, or device identifiers are committed.

## Known Risks

| Risk | Required mitigation |
|---|---|
| UAC4 service is absent or not exported | Fail as `unsupportedFirmware`; confirm firmware package before implementation |
| Vendor credentials are unavailable | Stop at Phase 0; do not use demo credentials |
| Credentials can be extracted from APK | Require documented vendor/security approval or service-side provisioning |
| Channel order differs from SSP model | Obtain vendor mapping and compare four-channel diagnostic WAV |
| SSP AAR supports only arm64 | Keep supported hardware arm64 and verify APK native libraries |
| AAR native library name collision | Obtain vendor confirmation and test native loading on clean process start |
| Binder callbacks outrun processing | Eight-frame bounded input queue, metrics, and overrun error |
| Flutter platform delivery creates latency | Native SSP, two-frame batching, and one acknowledged BasicMessageChannel packet |
| SSP output gain clips | Start at gain 1.0 and tune only from measured evidence |
| Service lifecycle differs from demo | Treat undocumented behavior as blocker and capture return codes/logs |
| Old firmware loses voice support | Intentional consequence of removing record fallback; expose explicit UI state |
| Raw diagnostic audio contains personal data | Ten-second hard cap, approved build only, app-private storage, 24-hour cleanup |

## Rollback Strategy

There is no runtime `record` fallback in this design. Rollback means installing the last
known-good APK from `main` or reverting this feature branch before release. Do not add a
hidden dual-stack implementation to simplify rollback.

## Implementation Log

Add one row after each completed phase or discovered blocker.

| Date | Commit | Phase | Evidence | Result |
|---|---|---|---|---|
| 2026-07-28 | `a5fe754` | Plan | Branch `feature/native-uac4-voice` created; demo and current capture paths inspected | `PLANNED` |

## Final Sign-Off

- Implementation agent: `PENDING`
- Code review agent: `PENDING`
- Device tester: `PENDING`
- Supported firmware version: `DEVICE_PENDING`
- Final commit: `PENDING`
- Release APK SHA-256: `PENDING`
- Final status: `PLANNED`
