# MR-S11 aggregate route observation validation

Дата: 2026-08-24.

## 1. Scope

MR-S11 отделяет authoritative logical navigation от Flutter route attachment и
переводит module orchestration на committed `WearRuntimeState`.

- PR: [#16](https://github.com/Vanilla1999/smart_glass/pull/16).
- Base branch: `experiment/aligned-audio-frontend`.
- Base commit: `7f9e0deafc4633c51ee4b77f70794044fe44e4cc`.
- Work branch: `refactor/wear-runtime-route-observation`.
- Plan: [`docs/audits/WEAR_MR_S11_ROUTE_OBSERVATION_PLAN.md`](../audits/WEAR_MR_S11_ROUTE_OBSERVATION_PLAN.md).
- Review record: [`docs/audits/WEAR_MR_S11_REVIEW_FINDINGS.md`](../audits/WEAR_MR_S11_REVIEW_FINDINGS.md).

## 2. Ownership result

| Value/decision | Authoritative owner after MR | Retained compatibility |
|---|---|---|
| Logical business screen | Aggregate `WearNavigationSlice.logicalScreen` | `WearFlowState.screen` remains a temporary derived mirror until MR-S12 |
| Actual Flutter route | Aggregate `actualPhoneScreen` through epoch-bound observation | local route cache is host diagnostics only |
| Barcode source screen/epoch | One captured aggregate snapshot | guarded anonymous-main fallback only |
| Voice screen/admission | Aggregate logical screen | screen action registry remains capability wiring |
| Scanner orchestration | Aggregate snapshot + capability valid for the same logical screen | facade fails closed on mirror drift |
| Widget attachment | Observation/rendering and UI action registration | no business `.enterScreen(` under production presentation |
| Canonical glasses payload | `WearRuntimeProjection.projectGlasses()` | transient compatibility overlay remains until MR-S12 |

## 3. Route observation contract

`WearModuleApp` no longer subscribes to `WearFlowController.stateStream` and does
not read controller screen for business attribution.

```text
Flutter route change
  -> captured route observation generation
  -> epoch-bound PhoneRouteObserved
  -> committed actualPhoneScreen
  -> scanner/voice host synchronization
  -> matching pending request acknowledgement
```

The router does not call feature entry. A route may lag aggregate logical state;
scanner and voice are configured from the aggregate transition independently of
widget construction.

## 4. Barcode, voice and scanner boundary

`WearBarcodeDispatcher` captures `sessionEpoch + logicalScreen` from one committed
snapshot. Delivery receipt and semantic barcode dispatch use exactly this pair.
Queued input cannot be re-labelled as belonging to a newer session or screen.

Fallback after `unsupported` is accepted only when all are true:

- runtime remains anonymous;
- captured/current screen is `WearScreenId.main`;
- epoch and screen are still current;
- rejection is `unsupported`, never stale/duplicate/busy/terminal.

`WearVoiceApplicationDispatcher` uses aggregate logical navigation for command,
phrase, preview, delay and admission context. It no longer reads
`_flow.state.screen`.

The temporary production facade rejects barcode, voice, phrase and hardware
callbacks whenever retained controller screen differs from aggregate logical
screen. This is fail-closed protection until MR-S12 physically removes the mirror.

## 5. Pre-auth and logout contract

Badge scanner before authorization is the only anonymous runtime exception:

- logical and actual screens must both be `main`;
- phone UI and bounded runtime must be active;
- scanner hardware must be prepared;
- registered main capability must accept barcode.

Logout advances epoch, resets feature/control state, publishes pending
replace-to-main navigation and keeps the bounded pre-auth runtime active.
Compatibility reset explicitly reprojects aggregate `main`; it cannot revert the
business screen to the old controller initial value.

## 6. Widget lifecycle cleanup

Production files under `lib/modules/wear/presentation` no longer invoke business
`.enterScreen(`. Widgets may subscribe, register UI actions and execute UI-only
work, but cannot start feature load/print/photo/navigation merely because they
were built.

Help, status and auth widgets no longer publish canonical glasses payloads.
Voice clarification retains only a bounded argument/focus/notice bridge after an
actual semantic clarification action; attachment itself is observation-only.

## 7. Regression specifications

- `test/wear_runtime_route_observation_boundary_test.dart`;
- `test/wear_pre_auth_runtime_contract_test.dart`;
- `test/wear_business_navigation_source_gate_test.dart`.

They specify route/logical separation, old-epoch rejection, bounded pre-auth
scanner, widget lifecycle restrictions, aggregate route sources, direct-route
prohibitions, logout pending navigation and source-level voice/barcode guards.

## 8. Review record

Initial reviewed HEAD:

`4afebb0eac50ca4311c9afe18821889d00d55075`.

Initial verdict: `REQUEST CHANGES`.

Blocking findings and review-fix commits are recorded in
`WEAR_MR_S11_REVIEW_FINDINGS.md`. Final review is anchored to the exact final HEAD
in the PR discussion before merge.

## 9. Remaining compatibility boundary

MR-S11 does **not** claim physical deletion of:

- `WearFlowController._state` / `WearFlowState`;
- status/transient timers and payload compatibility;
- clarification args/focus/notice compatibility;
- temporary aggregate presentation facade;
- guarded pre-auth auth handler.

Those are MR-S12. Final ownership gates and canonical audit are MR-S13.

## 10. Validation performed

Performed:

- full changed-file and call-graph inspection;
- exact-head route/scanner/barcode/voice ordering review;
- epoch and queued-input analysis;
- widget lifecycle repository audit;
- source/type/signature review by reading;
- review-fix and second full-diff review.

Not performed by explicit owner constraint:

- Flutter tests or analyzer;
- Dart analyzer;
- Gradle/APK/build;
- emulator/device/hardware validation.

This is static review evidence; executed host/device validation remains a release
gate.
