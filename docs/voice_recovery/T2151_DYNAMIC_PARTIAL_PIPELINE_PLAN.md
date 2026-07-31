# T2151 Dynamic Partial and Constrained Grammar Plan

Status: `IN_PROGRESS`

Related documents:

- `T2151_LIVE_FREE_TEXT_PIPELINE.md`
- `T2151_VOICE_HINT_UX_PLAN.md`
- `T2151_NOISY_STORE_VALIDATION_PLAN.md`

When this plan is implemented, it supersedes two older baseline statements in
`T2151_LIVE_FREE_TEXT_PIPELINE.md`:

- free-text partials remain forbidden from executing an item, but may publish a
  context-safe focus preview;
- an allowed exact fixed command wins over a simultaneous dynamic match instead
  of being rejected as a generic conflict.

## 1. Objective

Reduce perceived and actual latency for dynamic list choices such as `жёлтый`,
`белый` and product-name fragments while preserving exactly-once behavior,
route safety and noisy-store reliability.

Target behavior:

```text
stable partial -> focus preview
final or validated short endpoint -> selection
ambiguous final -> progressive clarification
```

Fixed `up` and `down` commands retain their existing immediate exact-partial
path.

## 2. Observed Baseline

The supplied device log showed:

| Scenario | Observed latency |
|---|---:|
| `up`/`down` median recognition | approximately 540 ms |
| `yellow` speech to phrase | 1192 ms |
| `white` speech to phrase | 1100 ms |
| dynamic endpoint to decision | 74-99 ms |
| decision to glasses update | approximately 2-15 ms |

Dynamic recognition after the VAD endpoint is already fast. The dominant delay
is word duration plus the approximately 500 ms silence boundary.

## 3. Current Pipeline

On a free-text screen, PCM is sent to command and free-text recognizers:

```text
PCM
-> command recognizer -> command partial/final
-> free-text recognizer -> free-text partial/final
```

`SpeechRecognitionService` already calls `getPartialResult()` for both lanes and
publishes a `SegmentedRecognitionResult` when the text changes.

The current free-text partial is then intentionally discarded in
`RecognitionArbiter`:

```dart
if (result.lane == RecognitionLane.freeText) {
  if (result.kind == RecognitionKind.partial) return null;
  return RecognitionArbitration.phrase(result);
}
```

Additional inactive infrastructure already exists:

- `WearVoiceControlService.freeTextPreviewStream`;
- `RecognitionArbitration.preview`;
- `WearFlowController.handleVoicePartialPhrase`;
- screen-level `onPartialPhrase` handlers.

The missing links are:

- a safe free-text partial arbitration policy;
- a typed preview event carrying recognition context;
- a `WearModuleApp` preview subscription;
- production dispatch to `handleVoicePartialPhrase`;
- dynamic constrained grammar for fast visible voice keys.

## 4. Safety Requirement

Do not connect the existing `Stream<String?>` directly to UI actions.

A preview must preserve:

- `captureEpoch`;
- `commandUtteranceId`;
- `routeRevision`;
- `grammarRevision`;
- `freeTextEpoch`;
- `sourceScreen`;
- `partialRevision`;
- recognized text;
- timestamp.

`WearModuleApp` must reject a preview when its route, grammar, epoch or source
screen is stale. The same safety model used by command and final phrase events
must apply to partial previews.

## 5. Proposed Data Model

Introduce typed concepts equivalent to:

```text
VoiceHint
- itemId
- phrase
- label ranges to render in bold
- candidate-set revision

WearVoicePreviewEvent
- text
- recognition context
- partial revision
- recognized timestamp

VoiceHintSet
- screen
- candidate-set revision
- hints by item ID
- grammar phrases for the currently rendered page
```

The exact Dart names may follow existing project conventions. The required
information and invariants are more important than the names.

## 6. Voice Hint Generation

Generate hints from the complete active candidate set according to
`T2151_VOICE_HINT_UX_PLAN.md`.

Required properties:

- every hint maps to one stable item ID;
- every hint is unique in the active candidate set;
- stop-word-only and one-letter hints are rejected;
- explicit data aliases take priority over generated phrases;
- duplicate or indistinguishable labels produce a validation result;
- hint generation is deterministic;
- the hint-set revision changes whenever item IDs, labels or aliases change.

The matcher and renderer must consume the same generated hint set.

## 7. Dynamic Grammar Strategy

The command grammar remains screen-scoped.

On list screens, the runtime grammar contains:

- fixed commands valid on the screen;
- bold voice keys for the currently rendered page;
- explicit full phrases when the phrase count remains bounded;
- `[unk]` when enabled.

Free-text remains active across the complete logical list. A user may speak an
item or phrase that is not visible on the current page.

Grammar rules:

- update grammar only between utterances;
- defer page/list changes while a VAD segment is active;
- never mutate the recognizer grammar in the middle of `acceptWaveform`;
- validate that grammar words exist in the Vosk model vocabulary when possible;
- log OOV phrases and keep free-text fallback available;
- normalize `ё`/`е` consistently while retaining accepted variants where the
  recognizer requires them.

## 8. Partial Arbitration Policy

### 8.1 Fixed commands

- `up` and `down`: retain immediate exact-partial execution.
- all other fixed commands: retain endpoint-only execution unless a separate
  reviewed policy explicitly changes them.

### 8.2 Bold dynamic key

A dynamic partial may produce a focus preview only when:

- the phrase is an exact complete voice key;
- it identifies one current item;
- the candidate-set revision is current;
- the same normalized result is stable for at least 150 ms;
- at least two matching partial revisions have been observed when the recognizer
  provides them;
- no conflicting fixed command exists;
- the utterance has not already produced a preview for another item.

The 150 ms value is an initial experiment parameter, not a production constant.

### 8.3 Arbitrary free-text partial

An arbitrary multiword partial may be matched for preview purposes.

- unique stable match: focus the item;
- multiple matches: retain candidates internally but do not navigate;
- no match: do nothing;
- changed hypothesis: replace the preview candidate;
- final disagreement: final result wins.

No business side effect is allowed from this path during the first rollout.

## 9. Final Decision Policy

The final coordinator remains the exactly-once owner.

```text
fixed command final -> execute command
dynamic unique final -> select item
dynamic ambiguous final -> open clarification
dynamic no match -> show compact failure notice
stale/conflicting result -> no side effect
```

Command candidates keep priority over dynamic matches when they represent an
allowed exact command for the current screen.

The selected dynamic item must be revalidated against the current item set and
revision before dispatch.

## 10. Progressive Clarification

The existing clarification implementation already performs recursive filtering.

Required additions:

- preserve all previously spoken phrases in clarification context;
- generate a new hint set after every candidate reduction;
- exclude already spoken and common candidate words from preferred hints;
- render the new hint phrase in bold for every displayed candidate;
- configure the constrained grammar from the current clarification page;
- keep full free-text matching over every remaining candidate;
- preserve previous candidate sets for back navigation.

The clarification screen must not require a literal `next word` command. Any
additional meaningful word or phrase narrows the current set.

## 11. Delayed Notice

Add a recognition-delay timer owned by the active utterance context.

```text
VAD_START -> start 900 ms timer
useful stable partial -> cancel timer
command/final result -> cancel timer
timeout -> show compact `Распознаю...`
utterance end/result -> clear notice
```

The timer must be cancelled on route, grammar, capture and free-text epoch
changes. A stale timer must never update a new screen.

## 12. Implementation Stages

### Stage 0: Instrumentation baseline

- Record native sample age at Dart admission.
- Record free-text partial text and timestamps.
- Record first stable candidate and first focus update.
- Record final selection and glasses render.
- Confirm whether short free-text words currently produce non-empty partials.

Exit condition: complete latency budget exists for `yellow`, `white`, `mobile`
and representative multiword names.

### Stage 1: Typed preview transport

- Add a context-rich preview event.
- Return safe preview candidates from arbitration.
- Subscribe in `WearModuleApp`.
- Validate route and revisions before dispatch.
- Invoke `WearFlowController.handleVoicePartialPhrase`.
- Define a successful handler return as `true`.

Exit condition: a stable unique partial changes focus only, with no navigation
or selection.

### Stage 2: Voice hints and rich rendering

- Implement deterministic hint generation.
- Add data validation for missing unique voice metadata.
- Extend glasses payload/state with structured voice hints.
- Render hint spans in bold.
- Keep focus border and marker visually distinct.

Exit condition: every displayed test item has one valid bold hint and the same
hint resolves to its item ID.

### Stage 3: Dynamic constrained grammar

- Add current-page hint phrases to runtime grammar.
- Defer grammar changes until utterance boundary.
- Add OOV and grammar-size diagnostics.
- Preserve arbitrary free-text over the complete list.

Exit condition: bold short phrases produce an earlier stable partial without
regressing `up`/`down` latency or command accuracy.

### Stage 4: Progressive clarification hints

- Recalculate hints after every candidate reduction.
- Preserve cumulative filtering and back history.
- Update grammar and glasses payload for the current clarification page.
- Add delayed recognition notice.

Exit condition: ambiguous results can be resolved with a second or third
free-text phrase without repeating earlier words.

### Stage 5: Optional optimistic selection

This stage is disabled by default.

- Consider selection after a validated stable partial plus short silence.
- Restrict it to reversible actions.
- Roll back when final recognition disagrees.
- Keep printing, database writes and irreversible actions final-only.

Exit condition: noisy-store validation proves an acceptable false-selection and
rollback rate.

## 13. Automated Coverage

Required unit tests:

- one-letter and stop-word-only hints are rejected;
- meaningful three-character words are allowed;
- shortest unique word is selected;
- a unique two- or three-word phrase is selected when required;
- duplicate voice labels require explicit metadata;
- uniqueness uses the complete candidate set, not only the visible page;
- `ё` and `е` normalization is consistent;
- multiword free-text matches an item;
- repeated clarification narrows the current set;
- unchanged clarification produces `Назовите точнее`;
- stale preview events are rejected;
- final result overrides a preview;
- a partial never performs a business side effect;
- exactly one final intent is emitted;
- grammar updates do not occur mid-utterance;
- fixed command wins over a conflicting dynamic candidate.

Required widget/integration tests:

- bold spans correspond to generated voice hints;
- focus and bold hint remain visually distinct;
- stable partial moves focus;
- final unique result selects;
- ambiguous final opens clarification;
- a second phrase updates candidate items and bold hints;
- delayed notice appears only after timeout and clears safely;
- route change suppresses stale preview and notice events.

## 14. Non-Goals

- Executing print or database operations from partial speech.
- Using a wake word as authentication.
- Treating ASR confidence as product identity verification.
- Adding every product-name combination to a fixed command catalog.
- Replacing barcode verification with speech.
