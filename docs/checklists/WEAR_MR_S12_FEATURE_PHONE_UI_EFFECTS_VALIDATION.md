# MR-S12 aggregate feature phone UI and bounded effects validation

Дата: 2026-08-24.

## 1. Scope

MR-S12 transfers migrated scan phone rendering and manual barcode input to the
aggregate runtime boundary.

- Base: `experiment/aligned-audio-frontend` at
  `7e7181a16aefaf67e2aa01de2fdae0e3c80ea048`.
- Branch: `refactor/wear-feature-phone-ui-effects`.
- Plan:
  [`docs/audits/WEAR_MR_S12_FEATURE_PHONE_UI_EFFECTS_PLAN.md`](../audits/WEAR_MR_S12_FEATURE_PHONE_UI_EFFECTS_PLAN.md).

## 2. Ownership result

| Value | Authoritative owner | Phone observation/executor |
|---|---|---|
| Scan phase/products/barcode/focus/status | aggregate `WearScanTaskSlice` | pure `WearScanPhoneProjection` |
| Product-select rendering | aggregate scan projection | widget scroll/dialog state only |
| Scan-idle loading | aggregate scan projection | widget rendering only |
| Manual input request | aggregate `WearUiEffectSlice` | scan-idle sends typed request |
| Manual input execution | claimed exact UI effect | current Flutter route executor |
| Manual input result | aggregate effect completion | value returns as typed result, not controller barcode callback |
| Scan status | aggregate scan status | route args retained only for non-scan compatibility status |

## 3. Pure scan phone projection

`WearScanPhoneProjection.fromState()` reads exactly one immutable
`WearRuntimeState` and exposes:

- version tuple;
- logical screen;
- scan phase;
- barcode;
- immutable products;
- normalized committed focus;
- product name;
- typed status;
- loading text/icon derived from phase.

Projection read does not dispatch, publish, cache or advance revision.

## 4. Product-select contract

`WearProductSelectScreen`:

- subscribes to `WearRuntimeAuthority.states`;
- does not import `wear_scan_runtime.dart`;
- does not read `WearProductSelectArgs` or `widget.args`;
- renders product/barcode/focus from the aggregate projection;
- sends focus/select to typed authority APIs;
- verifies a tapped product against the current committed list by stable ID;
- updates local focus only after an aggregate state event;
- keeps only scroll position and dialog lifetime as UI-local state.

The phone route no longer constructs product-select from business route extras.
Any still-emitted legacy `extra` is ignored and cannot override aggregate data;
its producer is removed with the final scan compatibility adapter cleanup.

## 5. Scan-idle and manual input effect

`WearScanIdleScreen` observes aggregate scan phase and has no
`WearScanRuntimeState` stream or `_isManualInputOpen` business flag.

Manual input flow:

```text
requestUiEffect(manualBarcodeInput)
  -> one pending effect per kind
  -> current scan-idle widget sees pending effect
  -> exact effect claim
  -> phone input route
  -> complete(value) or cancel
  -> exact effect removed
  -> non-empty value enters reviewed scan barcode reducer
```

Admission rules:

- pending effect is deferred while phone UI is inactive;
- only current scan-idle route claims it;
- rebuild cannot re-open a claimed effect;
- completion requires claimed status and current epoch/screen;
- screen/epoch drift rejects completion; cancel may retire stale UI work;
- empty/cancel retires the effect without scan mutation;
- non-empty accepted value preserves scan reducer effects and operation identity;
- repeated request is rejected as duplicate while any effect of the kind exists.

## 6. Status and route boundary

`WearStatusScreen` gives aggregate scan status precedence whenever:

- logical screen is `status`;
- scan phase is `WearScanTaskPhase.status`;
- aggregate status is present.

Route `WearStatusScreenArgs` remains only for generic/non-scan compatibility
flows. Scan-idle and product-select route builders no longer require printer,
product or barcode snapshots in `GoRouterState.extra`.

## 7. Regression specifications

`test/wear_runtime_feature_phone_ui_effects_test.dart` specifies:

- projection purity and immutable products;
- bounded duplicate UI-effect admission;
- inactive-phone claim rejection;
- claim + completion -> one lookup operation;
- cancel/empty result -> no lookup;
- old-epoch completion rejection;
- absence of feature streams and route snapshots in migrated scan widgets;
- no optimistic product focus cache mutation;
- aggregate status precedence.

## 8. Review gates

- no new mutable feature stream or singleton;
- no direct widget `wearFlowController.handleBarcode` manual path;
- no route args as scan phone owner;
- no completion before claim;
- exact epoch/effect/screen checks remain intact;
- effect removal and scan transition are one reducer result;
- scan lookup effects are not lost when UI effect is removed;
- phone/glasses read the same scan task;
- no UAC4/native/scanner protocol or repository changes;
- no generated/build artifacts.

## 9. Remaining compatibility boundary

Intentionally deferred:

- legacy transient voice-search payload/status methods;
- voice clarification args/focus/notice;
- physical `WearFlowState` and aggregate presentation facade removal;
- generic non-scan status route args;
- guarded anonymous badge auth callback.

These are MR-S13/MR-S14. Final gates/docs are MR-S15.

## 10. Validation limitation

Performed: source, diff, call-graph, type/signature and reducer-order review.

Not performed by owner instruction:

- Flutter/Dart analyzer;
- Flutter tests;
- Gradle/APK/build;
- emulator/device/hardware checks.

Committed tests are executable specifications for later owner-run validation, not
claims of a completed runtime run.
