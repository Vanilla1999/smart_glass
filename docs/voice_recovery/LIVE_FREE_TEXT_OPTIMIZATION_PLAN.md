# Live Free-Text Optimization Plan

## Goal

Keep `WEAR_FREE_TEXT_PIPELINE_MODE=liveWithReplayFallback` while removing PCM
queue overruns, microphone restarts, and long UI stalls on large dynamic lists.

The visual voice-hint underline must remain. Existing command/free-text
arbitration, including `isExactHint` and `isStableMatch`, must not change.

## Constraints

- Keep command and live free-text recognizers enabled.
- Keep PCM16LE, mono, 16 kHz audio.
- Keep VAD operating on 20 ms frames.
- Do not increase native ACK timeouts or buffers before removing known stalls.
- Do not add microphone retries.
- Do not run hint generation, file I/O, or full-catalog preparation in the PCM
  admission path.
- Do not block partial or final recognition while a hint index is being built.
- Do not change matching or arbitration semantics without regression tests.

## Phase 1: Remove avoidable PCM-path work

1. Decouple continuous WAV recording from `WearMockConfig` and
   `SharedPreferences`.
2. Use only the explicit `VOICE_CAPTURE_WAV_DIAGNOSTICS` build flag to enable
   continuous WAV recording.
3. Add fast paths in `_publishPartialChange` for empty text and fixed commands.
4. Do not request dynamic items, run matching, or build hints for those fast
   paths.
5. Do not request the hint index for free-text partials.

Verification:

- A validation build with WAV diagnostics disabled never logs
  `continuous WAV recording path=`.
- Empty and fixed-command partials do not call the dynamic item provider.
- Free-text partial matching does not build voice hints.

## Phase 2: Share and precompute voice hints

1. Replace the separate glasses and recognition hint caches with one shared
   `VoiceHintIndexCache` created by `WearDependencies`.
2. Key entries by screen, list revision, item count, reserved phrases, and
   excluded words.
3. Deduplicate in-flight generation for the same key.
4. Build indexes larger than 32 items outside the Flutter main isolate. Small
   menu and clarification lists may be generated synchronously to preserve
   immediate command grammar.
5. Expose a non-blocking `peek` operation for recognition and rendering.
6. If an index is not ready, render without underlines and use existing list
   matching as the recognition fallback.
7. Refresh the glasses payload only if the screen and list revision are still
   current when generation completes.
8. Add direct maps for `itemId -> hint` and unique `phrase -> itemId` lookup.

Verification:

- One screen/revision/configuration starts one generation.
- The 1,063-item catalog is not indexed from a partial, final, or widget build.
- Glasses lookup is proportional to the visible item count.
- Stale index results are not applied to a newer route or list revision.

## Phase 3: Reduce Vosk platform-channel traffic

1. Keep VAD and replay retention on the existing 20 ms frames.
2. Batch four frames into 80 ms / 2,560-byte recognizer calls.
3. Flush incomplete batches before endpoints, finalization, grammar changes,
   recognizer replacement, free-text disable, stop, and capture restart.
4. Never mix capture epochs, segments, or command utterance IDs in a batch.
5. Keep command partial polling on every batch for immediate navigation
   commands.
6. Poll live free-text partials every second batch, approximately every 160 ms.
7. When free-text queue delay exceeds 300 ms, continue accepting PCM but skip
   that intermediate partial-result query.
8. Never skip final results or endpoint flushes.

Verification:

- Four 640-byte frames produce one 2,560-byte recognizer call per lane.
- Endpoint flush preserves one to three remaining frames.
- Backlog accounting uses actual batched byte counts.
- Existing immediate command and dual-arbitration tests remain green.

## Phase 4: Device validation

Build with:

```bash
WEAR_FREE_TEXT_PIPELINE_MODE=liveWithReplayFallback ./tool/build_voice_recovery_apk.sh
```

Validate on T2151 while opening and using the 1,063-item availability list.

Acceptance criteria:

- No `PCM_QUEUE_OVERRUN`, `PCM_ACK_TIMEOUT`, or `RECOGNITION_BACKLOG` during a
  30-minute run.
- No continuous WAV recording unless explicitly enabled.
- `sourceToDartMicros` is normally below 100,000 and remains below 300,000.
- Recognition queue delay returns to a low value after each utterance.
- Product-list rendering does not synchronously build the full hint index.
- The hint index is generated once per revision/configuration.
- Underlines remain visible after the asynchronous index becomes ready.
- A stable `безалкогольное` dynamic match beats conflicting `домой` or `назад`
  command recognition.

## Deferred work

If overruns remain after all measured stalls above are removed, move Vosk
recognizer operations to a serialized Android worker thread. This requires
canonical threading guidance or dedicated package-level validation and is not
part of the first optimization pass.

Only after that investigation may native queue capacity or ACK timeout changes
be considered.
