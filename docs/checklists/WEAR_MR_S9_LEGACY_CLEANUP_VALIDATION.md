# Wear MR-S9 Legacy Cleanup Validation

## Scope

MR-S9 removes writable migration facades after the aggregate
`WearRuntimeAuthority` became authoritative. `WearDependencies.authority` owns
the one production `WearRuntimeStore`; phone and glasses remain projections of
its committed snapshots.

## Ownership

- [x] Mutable/static `WearSession` was deleted.
- [x] Production feature runtimes receive the root authority explicitly.
- [x] The duplicate `WearActualScreenStore` route owner was deleted.
- [x] Session authorization and clearing are observed from aggregate states.
- [x] Migrated widgets do not call business `enterScreen()`.
- [x] Migrated scan and availability business callback registrations were
  removed; bounded manual-input UI remains an adapter to semantic intents.
- [x] Hard-coded migrated-screen update exceptions were removed.
- [x] The duplicate payload-based `WearRuntimeStore` implementation was deleted.
- [x] `WearFlowController` no longer owns a per-screen payload cache; glasses
  payloads are projected from the aggregate runtime snapshot.
- [x] `WearStatusIconReporter` observes status only and does not call the
  glasses bridge or trigger projection delivery.
- [x] Obsolete `FlutterWearGlassesOutput` was deleted; production glasses
  transport is owned exclusively by `WearRuntimeGlassesSender`.

## Static Gates

- [x] `wear_runtime_legacy_ownership_search_test.dart` rejects retired writable
  owner names and migrated widget business-entry calls.
- [x] Repository search finds no production `WearSession` or
  `WearActualScreenStore` reference.
- [x] The ownership ledger contains no temporary writable owner.
- [x] Static ownership search rejects duplicate runtime stores, controller
  payload caches, reporter transport calls and the obsolete Flutter output.
- [ ] Automated tests, analyzer, Flutter, Gradle and build commands were not run
  by explicit MR execution constraint.
- [ ] T2151 hardware acceptance remains a device gate.

## Final Ownership Ledger

| Value | Writable owner | Consumers |
|---|---|---|
| session and identity | `WearRuntimeStore` session slice | selectors and lifecycle adapters |
| logical and actual route | `WearRuntimeStore` navigation slice | router output and route observer |
| printer task | `WearRuntimeStore` printer slice | printer effects and phone/glasses selectors |
| scan/print/status task | `WearRuntimeStore` scan slice | scan effects and phone/glasses selectors |
| availability task | `WearRuntimeStore` availability slice | availability effects and phone/glasses selectors |
| controls and UI effects | `WearRuntimeStore` control/UI slices | hardware and bounded UI adapters |

## Retained Adapters

- `WearFlowController` remains the command, router and bounded UI-effect adapter
  for screens not yet represented by a dedicated selector. It is not an
  independent aggregate store.
- Feature runtime classes remain effect executors and read projections while
  existing widgets are converted to direct selectors. Production wiring always
  supplies the root authority; optional authorities remain only for isolated
  unit construction.
- The legacy glasses output port remains connected to a no-op production sink
  for compatibility. The production transport owner is exclusively
  `WearRuntimeGlassesSender`.
- Voice, scanner, navigation and MethodChannel adapters remain because they own
  external resources or transport, not business state.
