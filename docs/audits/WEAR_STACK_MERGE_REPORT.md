# Wear single-state stack: merge and validation report

Дата актуализации: 2026-08-23.

## 1. Назначение отчёта

Этот документ фиксирует:

- исходный план Wear single-state migration;
- фактическую историю PR #1–#12;
- состояние integration branch после merge stack и post-merge stabilization;
- достигнутый ownership migrated business slices;
- оставшийся compatibility layer;
- исторический host-validation snapshot;
- обязательные follow-up и device-only release gates.

Отчёт не заменяет GitHub history, commit objects или CI. Для moving review-fix
branch её актуальный HEAD и итоговый merge SHA берутся из соответствующего PR, а
не поддерживаются вручную в этом документе до merge.

## 2. Где находится исходный план

Основной план миграции находится в
[`docs/WEAR_SINGLE_STATE_RUNTIME_PLAN.md`](../WEAR_SINGLE_STATE_RUNTIME_PLAN.md).
Последовательность этапов определена в разделе 15, `MR-S1`...`MR-S9`.

Связанные authoritative документы:

- [`docs/decisions/ADR-0001-WEAR_SINGLE_STATE_OWNER.md`](../decisions/ADR-0001-WEAR_SINGLE_STATE_OWNER.md) — один writable owner каждого business value;
- [`docs/decisions/ADR-0002-WEAR_STORE_EXECUTION_ORDER.md`](../decisions/ADR-0002-WEAR_STORE_EXECUTION_ORDER.md) — порядок dispatch, commit, effect и receipt;
- [`docs/checklists/WEAR_SINGLE_STATE_MR_REVIEW.md`](../checklists/WEAR_SINGLE_STATE_MR_REVIEW.md) — обязательная проверка каждого migration MR;
- `docs/checklists/WEAR_MR_S*_*.md` — validation record отдельных этапов;
- [`docs/audits/WEAR_STACK_REVIEW_FIX_PLAN.md`](WEAR_STACK_REVIEW_FIX_PLAN.md) — bounded plan исправления замечаний финального review;
- [`docs/INDEX.md`](../INDEX.md) — индекс canonical project documentation.

Изначальная стратегия: strangler migration без одновременной записи одного
значения в legacy и aggregate owners. Каждый MR должен был уменьшать число
mutable owners, переносить bounded slice и сохранять работающий flow.

## 3. Integration branch и commit ledger

- Integration/base branch: `experiment/aligned-audio-frontend`.
- MR-S9 merge SHA: `99d8e5b702d19e99c1c8ffb69f9d54309a70933f`.
- Первый merge-report commit: `10d639b25a7be567fbafc3f9ef0c972040c670ec`.
- Committed post-merge stabilization HEAD, от которого начат review-fix MR:
  `5b203450eff51119d65cd0c4f3817b2d4a0fc38e`.
- Post-merge production fixes, test migration и предыдущая актуализация отчёта
  входят в `5b20345`; они больше не являются незакоммиченным working-tree state.
- Review-fix branch: `fix/wear-stack-review-findings`.
- План review-fix зафиксирован commit
  `c642f2dd904ac9ba0e8ea4930ab3fb91d004b8c9`.

Для аудита важно различать три точки:

1. `99d8e5b` — кодовый результат merge MR-S9;
2. `10d639b` — первоначальный merge report поверх stack;
3. `5b20345` — committed stabilization и migrated legacy tests после stack.

## 4. План и фактические merges

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
| MR-S8 | [#11](https://github.com/Vanilla1999/smart_glass/pull/11) | `refactor/wear-runtime-unified-projection` | `experiment/aligned-audio-frontend` | `e777e8389662c5ee130e6c12136d8e807542d05e` | `a6688567ccab2ee9fc4f03c6511d5ee5ccec71a5` | Unified aggregate projection and versioned glasses envelope |
| MR-S9 | [#12](https://github.com/Vanilla1999/smart_glass/pull/12) | `refactor/wear-runtime-legacy-cleanup` | `experiment/aligned-audio-frontend` | `afd5f526b786654cedbdc29e1ff5b2a9853275d3` | `99d8e5b702d19e99c1c8ffb69f9d54309a70933f` | Cleanup of migrated legacy writable owners and retained adapters |

PR #8 закрыт без merge и не входит в integration history. Утверждение относится
к original stack #1–#12 и не означает отсутствие других, более поздних PR в
репозитории.

## 5. Состояние веток после merge

Canonical head branches PR #2...#12 были удалены после merge; integration branch
сохранена. Это исторический remote cleanup snapshot original stack.

Подтверждённое committed состояние:

- integration branch содержала `5b20345` при создании review-fix branch;
- PR #8 закрыт без merge, его commit не добавлялся в integration branch;
- `artifacts/voice_replay/`, `packages/vosk_flutter_service/build/` и
  `packages/vosk_flutter_service/pubspec.lock` не входят в committed tree
  `5b20345`;
- ветки `main`, voice/UAC4, `works`, `fsd`, пользовательские ветки и refs другого
  remote не являлись целью cleanup.

Текущее локальное working tree, локальные refs и ignored files этим GitHub audit
не подтверждаются. Для таких утверждений нужен отдельный timestamped вывод
`git status`/`git branch`, которого в этом отчёте нет.

## 6. Достигнутый ownership и граница результата

Для migrated business values authoritative state находится в aggregate runtime:

| Value | Authoritative owner после stack |
|---|---|
| Session identity and lifecycle | Aggregate session/lifecycle slices |
| Logical navigation and pending request | Aggregate navigation slice |
| Voice, scanner and connectivity admission | Aggregate control slices |
| Printer state and selection | Aggregate printer slice |
| Scan, print and status | Aggregate scan slice |
| Availability flow | Aggregate availability slice |
| Semantic inputs and bounded UI effects | Aggregate semantic/UI-effect reducers |
| Glasses projection and envelope version | Projection of committed aggregate snapshot |
| Glasses transport | `WearRuntimeGlassesSender` |

При этом исходный Definition of Done раздела 15 выполнен не полностью для всего
phone presentation layer. В проекте сохранены:

- `WearFlowController` с compatibility presentation/navigation state;
- runtime adapters для ещё не полностью мигрированных экранов;
- widget lifecycle paths, которые всё ещё вызывают compatibility `enterScreen()`;
- phone screens, которые читают legacy-compatible controller stream вместо
  единой aggregate phone projection.

Поэтому корректная формулировка результата:

> Основные Wear business slices и glasses projection переведены на aggregate
> authority. Полное удаление compatibility state и перевод всего phone UI в
> projection-only режим остаются отдельным follow-up milestone.

Нельзя использовать этот отчёт как разрешение снова добавлять второй writable
owner уже мигрированного business value.

## 7. Committed post-merge stabilization

Commit `5b20345` включает production/test stabilization после первого merge audit:

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
- targeted adapters и legacy tests приведены к typed authority API.

Review-fix MR дополнительно исправляет доказанную семантическую ошибку успешной
печати:

- `PrintPriceTagUseCase` и mock path возвращают имя использованного принтера;
- typed success intent переносит `printerName`, а не маскирует его как товар;
- `WearScanTaskSlice.productName` сохраняет выбранный товар;
- success status использует товар как `message`, принтер как `details`;
- raw и status-sequencing reducers имеют одинаковый контракт;
- regression tests используют разные значения товара и принтера.

## 8. Миграция legacy tests

Первый полный последовательный запуск после production fixes ранее показал:

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

В `5b20345` зафиксировано:

- добавлен `test/support/wear_runtime_test_helper.dart`;
- migrated tests создают fresh local authority, ожидают authorization, runtime/UI
  activation и используют тот же authority в controller;
- setup navigation выполняется через awaited `requestNavigation()`;
- effect completion ожидается через predicate по authoritative state;
- router tests различают logical screen, actual route и acknowledgement;
- projection tests создают aggregate state вместо direct payload injection;
- удалены 40 test cases, проверявших намеренно удалённый controller-owned
  payload/history compatibility contract; актуальная ownership coverage сохранена
  в authority, navigation и projection suites.

## 9. Исторический host-validation snapshot

До commit `5b20345` был записан следующий локальный результат:

| Gate | Исторический локальный результат |
|---|---|
| Migrated nine-file suite | 138 passed, 0 failed |
| Targeted Wear runtime suite | 152 passed, 0 failed |
| Full `flutter test --concurrency=1` | 751 passed, 2 skipped, 0 failed |
| Analyzer for 10 migrated test/helper files | No issues found |
| Full `flutter analyze` | No compile errors; 560 existing warning/info findings |
| `git diff --check` | Passed |
| `flutter build apk --debug` | Passed |
| Debug APK | `build/app/outputs/flutter-apk/app-debug.apk` |

Ограничения этого evidence:

- это сохранённый локальный snapshot, а не GitHub Actions/commit status;
- в отчёте нет immutable log artifact, environment manifest и APK SHA-256;
- он не доказывает результат на moving review-fix HEAD;
- в review-fix MR Flutter, Dart analyzer, Gradle, tests и APK build повторно не
  запускались; изменения проверяются только чтением кода и PR diff.

Следовательно, после merge review-fix для commit-bound release evidence нужен
отдельный разрешённый CI/local validation run на точном final SHA.

## 10. Device-only release gates

На реальном устройстве или emulator ещё необходимо проверить:

- Android MethodChannel и secondary glasses display;
- real scanner/camera permissions and lifecycle;
- USB/camera scanner input и reconnect/replay;
- UAC4 microphone routing и native Vosk model loading;
- logout/detached resource release;
- phone inactive/resume и scanner prepare/pause races;
- printer, scan и availability screen-off flows;
- glasses disconnect/reconnect и transport failure;
- exactly-once print/photo/UI effects на реальном hardware path;
- настоящий принтер и корректное отображение пары товар/принтер после печати.

Эти пункты остаются обязательными production release gates независимо от
host-side unit coverage.

## 11. Оставшиеся follow-up

После review-fix MR остаются отдельными задачами:

1. Перевести оставшиеся phone screens на aggregate selectors или
   `WearRuntimeProjection.projectPhone`.
2. Удалить business `enterScreen()` из widget lifecycle там, где он ещё служит
   mutation, а не observation.
3. Устранить дублирование `currentScreen`, menu focus и других navigation values
   между aggregate и compatibility state.
4. Сузить `WearFlowController` до façade без собственного writable business state
   либо удалить его после миграции последнего consumer.
5. Расширить ownership/static gates на весь Wear presentation layer.
6. Выполнить commit-bound host validation на разрешённом final SHA.
7. Закрыть device-only release gates из раздела 10.

Итоговый статус нельзя описывать как полный production sign-off, пока пункты 6–7
не подтверждены. Архитектурный stack завершил основной aggregate migration, но
полный presentation cleanup исходного Definition of Done ещё открыт.
