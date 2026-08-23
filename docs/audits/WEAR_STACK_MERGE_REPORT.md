# Wear single-state stack: merge and validation report

Дата актуализации: 2026-08-23.

## 1. Где находится исходный план

Основной план миграции находится в
[`docs/WEAR_SINGLE_STATE_RUNTIME_PLAN.md`](../WEAR_SINGLE_STATE_RUNTIME_PLAN.md).
Последовательность этапов определена в разделе 15, `MR-S1`...`MR-S9`.

Связанные authoritative документы:

- [`docs/decisions/ADR-0001-WEAR_SINGLE_STATE_OWNER.md`](../decisions/ADR-0001-WEAR_SINGLE_STATE_OWNER.md) — один writable owner каждого business value;
- [`docs/decisions/ADR-0002-WEAR_STORE_EXECUTION_ORDER.md`](../decisions/ADR-0002-WEAR_STORE_EXECUTION_ORDER.md) — порядок dispatch, commit, effect и receipt;
- [`docs/checklists/WEAR_SINGLE_STATE_MR_REVIEW.md`](../checklists/WEAR_SINGLE_STATE_MR_REVIEW.md) — обязательная проверка каждого migration MR;
- `docs/checklists/WEAR_MR_S*_*.md` — validation record отдельных этапов;
- [`docs/INDEX.md`](../INDEX.md) — индекс canonical project documentation.

Изначальная стратегия: strangler migration без одновременной записи одного
значения в legacy и aggregate owners. Каждый MR должен был уменьшать число
mutable owners, переносить один bounded slice и сохранять работающий flow.

## 2. Integration branch и committed state

- Integration/base branch: `experiment/aligned-audio-frontend`.
- GitHub remote tracking branch: `github/experiment/aligned-audio-frontend`.
- Последний committed и pushed HEAD: `10d639b25a7be567fbafc3f9ef0c972040c670ec`.
- Merge stack HEAD до документационного commit: `99d8e5b702d19e99c1c8ffb69f9d54309a70933f`.
- Commit исходного merge report: `10d639b docs(wear): record single-state stack merge`.
- Исправления compilation/runtime/tests после `10d639b` находятся в текущем
  рабочем дереве и пока не закоммичены и не отправлены.

## 3. План и фактические merges

Все canonical PR были смержены 2026-08-23 в плановом порядке в
`experiment/aligned-audio-frontend`.

| Stage | PR | Head branch | Base branch | Reviewed HEAD | Merge SHA | Результат |
|---|---:|---|---|---|---|---|
| Baseline stabilization | [#1](https://github.com/Vanilla1999/smart_glass/pull/1) | `fix/wear-runtime-barcode-scanner-stabilization` | `experiment/aligned-audio-frontend` | — | `945daf96b72ac12d7493fd5f9419df420fe33687` | Scanner/barcode ownership stabilized before stack |
| Architecture plan | [#2](https://github.com/Vanilla1999/smart_glass/pull/2) | `plan/wear-single-state-runtime` | `experiment/aligned-audio-frontend` | `d2a3c11b4d4a8ca17a193e6669a2c15bb30917eb` | `dbf16da2ff15095cce1df98c47f6034e849910e8` | Single-state plan and contracts |
| MR-S1 | [#3](https://github.com/Vanilla1999/smart_glass/pull/3) | `refactor/wear-runtime-store-shell` | `experiment/aligned-audio-frontend` | `aac060c51a94be38fe2934d99f318f05724ddf07` | `2434677e5d7c37081317cdab35ac039b4340eae2` | Store shell, immutable snapshot, queue and receipts |
| MR-S2 | [#4](https://github.com/Vanilla1999/smart_glass/pull/4) | `refactor/wear-runtime-session-navigation` | `experiment/aligned-audio-frontend` | `0075d7d0d40eb3b212f1881e845f7a0809136285` | `b20128d9ea9fe9d49d909228fb526fac39e4ddc9` | Session, lifecycle and navigation authority |
| MR-S3 | [#5](https://github.com/Vanilla1999/smart_glass/pull/5) | `refactor/wear-runtime-control-slices` | `experiment/aligned-audio-frontend` | `39c556a03ab1eb3d71db5cb25b6ca55573d3d9b6` | `840e8b19022404e40132c7a232af3790c146bc27` | Voice, scanner and connectivity controls |
| MR-S4 | [#6](https://github.com/Vanilla1999/smart_glass/pull/6) | `refactor/wear-runtime-printer-slice` | `experiment/aligned-audio-frontend` | `4a533ee6f28a035e41c2afbcd0a2e955e91c8a39` | `5ca7382a5cf5e10c5f56039f0654ecc1df3ede36` | Authoritative printer slice |
| MR-S5 | [#7](https://github.com/Vanilla1999/smart_glass/pull/7) | `refactor/wear-runtime-scan-slice` | `experiment/aligned-audio-frontend` | `e7c43c29f4975d1adfaca7eea38091dfe32ed389` | `064cd928ed5526c79c9b2caf51fda4de405a98f6` | Scan, print and status slice |
| Duplicate, not merged | [#8](https://github.com/Vanilla1999/smart_glass/pull/8) | `refactor/wear-session-navigation-state` | `refactor/wear-runtime-store-shell` | — | — | Superseded MR-S2 duplicate, closed |
| MR-S6 | [#9](https://github.com/Vanilla1999/smart_glass/pull/9) | `refactor/wear-runtime-availability-slice` | `experiment/aligned-audio-frontend` | `808fecb9dbe14b1bb0c633432af889f16905d474` | `0af51a1f3a9b04bb10b6d3ad096a2546008fb18a` | Authoritative availability slice |
| MR-S7 | [#10](https://github.com/Vanilla1999/smart_glass/pull/10) | `refactor/wear-runtime-semantic-inputs` | `experiment/aligned-audio-frontend` | `94843ad69d02da8a566e8a111a75b432b54d5c36` | `90155f87b0d94cd707f6d737d10011f20655f4d3` | Semantic inputs and bounded UI effects |
| MR-S8 | [#11](https://github.com/Vanilla1999/smart_glass/pull/11) | `refactor/wear-runtime-unified-projection` | `experiment/aligned-audio-frontend` | `e777e8389662c5ee130e6c12136d8e807542d05e` | `a6688567ccab2ee9fc4f03c6511d5ee5ccec71a5` | Unified phone/glasses projection |
| MR-S9 | [#12](https://github.com/Vanilla1999/smart_glass/pull/12) | `refactor/wear-runtime-legacy-cleanup` | `experiment/aligned-audio-frontend` | `afd5f526b786654cedbdc29e1ff5b2a9853275d3` | `99d8e5b702d19e99c1c8ffb69f9d54309a70933f` | Legacy writable-owner cleanup |

PR #8 не входит в merge history. Открытых PR и unresolved review threads после
merge stack не осталось.

## 4. Состояние веток после merge

Canonical head branches PR #2...#12 были удалены локально и на GitHub после
merge; integration branch сохранена. Baseline branch PR #1 и отдельные ветки на
других remotes не являются частью cleanup canonical MR stack.

Текущее состояние:

- `experiment/aligned-audio-frontend` и
  `github/experiment/aligned-audio-frontend` указывают на `10d639b`;
- локальных canonical `plan/wear-single-state-runtime` и
  `refactor/wear-runtime-*` branches больше нет;
- в `github/*` canonical PR #2...#12 head refs отсутствуют;
- ветки `main`, voice/UAC4, `works`, `fsd`, пользовательские и branches другого
  remote `origin` не удалялись как часть этой работы;
- PR #8 закрыт без merge, его commit не добавлялся в integration branch.

## 5. Финальный ownership

| Value | Writable owner |
|---|---|
| Session identity and lifecycle | Aggregate session/lifecycle slices |
| Logical navigation, history and pending request | Aggregate navigation slice |
| Actual phone route | Epoch-bound aggregate navigation observation |
| Voice, scanner and connectivity | Aggregate control slices |
| Printer state and selection | Aggregate printer slice |
| Scan, print and status | Aggregate scan slice |
| Availability flow | Aggregate availability slice |
| Semantic inputs and UI effects | Aggregate semantic/UI-effect reducers |
| Phone and glasses projection | Pure projection of one committed snapshot |
| Glasses transport | `WearRuntimeGlassesSender` |

Feature runtime classes остаются input/read-projection adapters над injected root
authority. Compatibility helpers не должны снова становиться writable business
owners.

## 6. Исправления после merge

После первого статического merge audit были устранены compilation и runtime
проблемы merged stack:

- navigation acknowledgement переведён на epoch-bound authority adapter;
- удалены обращения к отсутствующему `_clearContextPayload`;
- восстановлены недостающие equality/import/type contracts;
- исправлены callback signatures scan/printer/status adapters;
- добавлен `WearRuntimeAuthority.authorizedStream`;
- `WearRuntimeGlassesSender.reconnect()` отправляет projection текущего
  `store.state`, а не потенциально устаревший cached snapshot;
- `WearMockConfig` безопасно работает без предварительной инициализации dotenv;
- mock lookup/print перенесены в `WearScanEffectExecutor`;
- stale availability/photo/scan/printer results защищены epoch, operation и screen
  admission;
- targeted adapters и tests приведены к typed authority API.

## 7. Миграция legacy tests

Первый полный последовательный запуск после production fixes показал:

- 661 passed;
- 2 skipped;
- 130 failed.

Все 130 failures находились в девяти legacy test files. Основные причины:

- controller создавал собственный anonymous authority, а тест авторизовывал другой
  singleton или не авторизовывал runtime вообще;
- `enterScreen()` и direct router mutations использовались как business navigation;
- `rememberScreenPayload()`/`publishScreenPayload()` использовались как canonical
  state fixture после удаления payload cache ownership;
- availability tests считали accepted dispatch завершённым external effect;
- feedback assertions отражали старую policy.

Выполнено:

- добавлен `test/support/wear_runtime_test_helper.dart`;
- каждый migrated test создаёт fresh local authority, ожидает authorization,
  runtime/UI activation и использует тот же authority в controller;
- setup navigation выполняется через awaited `requestNavigation()`;
- effect completion ожидается через predicate по authoritative state;
- router tests различают logical screen, actual route и acknowledgement;
- projection tests создают aggregate state вместо direct payload injection;
- удалены 40 test cases, проверявших намеренно удалённый controller-owned
  payload/history compatibility contract; актуальная ownership coverage сохранена
  в runtime authority, navigation и projection suites.

## 8. Итоговая валидация

Host-side validation выполнена на текущем рабочем дереве:

| Gate | Result |
|---|---|
| Migrated nine-file suite | 138 passed, 0 failed |
| Targeted Wear runtime suite | 152 passed, 0 failed |
| Full `flutter test --concurrency=1` | 751 passed, 2 skipped, 0 failed |
| Analyzer for 10 migrated test/helper files | No issues found |
| Full `flutter analyze` | No compile errors; 560 existing warning/info findings |
| `git diff --check` | Passed |
| `flutter build apk --debug` | Passed |
| Debug APK | `build/app/outputs/flutter-apk/app-debug.apk` |

Согласно Flutter documentation, `test/` выполняется host-side. Native
`integration_test/`/`patrol_test/` scenarios требуют Android device/emulator и не
входят в приведённые 751 host tests.

## 9. Что не проверено

На реальном устройстве или emulator ещё необходимо проверить:

- Android MethodChannel и secondary glasses display;
- real scanner/camera permissions and lifecycle;
- UAC4 microphone routing и native Vosk model loading;
- logout/detached resource release;
- phone inactive/resume и scanner prepare/pause races;
- printer, scan и availability screen-off flows;
- glasses disconnect/reconnect и transport failure;
- exactly-once print/photo/UI effects на реальном hardware path.

## 10. Текущее незавершённое действие

Техническая миграция и host validation завершены, но post-merge fixes, test
migration и эта актуализация отчёта находятся в незакоммиченном рабочем дереве.
До создания commit необходимо ещё раз проверить intended diff и не включать
существующие untracked artifacts:

- `artifacts/voice_replay/`;
- `packages/vosk_flutter_service/build/`;
- `packages/vosk_flutter_service/pubspec.lock`.
