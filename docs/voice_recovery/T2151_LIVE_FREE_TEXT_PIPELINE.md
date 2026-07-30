# T2151 Live Free-Text Pipeline

Status: `DEVICE_PENDING`

## Baseline

The production-compatible baseline is `replayOnly`:

```text
command live -> endpoint -> retained PCM replay -> free-text result
```

Retained utterance PCM and replay remain available for recovery.

## Modes

`WEAR_FREE_TEXT_PIPELINE_MODE` accepts:

- `replayOnly` - existing sequential behavior and the default.
- `shadowLive` - command and free-text receive live PCM, but UI behavior still
  uses the existing command/replay path.
- `liveWithReplayFallback` - both lanes run live and a single decision is
  published after their FIFO boundary.

Live free-text is active only while the existing `freeTextEnabled` screen mode
is active. Grammar-only screens continue to feed only the command recognizer.

## Safety

- `up` and `down` remain the only commands allowed from exact partial results.
- All other production commands remain endpoint-only.
- First-result-wins is forbidden.
- Free-text partials never execute a dynamic item.
- Different command and free-text finals are rejected as a conflict.
- Late results are guarded by capture, route, grammar and free-text epochs.
- Native calls are serialized per lane. Reset and dispose are not invoked in
  the middle of `acceptWaveform`.

The live free-text queue has an independent byte backlog limit. When the limit
is exceeded, the complete live result for that utterance is invalidated;
individual frames are not silently dropped. Retained PCM is then replayed.

## Boundary

Each immutable 20 ms PCM frame is enqueued to the command lane and, on
free-text screens, to the free-text lane. Finalization is appended to the same
free-text serial queue. This FIFO barrier ensures all earlier frames are
processed before `getFinalResult` and reset.

The first implementation deliberately does not batch frames.

## Warm-Up

In `shadowLive` and `liveWithReplayFallback`, a newly created free-text
recognizer receives a short silent buffer directly, followed by bounded
finalization and reset. This buffer bypasses VAD and cannot affect VAD
calibration or publish a result.

## Metrics

Structured logs include:

- `VOICE_LIVE_FREE_TEXT`: mode, capture, segment, utterance, chunk, queue delay,
  recognizer time and audio lag.
- `VOICE_DUAL_FINAL`: command text, free-text text and endpoint-to-final time.
- `VOICE_ARBITRATION`: command, dynamic item, conflict or none.
- `VOICE_FREE_TEXT_FALLBACK`: reason, capture, utterance and replay bytes.
- `VOICE_SHADOW_COMPARISON`: live candidate and production replay mode.

Diagnostics now report the active pipeline mode and non-zero live free-text
processed chunks. Replay fallback and conflict counters are exposed for tests.

## T2151 Verification

Set:

```text
WEAR_FREE_TEXT_PIPELINE_MODE=shadowLive
```

Run:

```text
yellow x30
mobile x30
white x30
up x30
down x30
back x20
select x20
```

Repeat in a quiet room and with store background speech, using different
speaking rates and volumes. Run one continuous session for at least 30 minutes.

Do not enable `liveWithReplayFallback` by default until:

- live dynamic accuracy is no worse than replay;
- p99 audio lag does not grow over time;
- PCM drops remain zero;
- up/down latency regression is at most 10%;
- false command and dynamic selection rates do not increase;
- no duplicate or stale intent is observed;
- recognizers do not hang;
- CPU, RAM, GC and temperature are acceptable on T2151;
- replay fallback is rare and has an explicit reason.

The target latency is at most 1250 ms for `yellow` and 1350 ms for `mobile`.
These are hardware acceptance targets, not verified results.

## Decision coordinator

`VoiceUtteranceCoordinator` owns the exactly-once decision state. Its key contains `captureEpoch`, `commandUtteranceId`, `routeRevision`, `grammarRevision`, `freeTextEpoch`, and `sourceScreen`. Dynamic candidates are typed separately from fixed commands and carry a stable item ID plus the list revision used for matching.

Before publication the coordinator revalidates the complete context and checks that the matched item still exists. Route, capture, free-text epoch, or list changes produce a stale decision with no business side effect.

An uncertain live recognizer is detached before replacement. Its native operation is allowed to finish, and disposal is deferred until that future completes. Retained PCM is then replayed through the replacement recognizer.

## Automated coverage

The live pipeline and coordinator tests cover PCM fan-out, grammar-only compatibility, live dynamic selection, false command partials, immediate up/down, endpoint-only partial suppression, command-only and same-semantic results, conflict and ambiguity rejection, backlog and timeout fallback, route/capture/free-text/list invalidation, shadow isolation, replay-only compatibility, exactly-one intent, and no native mid-operation disposal.

Natural endpoint and VAD fallback ordering are additionally covered by `speech_recognition_service_pipeline_test.dart`.
