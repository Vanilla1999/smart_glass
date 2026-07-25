# T2151: Fast Voice Aliases and Segment Arbitration

## Implementation Status

Completed:

- [x] `VoiceActionCatalog` defines screen-scoped full phrases, fast aliases,
  and `immediateExactPartial` / `finalOnly` policies.
- [x] Global Vosk grammar includes the catalog's full phrases and aliases at
  recognizer creation; grammar is not changed on route transitions.
- [x] `RecognitionArbiter` captures `VoiceSegmentContext` at VAD segment start,
  including the actual screen and catalog revision, and resolves all segment
  results against that context.
- [x] An early command claims its segment, blocks sibling free text, suppresses
  a repeated final command, and logs a different final as a correction.
- [x] An alias from another screen does not claim the segment, leaving free text
  eligible for final resolution.
- [x] Free-text partials are emitted only through `freeTextPreviewStream`; the
  committed Wear flow receives final phrases only, and a grammar claim clears
  its segment preview.
- [x] The catalog rejects duplicate immediate aliases for a screen.
- [x] Unit and integration coverage proves VAD-start screen capture, preview
  isolation, fast aliases, final-only commands, foreign aliases, correction
  handling, and `прямое` navigation before segment closure.

Remaining:

- [ ] Expand the catalog with aliases for every concrete action label after the
  product owner confirms the final alias list per screen.
- [ ] Run the 30-50 repetition T2151 device protocol and record timing and
  correction telemetry.

## Observed Behavior

Recognition itself works. Vosk quickly emits `прямое` several times and then
`прямое сканирование`, but the command is not executed. The current problem is
not the microphone or audio quality. It is the grammar-partial handling policy
introduced with segment arbitration.

In one measurement, `прямое` appeared in `PARTIAL`, and the full phrase arrived
about 266 ms later. Safely executing an exact short alias can therefore make the
interface noticeably faster.

The intended design is screen-scoped aliases plus a grammar lane, a free-text
lane, and an arbiter that makes the two lanes work together.

## Terminology

The feature is not arbitrary "part of a word" recognition. It is recognition of
one pre-registered, complete word or short stable phrase from an action label.

Supported examples:

| Action label | Fast aliases |
| --- | --- |
| `Прямое сканирование` | `прямое`, `сканирование` |
| `Список товаров` | `список`, `товары` |
| `Печать ценника` | `печать`, `ценник` |
| `Сделать фото` | `фото` |

Unsafe and unsupported examples:

- `прям`
- `сканир`
- `печат`
- `выб`

Vosk may emit one partial hypothesis and later correct it. Executing arbitrary
fragments would reintroduce this failure mode:

```text
partial: вверх
final:   вниз
```

## Voice Action Catalog

Create a declarative action catalog:

```dart
enum VoiceActivationPolicy {
  immediateExactPartial,
  finalOnly,
}

class VoiceActionEntry {
  const VoiceActionEntry({
    required this.command,
    required this.screens,
    required this.fullPhrases,
    required this.fastAliases,
    required this.activationPolicy,
  });

  final WearVoiceCommand command;
  final Set<WearScreenId> screens;

  /// Full variants of the command.
  final Set<String> fullPhrases;

  /// Complete words and short stable phrases only.
  final Set<String> fastAliases;

  final VoiceActivationPolicy activationPolicy;
}
```

Example:

```dart
VoiceActionEntry(
  command: WearVoiceCommand.openDirectScan,
  screens: {
    WearScreenId.availabilityInteraction,
  },
  fullPhrases: {
    'прямое сканирование',
  },
  fastAliases: {
    'прямое',
    'сканирование',
  },
  activationPolicy: VoiceActivationPolicy.immediateExactPartial,
)
```

For a list:

```dart
VoiceActionEntry(
  command: WearVoiceCommand.openList,
  screens: {
    WearScreenId.availabilityInteraction,
  },
  fullPhrases: {
    'список товаров',
    'открыть список',
  },
  fastAliases: {
    'список',
    'товары',
  },
  activationPolicy: VoiceActivationPolicy.immediateExactPartial,
)
```

## Grammar Lifecycle

Do not call `setGrammar()` on every route change. Doing so can delay
recognition, reset an in-progress phrase, conflict with the Vosk queue, and
complicate recovery.

Build one global grammar when the recognizer is prepared:

```dart
final Set<String> voskGrammar = {
  for (final action in catalog.actions) ...action.fullPhrases,
  for (final action in catalog.actions) ...action.fastAliases,
};
```

Resolve the meaning of recognized text after recognition, using the active
screen. For example, `печать` may open the print section in a menu, start a
print on a confirmation screen, or be no command on another screen.

## Segment Context

Capture the actual GoRouter screen at segment creation, not at final-result
arrival. Never use an optimistic pending navigation target.

```dart
class VoiceSegmentContext {
  const VoiceSegmentContext({
    required this.captureEpoch,
    required this.segmentId,
    required this.actualScreen,
    required this.catalogRevision,
  });

  final int captureEpoch;
  final int segmentId;
  final WearScreenId actualScreen;
  final int catalogRevision;
}
```

All partial and final results for the segment resolve against this same
`actualScreen`. This prevents a phrase started in a menu from receiving a
different meaning after an early navigation transition.

## Arbitration Policy

### Safe Grammar Alias

When a grammar partial exactly matches a unique `fastAlias` for the segment's
screen and the entry policy is `immediateExactPartial`:

1. Execute the command immediately.
2. Mark the segment as `claimedByFastCommand`.
3. Clear its sibling free-text preview.
4. Suppress sibling free-text final results.
5. Suppress the grammar final for the same command.

This restores fast handling of `прямое`.

### Alias From Another Screen

If an alias is not registered for the segment's screen, it is not a command.
Do not claim the segment: free-text must remain eligible, because the word can
be part of a product name.

### Ambiguous Alias

An alias must resolve to no more than one action on one screen. Validate the
catalog at startup:

```dart
VoiceActionCatalogValidationResult validateForScreen(
  WearScreenId screen,
);
```

Duplicate aliases for one screen must fail a test or produce an explicit
diagnostic log. They must never be executed immediately.

### Safe and Risky Actions

`immediateExactPartial` is appropriate for mode selection and movement, for
example: `прямое`, `список`, `вверх`, `вниз`, opening a menu section, and tab
switching.

`finalOnly` is appropriate for side-effecting or irreversible operations, for
example: printing, saving, clearing, finishing, switching the user, filling a
database, confirming an operation, selecting a product with navigation, and
going home.

Policy belongs to `VoiceActionEntry`, not globally to `WearVoiceCommand`. For
example, `печать` may open a section immediately in a menu but must wait for a
final result when it begins actual printing.

### Different Final After Early Execution

One segment can produce at most one executed action. If a safe alias was
already executed and final grammar resolves to a different command, do not run
the second command. Record correction telemetry:

```text
[VoiceArbiter]
segment=18
earlyCommand=up
finalCommand=down
decision=keep_early_command
```

This is acceptable only for entries explicitly marked
`immediateExactPartial`. Risky actions remain `finalOnly`.

## Free-Text Policy

Free-text partial results are preview-only. They may display recognized text or
temporarily highlight a unique candidate, but they must not mutate committed
state.

Separate the streams:

```dart
Stream<VoiceSearchPreview> previewStream;
Stream<ResolvedVoiceIntent> committedIntentStream;
```

Keep separate state:

```dart
int? previewFocusedIndex;
int committedFocusedIndex;
```

Free-text partial must not change the committed focus, navigate to an item,
show `Not found`, start an API request, or publish a final glasses payload.

If grammar claims the segment, clear the preview. If no command is found, the
free-text final result is committed only after the grammar lane closes.

## Priority and States

Priority for each `(captureEpoch, segmentId)`:

1. Safe exact fast alias for the captured screen.
2. Full grammar command.
3. Free-text final.

```dart
enum VoiceSegmentDecision {
  pending,
  claimedByFastCommand,
  claimedByFinalCommand,
  committedAsFreeText,
  discarded,
}
```

Algorithm:

```text
grammar partial:
  exact fast alias for captured screen?
    yes -> execute once and claim segment
    no  -> wait

free-text partial:
  publish preview only

grammar final:
  already claimed?
    yes -> do not repeat
    no and command found -> execute and claim

free-text final:
  retain candidate; do not publish until grammar lane is closed

segment ended:
  command claimed -> discard free-text candidate
  command absent  -> publish free-text final
```

## Layer Boundaries

`SpeechRecognitionService` must remain responsible only for:

```text
PCM -> Vosk -> SegmentedRecognitionResult
```

Its result should provide `captureEpoch`, `segmentId`, `lane`, `kind`, `text`,
and `lastChunkId`. Resolving `text + active screen -> VoiceActionEntry` belongs
to `WearVoiceControlService` or `RecognitionArbiter + VoiceActionResolver`.

Do not make the low-level audio service depend on GoRouter or UI state. Consider
removing `parsedCommand` from `SegmentedRecognitionResult` after resolution has
moved to the control layer.

## Reliability Requirements

- Drop all results from an old `captureEpoch`.
- If one Vosk lane fails, close and clean up the segment deterministically.
- Keep maximum segment duration and bounded lane-close timeout.
- Preserve T2151 VAD checks: aliases cannot help if quiet speech does not create
  a segment.
- Do not reintroduce a fixed `silencePeakThreshold = 0.015` endpoint rule; it
  was unsuitable for quiet T2151 speech.

## Required Tests

- `прямое` immediately opens direct scan on the mode-selection screen.
- `прямое сканирование` does not execute a second time after early `прямое`.
- `прямое` on another screen does not execute a foreign command.
- An alias from another screen does not block normal free-text.
- `список` opens a list only where registered.
- `печать` in a menu opens the print section according to its configured policy.
- `печать` on a screen that starts real printing follows its `finalOnly` policy.
- Two actions on one screen cannot have the same fast alias.
- Free-text partial does not change committed focus.
- Grammar claim clears the free-text preview.
- `прошлая страница` does not create a product search for `прошлое`.
- A free-text partial arriving before grammar command causes no side effect.
- Partial and final of the same command cause one action.
- Partial of one command and final of another cause at most one action and emit a correction log.
- A full product request without a command reaches search.
- A command followed by a separate phrase has different segment IDs.
- A stale capture epoch cannot execute a command.
- Grammar-lane failure does not release free-text as though no command could exist.
- Endpointing works with different PCM buffer sizes.
- Quiet T2151 speech reliably creates a segment.
- After 30-50 repetitions of `прямое`, there are no duplicate transitions or false searches.
