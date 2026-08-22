# Проверка MR-S1: Wear runtime store shell

## Назначение

Этот чек-лист относится только к первому кодовому этапу single-state roadmap:

```text
MR-S1 — store shell, immutable snapshot, version contract,
dispatch queue, effect boundary, typed receipt и terminal dispose.
```

MR-S1 не переносит printer, scan, availability, voice или scanner business ownership. Их текущие owners остаются единственными writable owners. Новый store публикует только read-only compatibility view `WearFlowController.state`.

## Ownership ledger

| Business value | Writable owner до MR-S1 | Writable owner после MR-S1 | Новый store |
|---|---|---|---|
| Logical Wear flow | `WearFlowController` | `WearFlowController` | read-only `WearLegacyRuntimeView` |
| Printer state | `WearPrinterRuntime` / текущий compatibility path | без изменений | не копируется |
| Scan state | `WearScanRuntime` | без изменений | не копируется |
| Availability state | `WearAvailabilityRuntime` | без изменений | не копируется |
| Session/printer selection | `WearSession` и текущий runtime до соответствующего migration slice | без изменений | не копируется |
| Runtime version/terminal shell | отсутствует | `SerializedWearRuntimeStore` | authoritative только для shell metadata |
| Expected effect identity shell | отсутствует | `SerializedWearRuntimeStore` | authoritative |

Критический запрет:

```text
MR-S1 не должен записывать обратно в WearFlowController,
feature runtimes или WearSession.
```

## Что проверить статически

### Immutable root

- [ ] `WearRuntimeState` не предоставляет setters.
- [ ] `WearExpectedOperations.values` нельзя изменить.
- [ ] Version меняет только store.
- [ ] Read/projection не увеличивает revision.
- [ ] Legacy adapter хранит текущий `WearFlowState` только как read-only snapshot.
- [ ] В aggregate shell нет PCM, audio buffers, native controller или `BuildContext`.

### Version contract

- [ ] Сравнение выполняется tuple-порядком `(sessionEpoch, revision)`.
- [ ] Новый epoch новее любого revision старого epoch.
- [ ] Accepted state change увеличивает revision ровно на один.
- [ ] No-op и rejection не увеличивают revision.
- [ ] Reducer не может самостоятельно выбрать опубликованную revision.

### Dispatch queue

- [ ] Все intents проходят через одну очередь.
- [ ] Reducer вызывается без `await` внешней операции.
- [ ] Nested dispatch добавляется в хвост и не вызывает reducer re-entry.
- [ ] Ошибка одного reducer intent не оставляет processing guard навсегда.
- [ ] Следующий intent обрабатывается после controlled internal rejection.

### Commit/effect/receipt ordering

Порядок должен быть именно таким:

```text
reduce
-> commit immutable snapshot
-> publish snapshot
-> schedule effects
-> complete WearDispatchResult
```

Проверить:

- [ ] Expected operation identity находится в state до `effectRunner.schedule()`.
- [ ] Effect runner не получает setter store.
- [ ] Effect может вернуть только typed result intent.
- [ ] Receipt не ждёт завершения repository/native Future.
- [ ] Rejected/no-op intent не запускает effect.
- [ ] Re-entrant terminal barrier прекращает scheduling оставшихся effects.

### Terminal/dispose

- [ ] `dispose()` сразу закрывает admission.
- [ ] Terminal snapshot публикуется один раз.
- [ ] Pending queue получает typed `terminal` rejection.
- [ ] Expected operations очищаются.
- [ ] Effect runner dispose не обязан ждать зависший внешний Future.
- [ ] Поздний effect result получает terminal rejection и не мутирует state.
- [ ] Повторный `dispose()` безопасен.
- [ ] State stream завершается после terminal snapshot.

### Replayable state

- [ ] Новый subscriber немедленно получает current snapshot.
- [ ] Current snapshot доступен через `state`.
- [ ] Одна committed revision публикуется не более одного раза.
- [ ] После dispose новый subscriber видит final terminal snapshot и завершение stream.

### Compatibility facade

- [ ] Adapter читает `WearFlowController.state`, но не вызывает его mutation API.
- [ ] Повторная синхронизация того же object/revision является no-op.
- [ ] Реальное изменение flow создаёт ровно одну новую store revision.
- [ ] Phone/glasses provisional selectors возвращают один legacy snapshot.
- [ ] Facade можно удалить отдельно без изменения legacy behavior.

### Runtime ownership

- [ ] `CompositeWearBackgroundRuntime` копирует список owners как unmodifiable.
- [ ] Два runtime, заявившие один `WearScreenId`, приводят к fail-fast `StateError`.
- [ ] Проверка выполняется до подписки на child streams.
- [ ] Существующий уникальный ownership не меняет runtime behavior.

## Тесты, которые должен запустить владелец

Точечный тест MR-S1:

```bash
flutter test test/wear_runtime_store_test.dart
```

Связанные regression tests:

```bash
flutter test \
  test/wear_background_runtime_readiness_test.dart \
  test/wear_flow_controller_test.dart \
  test/wear_flow_coordinator_integration_test.dart \
  test/wear_runtime_stabilization_test.dart
```

## На что обратить внимание при падении

### Тест зависает

Проверить:

- `_draining` снимается в `finally`;
- effect Future случайно не `await`-ится dispatch queue;
- nested dispatch действительно ставится в хвост;
- dispose не ждёт in-flight fake effect.

### Лишняя revision

Проверить:

- initial compatibility snapshot и первый `synchronize()` представляют один object/revision;
- projection/read не вызывает dispatch;
- same-source snapshot сравнивается не только по числу revision, но и по source/identity;
- no-op reduction не помечена как `stateChanged`.

### Потерянное состояние

MR-S1 не должен заменять текущий flow. Если после подключения compatibility bundle изменяется `WearFlowController.state`, это блокирующая ошибка: направление зависимости перепутано.

### Effect стартует слишком рано

Если fake runner не видит expected operation ID в current state, нарушен ADR-0002. Effect нельзя запускать до commit.

### После dispose что-то оживает

Любой accepted dispatch или новая non-terminal revision после terminal snapshot является P0.

## Что сознательно не проверено в этом MR

- реальный printer/scan/availability ownership transfer;
- native scanner acknowledgement через новый receipt;
- phone route migration;
- voice/scanner/connectivity slices;
- glasses transport envelope;
- screen-off hardware behavior.

Они относятся к MR-S2 и последующим stacked MR.

## Выполнение в этой сессии

По требованию владельца не запускались:

- `flutter analyze`;
- `flutter test`;
- Gradle tasks;
- Flutter/Android build.

Проверка выполняется статическим чтением diff, API boundaries и control flow. Перед последующим merge владелец должен отметить результаты команд выше.
