# MR-S10: Phone presentation focus from aggregate state

Дата: 2026-08-23.

## 1. Контекст

- Integration/base branch: `experiment/aligned-audio-frontend`.
- Base commit: `dcaf154552791db8eb6d7a0edc48dc31950635d3`.
- Work branch: `refactor/wear-phone-aggregate-projection`.
- Исходный roadmap: [`docs/WEAR_SINGLE_STATE_RUNTIME_PLAN.md`](../WEAR_SINGLE_STATE_RUNTIME_PLAN.md).
- Предыдущий review-fix: PR #14, исправивший print-success contract и audit evidence.

После MR-S1...MR-S9 aggregate runtime уже содержит
`WearPresentationFocusSlice`, а `WearRuntimeProjection` строит phone/glasses focus
из одного committed snapshot. Но четыре phone screen всё ещё используют
`WearFlowState` как первичный mutable owner: сначала меняют controller state, а
`WearFlowController._setState()` затем асинхронно дублирует focus в aggregate.
Это legacy-first dual-write path и он противоречит принятому ownership contract.

## 2. Цель

Сделать aggregate `WearPresentationFocusSlice` единственным writable owner focus
для экранов:

- `WearScreenId.menu`;
- `WearScreenId.homeConfirm`;
- `WearScreenId.continueScan`;
- `WearScreenId.availabilityInteraction`.

Phone widgets должны:

1. читать focus через `WearRuntimeProjection.projectPhone()`;
2. подписываться на `WearRuntimeAuthority.states`;
3. отправлять semantic focus intent через compatibility API controller;
4. не читать `WearFlowController.state`/`WearFlowController.stream` как business
   source of truth.

`WearFlowState` в этом MR остаётся только read-only compatibility mirror для ещё
не мигрированных consumers.

## 3. Ownership ledger

| Business value | Owner до MR | Owner после MR | Compatibility view | Этап удаления |
|---|---|---|---|---|
| Menu focus | `WearFlowState.menuFocusedIndex` с последующим dual write | `WearPresentationFocusSlice` | `WearFlowState.menuFocusedIndex`, обновляемый из aggregate | MR-S12 |
| Home-confirm focus | `WearFlowState.focusedIndex` с последующим dual write | `WearPresentationFocusSlice` | `WearFlowState.focusedIndex`, read-only mirror | MR-S12 |
| Continue-scan focus | `WearFlowState.focusedIndex` с последующим dual write | `WearPresentationFocusSlice` | `WearFlowState.focusedIndex`, read-only mirror | MR-S12 |
| Availability-interaction focus | `WearFlowState.focusedIndex` с последующим dual write | `WearPresentationFocusSlice` | `WearFlowState.focusedIndex`, read-only mirror | MR-S12 |

После MR не должно существовать пути, где `_setState()` инициирует
`presentationFocus` dispatch. Любая авторизованная focus mutation начинается с
`dispatchSemanticInput()` и только затем отражается в compatibility state.

## 4. Scope реализации

### 4.1. Controller boundary

1. Добавить aggregate-first helper для presentation focus.
2. Перевести public focus/select methods четырёх экранов на awaited semantic
   dispatch.
3. Перевести voice/hardware up/down/select paths на committed aggregate focus.
4. Подписать compatibility controller на `WearRuntimeAuthority.states` и
   отражать aggregate focus в `WearFlowState` без обратной записи.
5. Удалить `_syncPresentationFocus()` из `_setState()`.
6. При авторизованной сессии строить compatibility payload этих экранов через
   aggregate projection.
7. Корректно отменять authority subscription в `dispose()`.

### 4.2. Phone widgets

Для `menu`, `homeConfirm`, `continueScan` и `availabilityInteraction`:

1. заменить подписку на `WearFlowController.stream` подпиской на
   `WearRuntimeAuthority.states`;
2. получить initial focus из `WearRuntimeProjection.projectPhone()`;
3. убрать imports и чтения `WearFlowState`;
4. не выполнять второй focus dispatch из scroll synchronization;
5. использовать controller только как input/navigation compatibility facade.

### 4.3. Regression gates

Добавить static ownership test, который запрещает в перечисленных screens:

- импорт `wear_flow_state.dart`;
- `_flow.stream`;
- `_flow.state.focusedIndex`;
- `_flow.state.menuFocusedIndex`.

Тот же gate должен подтверждать использование:

- `WearRuntimeProjection.projectPhone`;
- `WearRuntimeAuthority.states`.

Controller source gate должен запрещать вызов `_syncPresentationFocus` и
presentation-focus dispatch из `_setState()`.

## 5. Не входит в MR

- удаление `enterScreen()` из widget `initState()` — отдельный MR-S11;
- полный демонтаж presentation fields из `WearFlowState` и
  `WearFlowController` — отдельный MR-S12;
- миграция status/voice-clarification lifecycle;
- изменение navigation reducer или route protocol;
- изменение scanner, printer, availability repositories;
- voice/UAC4/audio transport changes;
- UI layout/styling;
- device/hardware validation;
- запуск Flutter, Dart analyzer, Gradle или APK build.

## 6. Порядок реализации

1. Зафиксировать этот план отдельным commit.
2. Изменить controller aggregate-first boundary.
3. Перевести четыре phone screen на aggregate projection.
4. Добавить static ownership test и validation checklist.
5. Обновить `docs/INDEX.md` и merge report compatibility status.
6. Открыть PR в `experiment/aligned-audio-frontend`.
7. Провести полный static diff review на точном HEAD.
8. Исправить каждое найденное замечание отдельным review-fix commit.
9. Повторить static review, затем merge PR.
10. Удалить merged work branch; посторонние branches/PR не трогать.

## 7. Acceptance criteria

- Aggregate `WearPresentationFocusSlice` является единственным writable owner для
  четырёх scoped screens.
- `_setState()` больше не запускает focus dispatch.
- Авторизованные touch/voice/hardware focus mutations проходят через один
  semantic reducer.
- Select/navigation читает committed aggregate focus.
- Scoped widgets читают один phone projection и не подписываются на
  `WearFlowController.stream`.
- Compatibility `WearFlowState` обновляется только aggregate -> legacy.
- Phone и glasses используют один focus snapshot.
- Diff не содержит audio, generated files, build outputs или unrelated cleanup.
- Документация не заявляет, что `enterScreen()`/compatibility cleanup уже
  завершены.

## 8. Static review checklist

- Нет fire-and-forget select, который может навигировать раньше принятого focus.
- Rejected/stale semantic input не запускает selection/navigation.
- Authority subscription не создаёт цикл aggregate -> legacy -> aggregate.
- Subscription отменяется при terminal dispose.
- Unauthorized compatibility fallback сохраняет auth/bootstrap behavior.
- Screen change не применяет focus другого logical screen.
- Item bounds совпадают с projection/reducer: menu 4, остальные scoped screens 2.
- No-op focus не создаёт лишнюю legacy emission или повторную navigation.

## 9. Validation limitation

По ограничению задачи `flutter test`, `flutter analyze`, `dart analyze`, Gradle и
APK build не запускаются. Validation этого MR состоит из чтения полного source,
GitHub compare/patch review и проверки ссылочной/типовой согласованности глазами.
Добавленные tests являются regression specification и должны быть запущены
владельцем проекта локально перед device release.

## 10. Stop/revert

MR необходимо остановить или разделить, если:

- для удаления dual write требуется одновременно переписать navigation protocol;
- widget должен стать вторым aggregate owner;
- focus невозможно commit-нуть до select без изменения user-visible flow;
- compatibility mirror снова начинает отправлять mutation в aggregate;
- scope затрагивает UAC4/scanner/native code.

Rollback возвращает controller-first focus для этих четырёх экранов одним
revert-коммитом; третий state owner не добавляется.