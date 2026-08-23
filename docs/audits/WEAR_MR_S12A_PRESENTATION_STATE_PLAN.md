# MR-S12A: Aggregate clarification and status ownership

Дата: 2026-08-24.

## 1. Контекст

- Integration/base branch: `experiment/aligned-audio-frontend` after MR-S11.
- Work branch: `refactor/wear-runtime-presentation-state`.
- Canonical architecture: `ADR-0001-WEAR_SINGLE_STATE_OWNER.md` and
  `ADR-0002-WEAR_STORE_EXECUTION_ORDER.md`.

MR-S10 transferred simple focus ownership. MR-S11 made aggregate logical
navigation authoritative for route/scanner/voice/barcode attribution and removed
business `enterScreen()` from production widgets.

The remaining presentation business values still live in controller/widget
compatibility state:

- voice clarification arguments, focused item and notice;
- generic status arguments, completion target and auto-transition timer;
- status route data copied through `WearFlowState.currentStatusArgs`;
- clarification glasses projection assembled from controller state;
- nested clarification context updated through a compatibility `enterScreen()`
  bridge.

These values can change navigation, voice grammar and what both phone and glasses
show, so they are not local widget state.

## 2. Goal

Introduce one aggregate presentation slice which owns:

```text
focus by logical screen
voice clarification context/focus/notice
generic status args/completion/deadline identity
```

All mutations use typed intents through the existing serialized store.

Phone and glasses read the same committed presentation snapshot. Controller and
widget code may retain read-only adapters during this MR, but no longer owns or
times these values.

## 3. Ownership ledger

| Value | Owner before | Owner after | Temporary view | Removal |
|---|---|---|---|---|
| Simple screen focus | Aggregate focus slice | Aggregate presentation slice | controller projection | S12B |
| Clarification args/history | `WearFlowState` + widget `_currentArgs` | Aggregate presentation slice | widget selector | S12B |
| Clarification focus | controller/widget | Aggregate presentation slice | widget render cache only | S12B |
| Clarification notice | controller/widget timer | Aggregate presentation slice | widget text selector | S12B |
| Generic status args | controller `_statusState` / route extra | Aggregate presentation slice | status screen selector | S12B |
| Status completion/deadline | controller timer/generation | Aggregate status operation | none | this MR |

## 4. State model

`WearRuntimePresentationSlice` extends the existing focus contract so already
wired semantic focus handling remains source-compatible.

It contains immutable fields:

```text
focusedIndices
clarification: VoiceClarificationArgs?
clarificationFocusedIndex
clarificationNotice
status: WearStatusScreenArgs?
statusCompletion: WearStatusCompletion?
statusOperationId: int?
statusDeadline: DateTime?
```

Collections and clarification match lists must be frozen or use already immutable
domain models.

The slice may be lazily upgraded from `WearPresentationFocusSlice`; this avoids a
second root and keeps older aggregate snapshots readable.

## 5. Typed intents

Add:

```text
WearVoiceClarificationContextChanged
WearVoiceClarificationFocusChanged
WearVoiceClarificationNoticeChanged
WearVoiceClarificationCleared
WearGenericStatusShown
WearGenericStatusElapsed
WearGenericStatusCleared
```

Every timer/result intent carries:

```text
sessionEpoch
operationId
expectedScreen
```

A status elapsed result is accepted only when epoch, operation ID, logical status
screen and expected completion still match.

## 6. Effect boundary

Reducer commits status plus expected operation identity before scheduling an
injectable delay effect.

```text
show status intent
 -> commit status/pending operation
 -> project phone/glasses
 -> schedule delay
 -> elapsed result intent
 -> reducer commits return navigation
```

No widget/controller `Timer` may perform business navigation.

Status with `stay` or no delay schedules no transition effect.

## 7. Clarification contract

Ambiguous phrase handling must atomically commit clarification context before
requesting logical navigation to `voiceClarification`.

Nested narrowing and previous-context restoration dispatch typed context intents;
widget attachment does not create or restore business state.

Voice grammar, phone items and glasses items derive from the same aggregate
clarification context and focus.

A selected item is admitted only against the current context revision/source-list
revision.

## 8. Implementation slices

1. Add aggregate presentation model/intents/reducer/effect executor.
2. Preserve existing semantic focus behavior through the new slice subtype.
3. Wire reducer/effect through the root authority.
4. Move clarification projection into `WearRuntimeProjection`.
5. Move status projection and auto-transition into aggregate.
6. Convert controller methods to typed dispatch façades.
7. Convert clarification/status widgets to aggregate selectors and render caches.
8. Add source and reducer/effect regression specifications.
9. Update canonical docs and review exact PR HEAD.

## 9. Tests/specifications

- focus survives lazy slice upgrade;
- clarification context/focus/notice is immutable and aggregate-owned;
- nested clarification and back history preserve one context chain;
- stale clarification update after screen/epoch change is rejected;
- phone/glasses clarification parity;
- status committed before delay starts;
- `stay` status schedules no delay;
- stale elapsed success/error after epoch/screen/operation change is rejected;
- status completion produces one aggregate navigation transition;
- widgets contain no business timer or clarification state restoration;
- controller contains no `_statusTimer`, `_statusGeneration` or writable
  clarification context after transfer.

## 10. Scope exclusions

- physical removal of all remaining `WearFlowState` fields and stream — S12B;
- deletion of temporary aggregate presentation façade — S12B;
- auth repository/protocol changes;
- UAC4/PCM/native scanner changes;
- process-death persistence;
- Flutter/analyzer/Gradle/build/device execution.

## 11. Stop/revert

Stop or split if:

- reducer must access `BuildContext` or router;
- timer starts before expected operation identity is committed;
- aggregate and controller both remain writable for the same value;
- clarification projection requires mutable widget collections;
- status migration changes printer/scan/availability repository behavior.

Rollback reverts the whole ownership transfer; it must not introduce dual write.
