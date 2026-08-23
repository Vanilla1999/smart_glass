# MR-S10: Phone presentation focus from aggregate state

Дата: 2026-08-23.

## 1. Контекст

- Integration/base branch: `experiment/aligned-audio-frontend`.
- Base commit: `dcaf154552791db8eb6d7a0edc48dc31950635d3`.
- Work branch: `refactor/wear-phone-aggregate-projection`.
- Plan-first commit: `35981269525ee64f9f7c5e3ff72e7d8ccf2af2fa`.
- Исходный roadmap: [`docs/WEAR_SINGLE_STATE_RUNTIME_PLAN.md`](../WEAR_SINGLE_STATE_RUNTIME_PLAN.md).
- Предыдущий review-fix: PR #14, исправивший print-success contract и audit evidence.

После MR-S1...MR-S9 aggregate runtime уже содержит
`WearPresentationFocusSlice`, а `WearRuntimeProjection` строит phone/glasses focus
из одного committed snapshot. Но четыре phone screen всё ещё используют
`WearFlowState` как первичный mutable owner: сначала меняют controller state, а
`WearFlowController._setState()` затем асинхронно дублирует focus в aggregate.
Это legacy-first path и он противоречит принятому ownership contract.

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
4. не читать `WearFlowController.state`/`WearFlowController.stateStream` как
   business source of truth.

`WearFlowState` в этом MR остаётся только read-only compatibility view для ещё не
мигрированных consumers.

## 3. Ownership ledger

| Business value | Owner до MR | Owner после MR | Compatibility view | Этап удаления |
|---|---|---|---|---|
| Menu focus | `WearFlowState.menuFocusedIndex` с последующим dispatch | `WearPresentationFocusSlice` | `WearFlowState.menuFocusedIndex`, отражаемый после aggregate commit | MR-S12 |
| Home-confirm focus | `WearFlowState.homeConfirmFocusedIndex` с последующим dispatch | `WearPresentationFocusSlice` | legacy field, read-only compatibility view | MR-S12 |
| Continue-scan focus | `WearFlowState.continueScanFocusedIndex` с последующим dispatch | `WearPresentationFocusSlice` | legacy field, read-only compatibility view | MR-S12 |
| Availability-interaction focus | `WearFlowState.availabilityInteractionFocusedIndex` с последующим dispatch | `WearPresentationFocusSlice` | legacy field, read-only compatibility view | MR-S12 |

После MR ни одна production focus mutation scoped screens не начинается с
`WearFlowController._setState()`. Она начинается с
`dispatchSemanticInput(presentationFocus)`, проверяет typed receipt и только затем
отражает committed value в compatibility state.

## 4. Реализационная форма

Чтобы не переписывать в одном MR весь монолитный `WearFlowController`, production
DI получает stateless compatibility facade
`WearAggregatePresentationFlowController`.

Facade:

- не хранит самостоятельный business focus;
- dispatches semantic focus через root authority;
- читает selection из committed `WearPresentationFocusSlice`;
- сериализует focus-dependent voice/button commands;
- подписывается на `WearRuntimeAuthority.states` для aggregate -> legacy mirror;
- отменяет подписку до controller/authority dispose.

Исторический focus echo внутри base `WearFlowController._setState()` физически
остаётся до MR-S12. В production MR-S10 paths он вызывается только после aggregate
commit с тем же значением и поэтому reducer принимает его как no-op без новой
revision. Это временный compatibility mechanism, а не второй writable owner.

## 5. Scope реализации

### 5.1. Controller boundary

1. Добавить aggregate-first facade для presentation focus.
2. Перевести public focus/select methods четырёх экранов на semantic dispatch.
3. Перевести voice/hardware `up`/`down`/`select` на committed aggregate focus.
4. Защитить `continueScan`/`finish` и `yes`/`no`/`cancel` тем же commit-first
   контрактом.
5. Подписать compatibility facade на `WearRuntimeAuthority.states` и отражать
   aggregate focus в `WearFlowState` без нового state holder.
6. При accepted focus отражать значение до делегирования legacy action, которому
   ещё нужен compatibility state.
7. Корректно отменять authority subscription в `dispose()`.

### 5.2. Phone widgets

Для `menu`, `homeConfirm`, `continueScan` и `availabilityInteraction`:

1. заменить подписку на `WearFlowController.stateStream` подпиской на
   `WearRuntimeAuthority.states`;
2. получить initial focus из `WearRuntimeProjection.projectPhone()`;
3. убрать imports и чтения `WearFlowState`;
4. убрать ручную публикацию второго focus payload на glasses;
5. использовать controller только как input/navigation compatibility facade.

### 5.3. Regression gates

Добавить source-level ownership test, который запрещает в перечисленных screens:

- импорт `wear_flow_state.dart`;
- `.stateStream`;
- чтение legacy focus fields через controller state.

Тот же gate должен подтверждать использование:

- `WearRuntimeProjection.projectPhone`;
- `WearDependencies.I.authority`.

Behavior specification должна покрывать:

- aggregate-first touch commit;
- same-value no-op revision;
- direct aggregate update -> compatibility view;
- stale-screen rejection;
- voice/button parity;
- selection из committed aggregate focus;
- production DI facade wiring.

## 6. Не входит в MR

- удаление `enterScreen()` из widget `initState()` — отдельный MR-S11;
- физическое удаление presentation fields и исторического echo из
  `WearFlowController` — отдельный MR-S12;
- миграция status/voice-clarification lifecycle;
- изменение navigation reducer или route protocol;
- изменение scanner, printer, availability repositories;
- voice/UAC4/audio transport changes;
- UI layout/styling;
- device/hardware validation;
- запуск Flutter, Dart analyzer, Gradle или APK build.

## 7. Порядок реализации

1. Зафиксировать исходный план отдельным commit.
2. Добавить aggregate-first controller boundary.
3. Перевести четыре phone screen на aggregate projection.
4. Добавить regression specification и validation checklist.
5. Обновить `docs/INDEX.md` и compatibility status.
6. Открыть PR в `experiment/aligned-audio-frontend`.
7. Провести полный static diff review на точном HEAD.
8. Исправить каждое найденное замечание отдельным review-fix commit.
9. Повторить static review, затем merge PR.
10. Удалить merged work branches; посторонние branches/PR не трогать.

## 8. Acceptance criteria

- Aggregate `WearPresentationFocusSlice` является единственным production writable
  owner для четырёх scoped screens.
- Production mutation сначала получает accepted semantic receipt и только потом
  обновляет compatibility view.
- Touch/voice/hardware focus mutations проходят через один semantic reducer.
- Direct section/continue/finish/yes/no commands не обходят commit-first contract.
- Select/navigation читает committed aggregate focus.
- Scoped widgets читают один phone projection и не подписываются на
  `WearFlowController.stateStream`.
- Compatibility echo не создаёт новую aggregate revision и не может изменить
  уже committed value.
- Phone и glasses используют один focus snapshot.
- Diff не содержит audio, generated files, build outputs или unrelated cleanup.
- Документация не заявляет, что `enterScreen()`/physical compatibility cleanup
  уже завершены.

## 9. Static review checklist

- Нет fire-and-forget select, который может навигировать раньше принятого focus.
- Rejected/stale semantic input не запускает selection/navigation.
- Authority subscription не создаёт цикл aggregate -> legacy -> aggregate:
  повторный semantic echo является same-value no-op.
- Subscription отменяется до terminal controller dispose.
- Touch focus разрешён по актуальному logical screen и не зависит от voice/runtime
  admission.
- Screen change не применяет focus другого logical screen.
- Item bounds совпадают с projection/reducer: menu 4, остальные scoped screens 2.
- No-op focus не создаёт новую aggregate revision или повторную navigation.
- Unauthorized/bootstrap behavior вне scoped focus не изменён.

## 10. Validation limitation

По ограничению задачи `flutter test`, `flutter analyze`, `dart analyze`, Gradle и
APK build не запускаются. Validation этого MR состоит из чтения полного source,
GitHub compare/patch review и проверки ссылочной/типовой согласованности глазами.
Добавленные tests являются regression specification и должны быть запущены
владельцем проекта локально перед device release.

## 11. Stop/revert

MR необходимо остановить или разделить, если:

- для aggregate-first focus требуется одновременно переписать navigation protocol;
- facade начинает хранить независимую mutable копию focus;
- focus невозможно commit-нуть до select без изменения user-visible flow;
- compatibility mirror может изменить aggregate отличным значением;
- scope затрагивает UAC4/scanner/native code.

Rollback удаляет facade wiring и возвращает controller-first focus одним
revert-коммитом; третий state owner не добавляется.
