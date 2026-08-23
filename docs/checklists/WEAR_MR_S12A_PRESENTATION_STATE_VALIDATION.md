# MR-S12A aggregate presentation state validation

Дата: 2026-08-24.

## Scope

MR-S12A transfers the remaining navigation-affecting presentation values into
`WearRuntimeState`:

- voice clarification context/focus/notice;
- generic status args/completion/deadline/operation identity;
- phone/glasses projection of those values.

Plan: [`../audits/WEAR_MR_S12A_PRESENTATION_STATE_PLAN.md`](../audits/WEAR_MR_S12A_PRESENTATION_STATE_PLAN.md).

## Ownership result

| Value | Authoritative owner | Temporary compatibility |
|---|---|---|
| simple focus | `WearRuntimePresentationSlice.focusedIndices` | derived `WearFlowState` view |
| clarification context | aggregate presentation slice | controller mirror for legacy selection internals until S12B |
| clarification focus | aggregate presentation slice | widget render cache only |
| clarification notice | aggregate presentation slice | widget timer may dispatch clear intent only |
| generic status | aggregate presentation slice | route extra derived from aggregate pending state |
| status deadline/result | aggregate operation identity + scheduler adapter | no controller business timer in production path |

## Status ordering

```text
WearGenericStatusShown
 -> validate current epoch/source screen
 -> commit status + expected operation + logical status navigation
 -> publish snapshot
 -> scheduler observes committed deadline
 -> WearGenericStatusElapsed(epoch, operationId)
 -> reducer validates epoch/screen/operation
 -> commit pop/replace target and clear status
```

The scheduler owns only a cancellable host `Timer`; deadline, completion and
operation identity remain in aggregate state.

## Clarification ordering

```text
ambiguous phrase
 -> commit clarification context
 -> request logical clarification navigation
 -> phone/glasses project the same context/focus
 -> nested context/focus/notice typed intents
 -> selection validates current context/list
 -> navigation away clears aggregate clarification state
```

Widget attachment does not construct canonical clarification business state.

## Required static review

- reducer is wired exactly once before core navigation handling;
- session authorization, clear and terminal reset presentation state;
- semantic focus preserves the richer presentation subtype;
- status without deadline/stay does not leave an expected operation;
- stale elapsed result cannot navigate;
- projection prioritizes generic status only when aggregate generic status exists;
- scan status behavior remains unchanged otherwise;
- clarification projection uses one aggregate context/focus/notice;
- route extra for status/clarification is derived from aggregate presentation;
- production façade overrides status/clarification mutation paths;
- controller timer/context fields remain compatibility-only and are removed in
  S12B, not treated as owners.

## Regression specifications

- `test/wear_runtime_presentation_slice_test.dart`;
- source ownership gates added by this MR;
- existing unified projection, status sequencing, voice clarification and
  navigation epoch suites remain applicable.

## Validation limitation

Not run by explicit owner constraint:

- Flutter tests;
- Dart/Flutter analyzer;
- Gradle;
- APK/build;
- emulator/device/hardware checks.

The MR is reviewed statically on its exact GitHub HEAD. Executed evidence remains
an owner release gate.
