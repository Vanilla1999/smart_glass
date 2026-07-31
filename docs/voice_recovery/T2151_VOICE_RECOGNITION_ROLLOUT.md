# T2151 VOICE_RECOGNITION Rollout Plan

## Strict policy update

Production never changes source automatically: `VOICE_RECOGNITION` requires
the UVC input. Exact-zero waits 1500 ms, performs one hard recreate, then the
second `VOICE_RECOGNITION` attempt waits 3000 ms (4000 ms capture timeout).
Failure is unavailable/reconnect, not `VOICE_COMMUNICATION` fallback. WAV
diagnostics require `VOICE_CAPTURE_WAV_DIAGNOSTICS=true`.

## Decision

`VOICE_RECOGNITION` is the primary experimental T2151 profile. Android defines
it as a speech-recognition microphone source, but it becomes the production
profile only after the hardware matrix below passes. `VOICE_COMMUNICATION`
remains the validated release fallback candidate.

Observed problem: callbacks and `AudioRecord` can be active while every PCM
sample is exactly zero for 5-6 seconds. This is an audio-route startup issue,
not a Vosk quality issue after usable PCM arrives.

## Ready Contract

For `t2151_voice_recognition`, `ready` requires all of the following:

- at least three chunks from the current capture;
- a recent audio callback;
- at least one raw PCM sample different from zero in the current capture;
- no active continuous exact-zero interval;
- capture not silenced by Android; and
- a current capture epoch.

Low non-zero RMS is valid hardware silence and must not trigger restart.
Commands are accepted only in `ready`.

## States And Overlay

- `loadingModel`: "Подготовка голосового управления".
- `startingRecorder`: recorder is being created.
- `waitingForAudioRoute`: recorder has exact-zero PCM; "Подключаем микрофон очков".
- `ready`: commands permitted.
- `suspendedBySystem`, `reconnecting`, `unavailable`, and
  `microphoneReconnectRequired`: existing recovery states.

## Startup Strategies

| Strategy | Behavior | Device sample |
|---|---|---|
| A | Wait up to 7 seconds for non-zero PCM; no recreate. | 20 cold starts |
| B | After 1200 ms exact-zero, stop/dispose, wait 300 ms, recreate once, then wait 2500 ms. | 20 cold starts |
| C | Explicitly select the current USB/UVC input before each recorder creation, including after reattach. | 20 cold starts |

Profile starting policy for B: `requireNonZeroPcmForStartup=true`,
`exactZeroStartupGrace=1200 ms`, `recoveryCaptureTimeout=2500 ms`, and one
startup recorder recreation. These are experimental values, not final tuning.

The successful strategy must meet: p95 start-to-first-nonzero <= 2 seconds,
zero false-ready events, no more than one recreation per startup, and no rapid
restart loop.

## Recovery Contract

- Startup exact-zero: recreate at most once.
- Runtime missing PCM for over 3 seconds: hard restart.
- Runtime exact-zero for 2-3 seconds: hard restart; ordinary low RMS does not.
- `isClientSilenced=true`: suspend and prohibit restart loops.
- Unsilence: one hard restart.
- USB removal: cancel capture and wait for input; USB add: wait for HAL settle,
  reacquire the device ID, and start.
- Production fallback target: `VOICE_RECOGNITION` -> one recreation ->
  `VOICE_COMMUNICATION`; the next cold start retries `VOICE_RECOGNITION`.

## Native Diagnostics And UVC Work

The existing Android `AudioRecordingCallback` already logs recording source,
session ID, silencing, formats, and routed device, but it identifies captures
by source rather than an `AudioRecord` instance. The follow-up requires either
a minimal `record_android` fork or a dedicated native capture bridge to expose
capture ID, audio session ID, requested/active source, preferred/actual device,
silencing, formats, effects, and `AudioDeviceCallback` route events. USB device
IDs must be reacquired after physical reattach.

## Vosk Startup

Start Vosk preparation after successful authorization when the voice session
starts. Create the command recognizer first, defer the free-text recognizer
until a product-search screen, retain the model between screens, and avoid
per-route `setGrammar()` calls.

## Validation Matrix

The validation build script now pins mocks, mock authentication shortcuts,
scanner skipping and diagnostic WAV capture to `false` with compile-time
defines. Runtime logs include the source fingerprint and effective voice
configuration. This improves session precondition evidence but does not satisfy
the device latency, thermal, battery, route, model or Android-version acceptance
measurements.

- 20 cold starts each for A, B, and C; play a fixed phrase before recorder start.
- Record start, first callback, first non-zero, first VAD start, first partial,
  and command execution. Save the first 8 seconds of PCM only in diagnostic APKs.
- 50 cold starts and 50 background/resume runs for the selected strategy.
- 20 USB unplug/replug runs, microphone contention, 100 quiet commands, and
  100 noisy-room commands.
- Compare VAD pairs `0.0008/0.0005`, `0.0007/0.0004`, and `0.0006/0.00035`
  only after route startup is stable.

`VOICE_RECOGNITION` can become production only with zero false-ready events,
p95 usable PCM <= 2 seconds after warm model, >= 98% fixed-command success,
no more than 50 ms worse p95 command latency than `VOICE_COMMUNICATION`,
verified resume/reattach recovery, and no restart loop.
