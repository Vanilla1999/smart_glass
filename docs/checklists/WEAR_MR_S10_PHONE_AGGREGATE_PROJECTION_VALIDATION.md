# MR-S10 phone aggregate projection validation

Дата: 2026-08-23.

## 1. Scope

MR-S10 переносит writable ownership presentation focus в
`WearPresentationFocusSlice` для четырёх phone screens:

- `menu`;
- `homeConfirm`;
- `continueScan`;
- `availabilityInteraction`.

Base branch: `experiment/aligned-audio-frontend`.

Base commit: `dcaf154552791db8eb6d7a0edc48dc31950635d3`.

PR: [#15](https://github.com/Vanilla1999/smart_glass/pull/15).

Plan:
[`docs/audits/WEAR_MR_S10_PHONE_AGGREGATE_PROJECTION_PLAN.md`](../audits/WEAR_MR_S10_PHONE_AGGREGATE_PROJECTION_PLAN.md).

## 2. Ownership result

| Value | Authoritative writable owner | Compatibility view |
|---|---|---|
| Menu focus | `WearPresentationFocusSlice` | `WearFlowState.menuFocusedIndex` |
| Home-confirm focus | `WearPresentationFocusSlice` | `WearFlowState.homeConfirmFocusedIndex` |
| Continue-scan focus | `WearPresentationFocusSlice` | `WearFlowState.continueScanFocusedIndex` |
| Availability-interaction focus | `WearPresentationFocusSlice` | `WearFlowState.availabilityInteractionFocusedIndex` |

Production DI installs `WearAggregatePresentationFlowController`. Its
`commitPresentationFocus()` first dispatches
`WearSemanticInputKind.presentationFocus` and only after an accepted, current
`sessionEpoch + logicalScreen + committed focus` receipt reflects the value into
the retained legacy controller fields.

The base `WearFlowController._setState()` still contains its historical semantic
focus echo. In production MR-S10 paths that echo can only repeat an already
committed aggregate value and therefore reduces to an accepted no-op. Physical
removal of the echo and the legacy fields remains MR-S12 work.

## 3. Phone projection result

The following widgets read `WearRuntimeProjection.projectPhone()` and subscribe
to `WearRuntimeAuthority.states`:

- `lib/modules/wear/presentation/screens/menu/wear_menu_screen.dart`;
- `lib/modules/wear/presentation/screens/home/wear_home_confirm_screen.dart`;
- `lib/modules/wear/presentation/screens/continue_scan/wear_continue_scan_screen.dart`;
- `lib/modules/wear/presentation/screens/availability/wear_availability_interaction_screen.dart`.

They no longer import `wear_flow_state.dart`, subscribe to
`WearFlowController.stateStream`, or read the four legacy focus fields as their
business source.

Local `_focusedIndex`/`_selectedButtonIndex` values are render caches only. Touch,
voice or button callbacks do not optimistically mutate them; a new value appears
only after an aggregate snapshot is projected back to the widget.

## 4. Input parity

The aggregate-first facade handles:

- touch focus and touch selection;
- voice `up`, `down`, `select`;
- hardware/button `up`, `down`, `select`;
- menu direct section commands through overridden select methods;
- availability list/direct-scan commands through overridden select methods;
- continue-scan `continueScan`/`finish`;
- home-confirm `yes`/`no`/`cancel`.

Focus-dependent navigation reads the requested committed aggregate value. A
rejected, old-epoch, stale-screen or superseded focus receipt prevents the
corresponding selection/navigation from continuing. The normalized requested
index is retained across the await; a later focus input cannot redirect an older
tap to another target.

## 5. Compatibility and lifecycle boundary

Intentionally retained in this MR:

- `WearFlowState` presentation fields as read-only compatibility view;
- the old controller state stream for consumers outside the four scoped screens;
- widget `enterScreen()` lifecycle calls;
- direct route compatibility behavior;
- status and voice-clarification presentation paths.

Planned follow-ups:

- MR-S11 removes business `enterScreen()` from widget lifecycle and makes
  aggregate logical navigation the scanner/input source;
- MR-S12 removes presentation fields, aggregate no-op echo and the temporary
  aggregate-first facade;
- final ownership/device gates follow after those migrations.

MR-S10 therefore closes only the four focus ownership paths. It does not claim
that the whole `WearFlowController` or complete phone presentation layer has
already become stateless.

## 6. Regression specification

Added:

`test/wear_phone_aggregate_projection_test.dart`

It specifies:

- touch commit updates aggregate before compatibility exposure;
- same-focus dispatch is a revision-preserving no-op;
- direct aggregate updates are reflected by the compatibility view;
- stale-screen focus is rejected without navigation;
- a later committed focus supersedes an older pending selection;
- same-screen session-epoch rollover invalidates the older action;
- voice and hardware buttons share the same aggregate focus after real
  authorization;
- scoped widgets cannot import/read legacy presentation state;
- scoped widgets cannot optimistically write local business focus;
- production DI uses the aggregate-first facade.

## 7. First review and fixes

Initial reviewed HEAD:

`cb2ece56fce49c62546123583901f3a8f93a3011`.

The first static review recorded four blocking findings in PR #15:

1. accepted focus was not revalidated against the captured session epoch;
2. continue-scan and availability widgets rendered focus before aggregate
   acceptance;
3. the voice/button test attempted to activate an anonymous runtime and therefore
   could not exercise commands;
4. direct touch selection could use a later aggregate focus rather than the
   requested normalized index.

Review-fix commits:

- `644c7d670c66b37138ce69a2d8a2ab94f05b2276` — captured-epoch and superseded-focus guards plus stable requested selection;
- `bfcf7e0208e6ac589682e6c282db96a84181191a` — continue-scan renders only committed projection;
- `4f6ce83d70b8a3c74cbfdbf5c8133346d24fd382` — availability interaction renders only committed projection;
- `fb528dcb79bbc5e5e7f4f3b5743ea25c29c02f54` — executable authorization setup and concurrency/epoch regression specifications.

The final reviewed HEAD and merge SHA are recorded in the immutable PR discussion
and GitHub merge object. This document intentionally does not predict a future
merge SHA.

## 8. Static review gates

The final PR review verifies on the exact reviewed HEAD:

- no unrelated audio/native/scanner/repository changes;
- item bounds are menu `4`, other scoped screens `2`;
- select awaits an accepted focus receipt where it supplies a new index;
- accepted receipt remains valid for the captured epoch, logical screen and
  requested committed focus;
- a newer focus input cannot redirect or authorize an older selection;
- authority subscription cannot loop because compatibility echo is same-value;
- compatibility subscription is cancelled before authority/controller disposal;
- phone and glasses projection both read `WearPresentationFocusSlice`;
- no scoped widget subscribes to `WearFlowController.stateStream`;
- no scoped widget manually publishes a second focus payload to glasses;
- no scoped widget optimistically changes its focus cache;
- `enterScreen()` is still present and is not falsely claimed as completed.

## 9. Validation performed for this MR

Performed:

- complete source and GitHub diff inspection;
- type/signature/reference consistency review by reading code;
- changed-file scope review;
- concurrency, stale-screen and epoch-bound control-flow review;
- regression test specification review;
- second review after all first-pass findings were fixed.

Not performed, by explicit task constraint:

- `flutter test`;
- `flutter analyze`;
- `dart analyze`;
- Gradle tasks;
- APK build;
- emulator/device/hardware validation.

Therefore this document is static review evidence, not executed compile/test or
device evidence. The added test suite must be run by the repository owner before
production release.
