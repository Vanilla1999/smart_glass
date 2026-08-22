# Review checklist для MR миграции Wear single-state

Этот шаблон применяется ко всем кодовым MR из [`../WEAR_SINGLE_STATE_RUNTIME_PLAN.md`](../WEAR_SINGLE_STATE_RUNTIME_PLAN.md) и учитывает [`../decisions/ADR-0002-WEAR_STORE_EXECUTION_ORDER.md`](../decisions/ADR-0002-WEAR_STORE_EXECUTION_ORDER.md).

## 1. Область MR

- [ ] В описании назван один migration slice.
- [ ] MR не смешивает state ownership, UAC4/PCM и UI redesign без доказанной необходимости.
- [ ] Перечислены изменяемые owners до и после MR.
- [ ] Указано, какой compatibility adapter остаётся временно.
- [ ] Указан следующий шаг и срок удаления adapter.
- [ ] Явно перечислено, какие business values MR не мигрирует.

## 2. Единственный owner

- [ ] Для каждого изменённого business value существует ровно один writable owner.
- [ ] Не добавлен mutable singleton.
- [ ] Не добавлен второй authoritative feature stream.
- [ ] Widget, route и glasses payload не считаются источником business-state.
- [ ] `WearSession` не получает новую mutable business-копию.
- [ ] Один logical screen обслуживается максимум одним runtime/reducer.
- [ ] Нет dual write в legacy owner и aggregate slice.
- [ ] Read-only mirror нельзя изменить через public/internal API.
- [ ] Adapter не хранит самостоятельную mutable копию.

### Ownership ledger

Заполнить в PR:

| Business value | Owner до MR | Owner после MR | Read-only compatibility view | Этап удаления |
|---|---|---|---|---|
| | | | | |

Блокирующая ошибка: один value указан writable одновременно в двух компонентах.

## 3. Version и immutability contract

- [ ] `sessionEpoch` имеет однозначный lifecycle scope.
- [ ] `revision` монотонна внутри epoch.
- [ ] Ordering сравнивается по `(sessionEpoch, revision)`, а не только по revision.
- [ ] Новый epoch не принимает payload/result старого epoch.
- [ ] No-op/rejected intent не публикует snapshot и не увеличивает revision.
- [ ] Регистрация pending operation/effect увеличивает revision как реальная state mutation.
- [ ] Projection/read не увеличивает revision.
- [ ] Aggregate state и вложенные collections immutable/unmodifiable.
- [ ] Equality/selectors не зависят от mutable collection identity.
- [ ] Process restart semantics явно не обещают больше Variant A.

## 4. Intent и dispatch boundary

- [ ] Touch, voice, hardware button и scanner используют semantic intents, если относятся к одному действию.
- [ ] Input adapter не меняет state напрямую.
- [ ] Intent содержит достаточный context без `BuildContext`.
- [ ] Команда старого logical screen не применяется к новому screen.
- [ ] Повторный input имеет явную dedupe/exactly-once семантику.
- [ ] Capability и фактическое исполнение команды совпадают.
- [ ] Legacy entry point либо делегирует единственному owner, либо помечен к удалению.
- [ ] Dispatch возвращает typed accepted/rejected receipt.
- [ ] Reject reason различает stale screen, terminal, unsupported, duplicate и busy.
- [ ] Receipt возвращает epoch/revision после reducer-processing.
- [ ] Receipt не ждёт завершения внешнего effect.
- [ ] Scanner/native acknowledgement основан на receipt, а не на факте вызова callback.
- [ ] Receipt не хранится как второй mutable state source.

## 5. Store queue и execution order

- [ ] Intents обрабатываются последовательно.
- [ ] Nested dispatch ставится в хвост и не re-enter reducer.
- [ ] Ошибка одного intent не оставляет очередь навсегда в processing state.
- [ ] Queue ordering зафиксирован тестами.
- [ ] После terminal/reset ожидающие inputs не продолжают mutation.
- [ ] Каждый queued intent получает ровно один receipt.
- [ ] Expected `operationId` committed в state до запуска effect.
- [ ] Committed snapshot опубликован до effect result.
- [ ] Effect scheduled/registered до завершения accepted receipt.
- [ ] Rejected intent не запускает effect.
- [ ] Медленный external effect не удерживает dispatch queue.
- [ ] Back/home/logout/terminal intent не ждёт unrelated network/print/photo effect.

## 6. State stream и dispose

- [ ] `state` всегда содержит последний committed snapshot.
- [ ] Новый subscriber сразу получает current snapshot.
- [ ] Одна authoritative revision не публикуется повторно без причины.
- [ ] No-op не создаёт state event.
- [ ] `dispose()` идемпотентен.
- [ ] Dispose создаёт terminal barrier до освобождения adapters/resources.
- [ ] Dispatch после terminal не мутирует state и имеет одну документированную rejection/error policy.
- [ ] State stream закрывается после terminal cleanup.
- [ ] Поздний effect result после dispose игнорируется.
- [ ] Зависший внешний effect не блокирует terminal barrier бесконечно.

## 7. Reducer/state transition

- [ ] Transition атомарен.
- [ ] Невозможные состояния исключены типами или явными invariants.
- [ ] Новый snapshot получает следующую revision только при изменении.
- [ ] Reducer не вызывает repository, native API, navigation или timer напрямую.
- [ ] Loading/success/error представлены согласованно.
- [ ] Reset/logout не оставляет feature state от старой сессии.
- [ ] Status/overlay не дублируется в task и widget timer.
- [ ] Reducer формирует receipt согласованно с transition/effects.
- [ ] Reducer exception не публикует частичный state.

## 8. Async effects и concurrency

Для каждого effect заполнить:

| Effect | `sessionEpoch` | `operationId` | Concurrency/exclusive policy | Условие принятия result | Поведение при stale result |
|---|---|---|---|---|---|
| | | | | | |

Проверки:

- [ ] Effect handler не имеет setter-доступа к store state.
- [ ] Effect возвращает success/error только через typed result intent.
- [ ] Result содержит epoch и operation identity.
- [ ] Проверяется ожидаемая task phase.
- [ ] Screen change делает старый result неприменимым, где это требуется.
- [ ] Logout/detached делает старый result неприменимым.
- [ ] Error path проходит ту же admission function, что success path.
- [ ] Невозможность физически отменить Future не позволяет stale mutation.
- [ ] Exactly-once effects не запускаются повторно от двойного select/tap.
- [ ] Rejected stale result имеет различимую причину в diagnostics.
- [ ] Pending operation ID очищается/заменяется атомарно.
- [ ] Независимые effects могут завершаться out of order безопасно.
- [ ] Exclusive resource имеет mutex/dedupe/coordinator policy.
- [ ] Нет случайной глобальной сериализации всех effects через `await` в dispatch queue.

## 9. Lifecycle и runtime-control slices

- [ ] `paused`/`hidden` не завершают Wear runtime без причины.
- [ ] `detached`, logout и dispose закрывают input admission.
- [ ] Поздний callback не реактивирует terminal runtime.
- [ ] Foreground service не становится владельцем business-state.
- [ ] Scanner hardware lifecycle отделён от barcode admission.
- [ ] Resource cleanup идемпотентен.
- [ ] Epoch/reset policy одинакова для success и error paths.
- [ ] Voice coarse phase имеет одного owner.
- [ ] Scanner hardware/admission state имеет одного owner.
- [ ] Connectivity coarse observation имеет одного owner.
- [ ] `WearModuleApp`, scanner policy и reporters являются adapters/observers, а не параллельными owners.
- [ ] PCM chunks, audio buffers, high-frequency level и native lease objects не помещены в aggregate state.
- [ ] High-frequency audio callbacks не создают aggregate revision на каждый packet/level.

## 10. Navigation

- [ ] Business decision использует logical screen.
- [ ] Actual phone route используется только как observation/admission при активном UI.
- [ ] Navigation request имеет identity.
- [ ] Stale acknowledgement игнорируется.
- [ ] Resume доставляет latest актуальный route.
- [ ] Widget construction не повторяет business entry.
- [ ] Screen-off flow не зависит от нового Flutter frame.
- [ ] Route observer не запускает feature load напрямую.
- [ ] Navigation delivery одного pending request имеет exclusive/exactly-once policy.

## 11. UI effects

- [ ] `BuildContext` не передаётся в runtime/reducer.
- [ ] Manual input, system settings и dialogs оформлены как UI-only effects либо остаются явно локальными до своего migration slice.
- [ ] UI effect имеет `effectId` и `sessionEpoch`.
- [ ] Pending effects являются bounded state, а не append-only history.
- [ ] Определён maximum/one-per-kind policy.
- [ ] Rebuild/reconnect не создаёт второй semantic effect.
- [ ] Acknowledgement удаляет effect атомарно.
- [ ] Result старого effect отклоняется.
- [ ] Reset удаляет effects старого epoch.
- [ ] Поведение при inactive phone UI определено явно: defer, alternative или reject.

## 12. Phone/glasses projection

- [ ] Phone и glasses читают один aggregate snapshot либо один read-only adapter текущего owner на переходном этапе.
- [ ] Focus/item/status совпадают.
- [ ] Projection не мутирует store.
- [ ] Projection детерминирована.
- [ ] Envelope сравнивает `(sessionEpoch, revision)`.
- [ ] Младший payload не перезаписывает старший.
- [ ] Transient overlay не откатывает base screen.
- [ ] Reconnect получает latest full snapshot.
- [ ] Legacy projection adapter не принимает business decisions.
- [ ] Projection read не увеличивает revision.

## 13. Тесты

### Ownership/compatibility

- [ ] Read-only mirror совпадает с текущим legacy owner.
- [ ] Mirror нельзя изменить.
- [ ] Ownership transfer удаляет/замораживает legacy writer.
- [ ] Duplicate screen owner отклоняется.

### Reducer/receipt

- [ ] Happy path + accepted receipt.
- [ ] Invalid/unsupported intent + typed rejected receipt.
- [ ] No-op intent без новой revision.
- [ ] Stale screen.
- [ ] Stale epoch.
- [ ] Stale operation ID.
- [ ] Terminal runtime.
- [ ] Duplicate input.
- [ ] Receipt не ждёт внешнего effect.

### Store/queue/order

- [ ] Последовательность конкурентных intents.
- [ ] Nested dispatch в хвост.
- [ ] Queue recovery после exception.
- [ ] Revision monotonicity.
- [ ] No-op не меняет revision.
- [ ] Новый subscriber получает current snapshot.
- [ ] Каждый intent завершает свой receipt ровно один раз.
- [ ] Commit происходит до effect start.
- [ ] Effect scheduled до receipt completion.
- [ ] Rejected intent не schedules effect.
- [ ] Terminal intent не ждёт blocked unrelated effect.

### Effect concurrency

- [ ] Независимые operations могут завершиться в обратном порядке.
- [ ] Stale result старой operation отклоняется.
- [ ] Exclusive effect не запускается дважды.
- [ ] Success/error используют один guard.

### Dispose

- [ ] Dispose идемпотентен.
- [ ] Dispatch после terminal не мутирует state.
- [ ] Pending receipts завершаются по документированной policy.
- [ ] Поздний effect result игнорируется.
- [ ] Stream/subscriptions закрываются.
- [ ] Hung fake effect не блокирует terminal barrier.

### Runtime control

- [ ] Voice coarse observation.
- [ ] Scanner hardware/admission independence.
- [ ] Terminal admission close.
- [ ] Stale native callback rejection.
- [ ] Connectivity observation ordering.
- [ ] PCM/audio level не меняют aggregate state.

### UI effects

- [ ] Rebuild/reconnect не дублирует effect.
- [ ] Ack удаляет effect.
- [ ] Stale ack/result отклоняется.
- [ ] Queue bound соблюдается.

### Projection

- [ ] Phone selector.
- [ ] Glasses payload.
- [ ] Parity одного snapshot.
- [ ] Stale tuple rejection.
- [ ] Projection не меняет revision.

### Integration

- [ ] Flow работает без widget tree.
- [ ] Flow работает при `phoneUiActive=false`.
- [ ] Resume синхронизирует телефон.
- [ ] Resource teardown не допускает restart.

## 14. Статическая проверка diff

- [ ] Нет нового `Object?` в cross-layer contract без обоснования.
- [ ] Нет нового `!` на optional runtime dependency без construction invariant.
- [ ] Нет fire-and-forget mutation без error/stale handling.
- [ ] Success и catch используют одинаковые identity guards.
- [ ] Timer имеет generation/epoch guard или scheduler effect.
- [ ] Broadcast stream не используется как replayable state без current snapshot contract.
- [ ] Нет зависимости business load от `initState()`/`build()`.
- [ ] Нет отдельного формирования business payload из widget state.
- [ ] Нет dual-write «для совместимости».
- [ ] Нет unbounded pending event/effect collection.
- [ ] Read-only adapter действительно не содержит setter/mutation path.
- [ ] Dispatch receipt не маскирует rejected intent как success.
- [ ] Aggregate state не содержит PCM/audio/native resource objects.
- [ ] External repository/native call не awaited внутри dispatch queue до следующего intent.
- [ ] Effect start не предшествует commit expected operation identity.
- [ ] Dispose имеет terminal barrier до закрытия stream/resources.

## 15. Документация

- [ ] Обновлён ownership contract, если решение изменилось.
- [ ] Обновлён ownership ledger.
- [ ] Обновлён migration plan/status.
- [ ] Execution/concurrency policy соответствует ADR-0002.
- [ ] Добавлен или обновлён acceptance checklist.
- [ ] Явно указано, что реально запускалось.
- [ ] Непроверенные hardware assumptions отмечены как риски.

## 16. Rollback

- [ ] Описан безопасный rollback.
- [ ] Rollback не создаёт третий state holder.
- [ ] Repository/native protocol не изменён без необходимости.
- [ ] Compatibility adapter можно вернуть независимо от других slices.
- [ ] Ownership ledger после rollback остаётся однозначным.

## 17. Финальный review verdict

PR нельзя считать готовым, если выполняется хотя бы одно:

- существует два writable owner одного business value;
- read-only mirror можно изменять;
- async error path не имеет того же stale guard, что success;
- dispatch не возвращает честный typed receipt;
- effect стартует до commit operation identity;
- медленный effect блокирует back/logout/terminal queue;
- dispose не создаёт terminal barrier;
- actual route управляет screen-off business logic;
- widget lifecycle запускает единственный business load;
- phone и glasses строятся из независимых mutable sources;
- voice/scanner/connectivity control остаётся раздвоенным;
- aggregate state обновляется от каждого PCM/audio-level event;
- terminal lifecycle допускает поздний restart;
- no-op intent беспричинно увеличивает revision;
- UI effects хранятся без bound/ack policy;
- тест проверяет только mock callback, но не state invariant;
- в PR не указано, что не было запущено.

### Итоговая запись reviewer

```text
Exact HEAD:
Проверенные файлы:
Ownership transfers:
Read-only adapters:
Dispatch receipt semantics:
Execution/effect concurrency:
Dispose policy:
Найденные blocking issues:
Исправленные issues:
Не запущено:
Остаточные hardware risks:
Verdict:
```
