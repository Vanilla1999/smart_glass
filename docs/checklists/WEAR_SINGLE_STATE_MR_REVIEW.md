# Review checklist для MR миграции Wear single-state

Этот шаблон применяется ко всем кодовым MR из [`../WEAR_SINGLE_STATE_RUNTIME_PLAN.md`](../WEAR_SINGLE_STATE_RUNTIME_PLAN.md).

## 1. Область MR

- [ ] В описании назван один migration slice.
- [ ] MR не смешивает state ownership, UAC4/PCM и UI redesign без доказанной необходимости.
- [ ] Перечислены изменяемые owners до и после MR.
- [ ] Указано, какой compatibility adapter остаётся временно.
- [ ] Указан следующий шаг удаления adapter.

## 2. Единственный owner

- [ ] Для каждого изменённого business-поля существует ровно один writable owner.
- [ ] Не добавлен mutable singleton.
- [ ] Не добавлен второй authoritative feature stream.
- [ ] Widget, route и glasses payload не считаются источником business-state.
- [ ] `WearSession` не получает новую mutable business-копию.
- [ ] Один logical screen обслуживается максимум одним runtime/reducer.

### Таблица ownership

Заполнить в PR:

| Business value | Owner до MR | Owner после MR | Удалённая/временная копия |
|---|---|---|---|
| | | | |

## 3. Intent boundary

- [ ] Touch, voice, hardware button и scanner используют semantic intents, если относятся к одному действию.
- [ ] Input adapter не меняет state напрямую.
- [ ] Intent содержит достаточный context без `BuildContext`.
- [ ] Команда старого logical screen не применяется к новому screen.
- [ ] Повторный input имеет явную dedupe/exactly-once семантику.
- [ ] Capability и фактическое исполнение команды совпадают.

## 4. Reducer/state transition

- [ ] Transition атомарен.
- [ ] Невозможные состояния исключены типами или явными invariants.
- [ ] Новый snapshot получает следующую revision.
- [ ] Reducer не вызывает repository, native API, navigation или timer напрямую.
- [ ] Loading/success/error представлены согласованно.
- [ ] Reset/logout не оставляет feature state от старой сессии.

## 5. Async effects

Для каждого effect заполнить:

| Effect | `sessionEpoch` | `operationId` | Условие принятия result | Поведение при stale result |
|---|---|---|---|---|
| | | | | |

Проверки:

- [ ] Result содержит epoch и operation identity.
- [ ] Проверяется ожидаемая task phase.
- [ ] Screen change делает старый result неприменимым, где это требуется.
- [ ] Logout/detached делает старый result неприменимым.
- [ ] Error path защищён теми же guards, что success path.
- [ ] Невозможность физически отменить Future не позволяет stale mutation.
- [ ] Exactly-once effects не запускаются повторно от двойного select/tap.

## 6. Lifecycle

- [ ] `paused`/`hidden` не завершают Wear runtime без причины.
- [ ] `detached`, logout и dispose закрывают input admission.
- [ ] Поздний callback не реактивирует terminal runtime.
- [ ] Foreground service не становится владельцем business-state.
- [ ] Scanner hardware lifecycle отделён от barcode admission.
- [ ] Resource cleanup идемпотентен.

## 7. Navigation

- [ ] Business decision использует logical screen.
- [ ] Actual phone route используется только как observation/admission при активном UI.
- [ ] Navigation request имеет identity.
- [ ] Stale acknowledgement игнорируется.
- [ ] Resume доставляет latest актуальный route.
- [ ] Widget construction не повторяет business entry.
- [ ] Screen-off flow не зависит от нового Flutter frame.

## 8. UI effects

- [ ] `BuildContext` не передаётся в runtime/reducer.
- [ ] Manual input, system settings и dialogs оформлены как UI-only effects либо остаются явно локальными до своего migration slice.
- [ ] UI effect имеет `effectId` и `sessionEpoch`.
- [ ] Effect доставляется не более одного раза.
- [ ] Result старого effect отклоняется.
- [ ] Поведение при inactive phone UI определено явно: defer, alternative или reject.

## 9. Phone/glasses projection

- [ ] Phone и glasses читают один aggregate snapshot.
- [ ] Focus/item/status совпадают.
- [ ] Projection не мутирует store.
- [ ] Projection детерминирована.
- [ ] Envelope/revision не позволяет старому payload перезаписать новый.
- [ ] Transient overlay не откатывает base screen.
- [ ] Reconnect получает latest full snapshot.

## 10. Тесты

### Reducer

- [ ] Happy path.
- [ ] Invalid intent.
- [ ] Stale screen.
- [ ] Stale epoch.
- [ ] Stale operation ID.
- [ ] Terminal runtime.
- [ ] Duplicate input.

### Store/queue

- [ ] Последовательность конкурентных intents.
- [ ] Nested dispatch.
- [ ] Revision monotonicity.
- [ ] Новый subscriber получает current snapshot.

### Effects

- [ ] Success.
- [ ] Error.
- [ ] Result после screen change.
- [ ] Result после logout/detached.
- [ ] Exactly-once operation.

### Projection

- [ ] Phone selector.
- [ ] Glasses payload.
- [ ] Parity одного snapshot.
- [ ] Stale revision rejection.

### Integration

- [ ] Flow работает без widget tree.
- [ ] Flow работает при `phoneUiActive=false`.
- [ ] Resume синхронизирует телефон.
- [ ] Resource teardown не допускает restart.

## 11. Статическая проверка diff

- [ ] Нет нового `Object?` в cross-layer contract без обоснования.
- [ ] Нет нового `!` на optional runtime dependency без construction invariant.
- [ ] Нет fire-and-forget mutation без error/stale handling.
- [ ] Success и catch используют одинаковые identity guards.
- [ ] Timer имеет generation/epoch guard или scheduler effect.
- [ ] Broadcast stream не используется как replayable state без current snapshot.
- [ ] Нет зависимости business load от `initState()`/`build()`.
- [ ] Нет отдельного формирования business payload из widget state.

## 12. Документация

- [ ] Обновлён ownership contract, если решение изменилось.
- [ ] Обновлён migration plan/status.
- [ ] Добавлен или обновлён acceptance checklist.
- [ ] Явно указано, что реально запускалось.
- [ ] Непроверенные hardware assumptions отмечены как риски.

## 13. Rollback

- [ ] Описан безопасный rollback.
- [ ] Rollback не создаёт третий state holder.
- [ ] Repository/native protocol не изменён без необходимости.
- [ ] Compatibility adapter можно вернуть независимо от других slices.

## 14. Финальный review verdict

PR нельзя считать готовым, если выполняется хотя бы одно:

- существует два writable owner одного business value;
- async error path не имеет stale guard;
- actual route управляет screen-off business logic;
- widget lifecycle запускает единственный business load;
- phone и glasses строятся из разных state sources;
- terminal lifecycle допускает поздний restart;
- тест проверяет только mock callback, но не state invariant;
- в PR не указано, что не было запущено.

### Итоговая запись reviewer

```text
Exact HEAD:
Проверенные файлы:
Найденные blocking issues:
Исправленные issues:
Не запущено:
Остаточные hardware risks:
Verdict:
```
