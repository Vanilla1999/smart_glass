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
`commitPresentationFocus()` first dispatches `WearSemanticInputKind.presentationFocus`
and only after an accepted receipt reflects the committed value into the retained
legacy controller fields.

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

## 4. Input parity

The aggregate-first facade handles:

- touch focus and touch selection;
- voice `up`, `down`, `select`;
- hardware/button `up`, `down`, `select`;
- menu direct section commands through overridden select methods;
- availability list/direct-scan commands through overridden select methods;
- continue-scan `continueScan`/`finish`;
- home-confirm `yes`/`no`/`cancel`.

Focus-dependent navigation reads the committed aggregate value. A rejected or
stale focus receipt prevents the corresponding selection/navigation from
continuing.

## 5. Compatibility and lifecycle boundary

Intentionally retained in this MR:

- `WearFlowState` presentation fields as read-only compatibility view;
- the old controller state stream for consumers outside the four scoped screens;
- widget `enterScreen()` lifecycle calls;
- direct route compatibility behavior;
- status and voice-clarification presentation paths.

Planned follow-ups:

- MR-S11 removes business `enterScreen()` from widget lifecycle;
- MR-S12 removes presentation fields, aggregate no-op echo and the temporary
  aggregate-first facade;
- final ownership/device gates follow after those migrations.

## 6. Regression specification

Added:

`test/wear_phone_aggregate_projection_test.dart`

It specifies:

- touch commit updates aggregate before compatibility exposure;
- same-focus dispatch is a revision-preserving no-op;
- direct aggregate updates are reflected by the compatibility view;
- stale-screen focus is rejected without navigation;
- voice and hardware buttons share the same aggregate focus;
- scoped widgets cannot import/read legacy presentation state;
- production DI uses the aggregate-first facade.

## 7. Static review gates

The PR review must verify on the exact reviewed HEAD:

- no unrelated audio/native/scanner/repository changes;
- item bounds are menu `4`, other scoped screens `2`;
- select awaits an accepted focus receipt where it supplies a new index;
- authority subscription cannot loop because compatibility echo is same-value;
- compatibility subscription is cancelled before authority/controller disposal;
- phone and glasses projection both read `WearPresentationFocusSlice`;
- no scoped widget subscribes to `WearFlowController.stateStream`;
- no scoped widget manually publishes a second focus payload to glasses;
- `enterScreen()` is still present and is not falsely claimed as completed.

## 8. Validation performed for this MR

Performed:

- complete source and GitHub diff inspection;
- type/signature/reference consistency review by reading code;
- changed-file scope review;
- regression test specification review.

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

## 9. Review record

PR number, reviewed HEAD, review findings, review-fix commits and merge SHA are
recorded in the PR discussion and must be added here only after those immutable
values exist.
