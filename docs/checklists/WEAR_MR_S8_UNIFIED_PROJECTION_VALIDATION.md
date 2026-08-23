# Wear MR-S8 Unified Projection Validation

## Scope

MR-S8 makes committed `WearRuntimeState` the only production source for phone
selectors and glasses projection. Final compatibility deletion remains MR-S9.

## Ownership

- [x] `WearRuntimeProjection` reads one committed aggregate snapshot.
- [x] Phone and glasses use the same focus, items and status values.
- [x] Production has one glasses sender: `WearRuntimeGlassesSender`.
- [x] `WearFlowController` payload caches and feature callbacks are not a
  production projection source; they remain compatibility surfaces for MR-S9.
- [x] Projection and transport failures cannot dispatch business intents.

## Version Contract

- [x] Full envelope contains `schemaVersion`, `sessionEpoch`, `stateRevision`,
  `logicalScreen`, `payload` and `overlay`.
- [x] Receiver ordering compares `(sessionEpoch, stateRevision)`.
- [x] Lower/equal revision in one epoch is stale.
- [x] A newer epoch accepts a reset revision and rejects the previous epoch.
- [x] Overlay carries the same epoch/revision and no navigation field.
- [x] Reconnect sends the latest full envelope with `showWearGlasses`.
- [x] Projection reads do not dispatch and do not increment revision.

## Specification Tests

- [x] Screen payload contract and phone/glasses focus parity.
- [x] Deterministic projection and read-without-revision.
- [x] Versioned overlay without alternate navigation ownership.
- [x] Same-epoch stale rejection and new-epoch reset acceptance.
- [ ] Device reconnect acceptance on T2151.
- [ ] Full automated suite, analyzer, Flutter and Gradle checks were not run by
  explicit MR execution constraint.

## S9 Boundary

The mutable `WearSession`, feature runtime facades, screen registration API,
legacy payload helpers and compatibility tests are intentionally retained.
Their final deletion is MR-S9 and must not be folded into this MR.
