# MR-S11 aggregate route observation validation

Дата: 2026-08-24.

## 1. Scope

MR-S11 отделяет authoritative logical navigation от Flutter route attachment и
переводит module orchestration на committed `WearRuntimeState`.

- Base branch: `experiment/aligned-audio-frontend`.
- Base commit: `7f9e0deafc4633c51ee4b77f70794044fe44e4cc`.
- Work branch: `refactor/wear-runtime-route-observation`.
- Plan: [`docs/audits/WEAR_MR_S11_ROUTE_OBSERVATION_PLAN.md`](../audits/WEAR_MR_S11_ROUTE_OBSERVATION_PLAN.md).

## 2. Ownership result

| Value/decision | Authoritative owner after MR | Retained compatibility |
|---|---|---|
| Logical business screen | Aggregate `WearNavigationSlice.logicalScreen` | `WearFlowState.screen` remains derived/temporary until MR-S12 |
| Actual Flutter route | Aggregate `actualPhoneScreen` through epoch-bound observation | local route string/screen cache is host diagnostics only |
| Barcode source screen | Captured aggregate logical screen | unsupported semantic barcode may call guarded legacy handler until auth migration in MR-S12 |
| Barcode source epoch | Captured aggregate `sessionEpoch` | none |
| Voice screen provider | Aggregate logical screen | screen action registry remains capability wiring |
| Scanner orchestration | Aggregate snapshot + handler/runtime capability | base controller capability getter is compatibility-only |
| Widget attachment | Observation/rendering and UI action registration | no business `enterScreen()` under `lib/modules/wear/presentation` |
| Canonical glasses payload | `WearRuntimeProjection.projectGlasses()` | transient compatibility overlay remains until MR-S12 |

## 3. Route observation contract

`WearModuleApp` no longer subscribes to `WearFlowController.stateStream` and does
not read `flow.state.screen`.

Router changes follow this order:

```text
Flutter route change
  -> captured route observation generation
  -> epoch-bound PhoneRouteObserved
  -> committed actualPhoneScreen
  -> scanner/voice host synchronization
  -> matching pending request acknowledgement
```

The router does not call `flow.observeRoute()` and cannot invoke feature entry,
load, print, photo, selection reset or logical navigation.

A phone route may lag aggregate logical state. Voice grammar and screen-off
scanner orchestration are updated on aggregate logical transitions independently
of widget construction.

## 4. Barcode boundary

`WearBarcodeDispatcher` receives `WearRuntimeAuthority` directly.

At admission it captures from one committed snapshot:

- `sessionEpoch`;
- `logicalScreen`;
- epoch-bound `WearRuntimeControlAdapter`;
- monotonic delivery ID.

Both scanner delivery acceptance and semantic barcode dispatch use that same
captured epoch/screen. A queued callback cannot be re-labelled as input for a
newer session or screen.

The unsupported semantic fallback is deliberately bounded:

- only `WearDispatchRejectReason.unsupported` may fall back;
- current epoch and logical screen must still equal the captured values;
- stale, duplicate, busy and terminal receipts never bypass aggregate admission;
- production uses it for the still-legacy pre-auth badge handler;
- MR-S12 replaces it with aggregate-owned auth effect/state.

## 5. Pre-auth scanner repair

The previous aggregate control policy accidentally made badge authorization
impossible before a session existed, despite the retained product contract and
legacy policy tests.

MR-S11 adds two narrow reducers:

- `WearPreAuthLifecycleReducer`: anonymous runtime may become active only on
  logical `main`;
- `WearPreAuthScannerAdmissionReducer`: scanner admission is allowed only when
  logical and actual screens are both `main`, phone UI is active, hardware is
  prepared and the registered screen capability accepts barcode.

Anonymous runtime activation on `scannerConnect`, settings or any other screen
remains rejected.

Authorization advances the epoch and resets scanner controls through the existing
feature-epoch reducer. Old route/scanner adapters are then stale by construction.

## 6. Widget lifecycle cleanup

Production files under `lib/modules/wear/presentation` no longer call
`.enterScreen(`.

Removed lifecycle business entry from:

- main/auth;
- menu;
- home confirmation;
- continue scan;
- availability interaction;
- help;
- status;
- settings;
- DB settings;
- Wi-Fi settings;
- printer settings;
- voice clarification attachment.

The widgets may still register UI action callbacks, subscribe to aggregate
projection, create local controllers and execute UI-only work.

Help, status and auth widgets no longer publish canonical glasses payloads.

Voice clarification still uses a bounded compatibility bridge when its nested
argument/history context changes after a semantic clarification action. Initial
widget attachment does not invoke the bridge. Ownership of clarification
arguments/focus/notice moves in MR-S12.

## 7. Regression specifications

Added:

- `test/wear_runtime_route_observation_boundary_test.dart`;
- `test/wear_pre_auth_runtime_contract_test.dart`.

They specify:

- route observation cannot change logical screen;
- route/scanner adapters from an old epoch are rejected;
- pre-auth matching `main` route prepares and admits badge scanner;
- route drift closes pre-auth admission;
- anonymous runtime activation is allowed only on `main`;
- presentation Dart sources cannot call `.enterScreen(`;
- module orchestration cannot read controller screen/state stream or call
  `flow.observeRoute()`;
- barcode/voice production wiring captures aggregate screen and epoch;
- help/status/auth widgets cannot publish canonical glasses payload.

Existing `test/wear_scanner_runtime_policy_test.dart` remains the behavioral
contract for pre-auth, active-route, background and terminal decisions.

## 8. Static review gates

Review must verify on the exact PR HEAD:

- no source under `lib/modules/wear/presentation` contains `.enterScreen(`;
- `WearModuleApp` has one aggregate state subscription and no flow-state
  subscription;
- route observation and ACK use an epoch-bound adapter;
- route observation never calls feature/runtime entry;
- scanner and voice synchronize on aggregate logical transitions;
- barcode delivery and semantic dispatch share captured epoch/screen;
- only unsupported semantic barcode can reach compatibility fallback;
- pre-auth scanner requires logical=actual=`main`;
- non-main anonymous activation remains rejected;
- help/status/auth glasses payloads come from aggregate projection;
- no UAC4/PCM/native protocol/repository changes are present;
- S12 work is not falsely claimed complete.

## 9. Validation performed

Performed:

- complete changed-file and call-graph inspection;
- source/type/signature consistency review by reading;
- logical/actual route ordering analysis;
- epoch and queued-barcode analysis;
- widget lifecycle repository audit;
- regression specification review.

Not performed by explicit owner constraint:

- `flutter test`;
- `flutter analyze` / `dart analyze`;
- Gradle;
- APK/build;
- emulator/device/hardware validation.

This is static review evidence. Executed tests and device acceptance remain
release gates.

## 10. Follow-up boundary

MR-S12 must remove the remaining writable compatibility business state:

- `WearFlowState` focus/clarification/navigation/task/status copies;
- temporary `WearAggregatePresentationFlowController` focus mirror;
- controller status/transient business timers and payload path;
- legacy auth barcode fallback;
- clarification argument/focus/notice ownership;
- remaining controller screen decisions.

Final repository gates and canonical audit update follow in MR-S13.
