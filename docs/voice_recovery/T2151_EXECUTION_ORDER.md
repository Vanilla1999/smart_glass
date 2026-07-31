# T2151 Execution Order

Status: `SOFTWARE PATHS READY FOR VALIDATION; ACCEPTANCE GATES PENDING`

## Current Checkpoint

The software paths for steps 3-8 are implemented and covered by focused
regression tests. Step 2 baseline acceptance and the latency, accuracy and device
conditions attached to steps 3-9 remain open. The checked-in safe default stays
`replayOnly`; visible live preview validation uses an explicit
`liveWithReplayFallback` build. Steps 10 and 11 remain gated by step 9 results.

Completed in code:

- the UX contract is accepted;
- recognition results carry an explicit recognition timestamp;
- free-text partials produce typed `WearVoicePreviewEvent` shadow events with
  capture, utterance, route, grammar, free-text epoch, screen and revision
  context;
- shadow matching logs the predicted dynamic item and final-result agreement;
- `shadowLive` partials are logged but suppressed before the typed result stream
  and cannot change focus or execute a business action;
- deterministic voice hints are generated from the complete active candidate
  set;
- one-letter, stop-word-only and number-only hints are rejected;
- meaningful three-character words are accepted;
- structured hint ranges survive the glasses bridge and render in bold;
- printer, duplicate-product, availability group/product and clarification
  lists use the same generated hint metadata for visible rows;
- focus border/marker rendering remains independent from hint weight.
- stable unique partials move focus after a 150 ms stability delay and cannot
  select, navigate, print or execute another business action;
- visible preview requires two distinct matching partial observations and one
  utterance cannot preview two different items;
- preview events are rejected when capture, utterance, route, grammar,
  free-text, screen or list context is stale;
- screen grammar combines fixed commands with current voice hints and defers
  changes until an utterance boundary; deferred calls are latest-wins and
  complete or fail with the applied switch;
- exact dynamic keys from the command grammar carry a typed item ID into the
  same context-safe preview path instead of being discarded as unknown commands;
- progressive clarification retains spoken phrases, recalculates hints and
  excludes previously spoken words; its current page owns the active grammar,
  partials change focus only and selection revalidates the source-list revision;
- the delayed recognition notice starts at segment speech onset, appears after
  900 ms without useful feedback and is cleared by preview, command, final or
  segment completion;
- explicit voice aliases participate in dynamic matching and candidate-set
  revision identity; visible aliases are preferred for generated hints;
- replay and live results retain the list revision captured when their utterance
  started and are rejected after a newer utterance starts;
- recognition-delay events retain route and segment ownership, so old show/hide
  events cannot mutate a newer route or segment;
- preview usefulness is segment-owned and cannot clear another segment's delay;
- direct-scan duplicate rows expose the same generated hint metadata and dynamic
  matching contract as the other data-backed selectable lists;
- delayed live finals are rejected after a newer utterance starts;
- command-lane OOV results are logged for grammar diagnostics.
- command and delay events are capture-owned at the UI admission boundary;
- direct-scan duplicate payloads feed dynamic grammar and free-text matching;
- runtime-capability-filtered command phrases reserve dynamic voice hints;
- validation APK builds force mocks, auth shortcuts, scanner skip and WAV
  diagnostics off before mock configuration initializes;
- native PCM headers now retain source monotonic and wall-clock timestamps
  through fragmented SSP input, and Dart logs source-to-admission age;
- the runtime fingerprint logs free-text mode, mock/WAV flags, device profile,
  VAD/audio/endpoint configuration and initial grammar size. Android's existing
  native diagnostics remain the source for device model/version and route data.

Pending before the baseline exit condition can be accepted:

- device runs for the required phrases and p50/p95/p99 calculation;
- device validation of native source-to-Dart admission age and clock behavior;
- CPU, memory, temperature and battery capture on the target device.
- explicit `liveWithReplayFallback` validation builds and rollback evidence;
- preview/final disagreement, false-focus, command-regression and flicker gates;
- the complete noisy-store matrix and endpoint sweep.

Automated verification at this checkpoint:

- the targeted voice-recovery regression and integration suite includes direct
  150 ms preview, 900 ms notice, final-ownership, deferred-grammar and stale
  route tests;
- `git diff --check` is clean;
- `flutter analyze` reports project lint debt and no compilation errors.

Next execution boundary: capture the missing step 2 baseline, then run the
step 3-8 acceptance matrix and step 9 physical noisy-store validation on the
target device. Do not start endpoint sweep or optimistic selection before step
9 meets its exit conditions.

Related documents:

- `T2151_VOICE_HINT_UX_PLAN.md`
- `T2151_DYNAMIC_PARTIAL_PIPELINE_PLAN.md`
- `T2151_NOISY_STORE_VALIDATION_PLAN.md`

## Execution Principle

The three plans are not implemented independently one after another.

- The UX plan defines the product contract.
- The dynamic partial plan defines implementation stages.
- The validation plan is executed throughout development, not only at the end.

## Order

### 1. Approve the UX Contract

Use `T2151_VOICE_HINT_UX_PLAN.md`.

Confirm:

- every displayed item has a meaningful bold voice key;
- one-letter, stop-word-only and standalone-number keys are forbidden;
- free-text accepts one or more parts of an item name;
- clarification progressively filters the current candidate set;
- stable partial changes focus only;
- final result owns selection and navigation;
- delayed recognition notice appears only when useful feedback is late.

Exit condition: UX rules are accepted and no unresolved product behavior remains.

### 2. Capture the Baseline

Use Stage 0 of `T2151_DYNAMIC_PARTIAL_PIPELINE_PLAN.md` and Experiment A of
`T2151_NOISY_STORE_VALIDATION_PLAN.md`.

Record:

- native sample to Dart admission;
- VAD start;
- first command and free-text partial;
- endpoint;
- final decision;
- focus/selection payload and rendered frame;
- queue and recognizer latency;
- CPU, memory and temperature.

Required scenarios:

```text
up
down
white
yellow
mobile
multiword product name
ambiguous product name
```

Exit condition: p50, p95 and p99 latency budgets are available for the current
final-only behavior.

### 3. Add Typed Partial Events in Shadow Mode

Implement context-rich preview events without changing UI behavior.

Required context:

- capture epoch;
- utterance ID;
- route revision;
- grammar revision;
- free-text epoch;
- source screen;
- partial revision;
- timestamp.

Compute intended focus changes and compare them with final decisions, but do not
show or execute them.

Exit condition:

- stale preview events are always rejected;
- duplicate intents remain zero;
- preview/final disagreement is measured;
- command latency regression is within the accepted limit.

### 4. Implement Voice Keys and Bold Rendering

Implement one deterministic source of truth for:

- item ID;
- bold phrase;
- label ranges;
- matcher phrase;
- constrained grammar phrase;
- candidate-set revision.

Add validation for stop words, one-letter keys, duplicate keys and items without
pronounceable unique metadata.

Exit condition:

- every displayed test item has one valid bold key or an explicit validation
  failure;
- saying the key resolves to exactly one item in the complete active candidate
  set;
- focus and bold hint remain visually distinct.

### 5. Enable Stable Partial Focus Preview

Connect typed partial events to `WearFlowController.handleVoicePartialPhrase`.

Initial policy:

```text
stable unique partial -> move focus
stable ambiguous partial -> prepare candidates only
unstable partial -> no visible change
final unique -> select
final ambiguous -> clarification
```

No partial may select a printer, navigate, print or perform another business
action.

Exit condition:

- partial focus preview is context-safe;
- final result overrides preview;
- false focus and preview/final disagreement satisfy the pilot limits.

### 6. Add Dynamic Constrained Grammar

Add bold voice keys for the currently rendered page to the screen-scoped command
grammar. Keep arbitrary free-text active across the complete logical list.

Requirements:

- update grammar only between utterances;
- log grammar size, switch time and OOV phrases;
- retain free-text and replay fallback;
- preserve immediate `up`/`down` behavior.

Exit condition:

- bold keys produce earlier stable partials;
- `up`/`down` p95 regression is no more than 10%;
- false activation rate does not increase beyond the accepted threshold;
- PCM drops and duplicate intents remain zero.

### 7. Complete Progressive Clarification

Use the existing recursive clarification flow and add:

- cumulative spoken-phrase context;
- voice-key recalculation after every candidate reduction;
- exclusion of already spoken and common words from preferred keys;
- bold differentiating phrases for every displayed candidate;
- constrained grammar for the current clarification page;
- free-text matching over all remaining candidates;
- previous candidate-set restoration on back.

Exit condition:

- a second or third phrase narrows the current set without repeating earlier
  words;
- one remaining item is selected correctly;
- unchanged and no-match phrases preserve the correct candidate set;
- stale or removed items cannot be selected.

### 8. Add the Delayed Recognition Notice

Start a 900 ms timer at `VAD_START`.

```text
useful stable partial -> cancel timer
command/final result -> cancel timer
timeout -> show compact `Распознаю...`
utterance end/result -> clear notice
```

The notice must use the compact list notice and must not cover list items.

Exit condition:

- normally fast `up`/`down` commands do not show the notice;
- stale timers cannot update another route;
- the notice does not flicker during normal short commands.

### 9. Run Store Validation

Execute the complete `T2151_NOISY_STORE_VALIDATION_PLAN.md`.

Required conditions:

- quiet baseline;
- controlled store noise at approximately 15, 10 and 5 dB SNR;
- store before opening;
- normal store operation;
- noisiest known store zone;
- at least one eight-hour equivalent of hard-negative audio.

Exit condition: all required safety, latency, accuracy and device-stability gates
are accepted.

### 10. Optimize the Endpoint

Only after partial preview and constrained grammar are validated, compare:

```text
500 ms
400 ms
300 ms
```

Measure:

- total selection latency;
- truncated phrases;
- accidental utterance splitting;
- false final results;
- misses in store noise.

Do not reduce the endpoint globally based only on quiet-room results.

Exit condition: one endpoint configuration is demonstrably faster without
violating accepted store-noise limits.

### 11. Consider Optimistic Selection

This stage is optional and disabled by default.

It may be considered only for reversible actions after separate approval and
validation.

Requirements:

- validated stable partial plus short silence;
- exactly-once provisional action;
- rollback when final recognition disagrees;
- no printing, database write or irreversible operation from partial speech.

Exit condition: store evidence proves an accepted false-selection and rollback
rate.

## Validation Runs Throughout the Order

The validation plan is used at every relevant stage:

| Stage | Validation activity |
|---|---|
| Baseline | Final-only latency and accuracy |
| Shadow partial | Preview/final agreement and stale-event safety |
| Bold rendering | Key uniqueness and UI correctness |
| Visible preview | False focus and perceived latency |
| Dynamic grammar | Speed, OOV, false activation and command regression |
| Clarification | Multi-turn success and candidate safety |
| Endpoint sweep | Latency versus truncation and false finals |
| Optimistic selection | Rollback and business safety |

## Global Stop Conditions

Stop rollout and restore final-only dynamic selection when any condition occurs:

- duplicate business intent;
- stale route or list action;
- irreversible action from partial speech;
- false navigation above the accepted threshold;
- growing PCM or recognizer queue;
- recognizer hang or repeated timeout;
- `up`/`down` p95 regression above 10%;
- unacceptable temperature or battery regression.
