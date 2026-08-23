# Wear single-state stack merge report

- Integration branch: `experiment/aligned-audio-frontend`
- Post-merge HEAD before this report: `99d8e5b702d19e99c1c8ffb69f9d54309a70933f`
- Review method: static source inspection only

Проверка статическая. Flutter, analyzer, tests, Gradle и builds не запускались.

## Merge ledger

| Stage | PR | Reviewed HEAD | Merge SHA | Findings fixed | Check |
|---|---:|---|---|---|---|
| Architecture | #2 | `d2a3c11b4d4a8ca17a193e6669a2c15bb30917eb` | `dbf16da2ff15095cce1df98c47f6034e849910e8` | Contract consistency | Static |
| MR-S1 | #3 | `aac060c51a94be38fe2934d99f318f05724ddf07` | `2434677e5d7c37081317cdab35ac039b4340eae2` | Fail-closed mirror and observable rejection | Static |
| MR-S2 | #4 | `0075d7d0d40eb3b212f1881e845f7a0809136285` | `b20128d9ea9fe9d49d909228fb526fac39e4ddc9` | Production authority, lifecycle and stale route admission | Static |
| MR-S3 | #5 | `39c556a03ab1eb3d71db5cb25b6ca55573d3d9b6` | `840e8b19022404e40132c7a232af3790c146bc27` | Production controls and scanner supersession | Static |
| MR-S4 | #6 | `4a533ee6f28a035e41c2afbcd0a2e955e91c8a39` | `5ca7382a5cf5e10c5f56039f0654ecc1df3ede36` | Printer authority retained through parent fixes | Static |
| MR-S5 | #7 | `e7c43c29f4975d1adfaca7eea38091dfe32ed389` | `064cd928ed5526c79c9b2caf51fda4de405a98f6` | Missing DTO and monotonic scan IDs | Static |
| MR-S6 | #9 | `808fecb9dbe14b1bb0c633432af889f16905d474` | `0af51a1f3a9b04bb10b6d3ad096a2546008fb18a` | Monotonic availability IDs and typed route extra | Static |
| MR-S7 | #10 | `94843ad69d02da8a566e8a111a75b432b54d5c36` | `90155f87b0d94cd707f6d737d10011f20655f4d3` | Deferred UI effects, focus authority and cleanup | Static |
| MR-S8 | #11 | `e777e8389662c5ee130e6c12136d8e807542d05e` | `a6688567ccab2ee9fc4f03c6511d5ee5ccec71a5` | Aggregate focus projection and one sender | Static |
| MR-S9 | #12 | `afd5f526b786654cedbdc29e1ff5b2a9853275d3` | `99d8e5b702d19e99c1c8ffb69f9d54309a70933f` | Removed duplicate owners, store, cache and sender | Static |

PR #8 was a superseded duplicate of MR-S2 and was closed without merge. Baseline stabilization PR #1 was already merged before this stack.

## Final ownership

| Value | Writable owner |
|---|---|
| Session identity and lifecycle | Aggregate session/lifecycle slices |
| Logical navigation, history and pending request | Aggregate navigation slice |
| Actual phone route | Aggregate navigation observation |
| Voice, scanner and connectivity | Aggregate control slices |
| Printer state and selection | Aggregate printer slice |
| Scan, print and status | Aggregate scan slice |
| Availability flow | Aggregate availability slice |
| Semantic inputs and UI effects | Aggregate semantic/UI-effect reducers |
| Phone and glasses projection | Pure projection of one committed snapshot |
| Glasses transport | `WearRuntimeGlassesSender` |

Feature runtime classes remain input/read-projection adapters over the injected root authority. Non-migrated UI routing helpers remain compatibility-only and do not own migrated feature values.

## Static audit

The final tree contains one `WearRuntimeStore` implementation and no mutable static `WearSession`, duplicate actual-screen store, `_screenPayloads` cache, second production glasses sender, migrated widget `enterScreen()` calls, mutable printer selection copy, or PCM/native handles in aggregate state. Reducers return effects without I/O or mutable state setters; external results return through typed intents with epoch, operation, screen and phase admission.

## Owner validation

The owner should run the documented Flutter test groups, analyzer, Android/Gradle builds, and T2151 device scenarios. Device acceptance must include logout/detached teardown, phone inactive/resume, scanner prepare/pause races, printer/scan/availability screen-off flows, glasses disconnect/reconnect, transport failure, and exactly-once print/photo/UI effects.

## Residual risks

- Static inspection does not prove Dart compilation or runtime behavior.
- Device transport and scanner lifecycle timing remain unverified.
- Compatibility routing for non-migrated presentation screens remains and must not gain new business ownership.
