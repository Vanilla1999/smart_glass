# Проверка MR-S1: Wear runtime store shell

MR: `feat(wear): add the MR-S1 runtime store shell`

Этот MR не переносит feature ownership. Его задача — доказать форму store, по которой будут выполняться следующие stacked MR.

## Что должно остаться неизменным

- `WearFlowController` остаётся владельцем текущего logical flow.
- `WearPrinterRuntime`, `WearScanRuntime` и `WearAvailabilityRuntime` остаются единственными writable feature owners.
- `WearSession` пока не переносится.
- Phone/glasses production projection не переключается на новый store.
- Native scanner, UAC4, PCM, Vosk, Firebird и UI layout не меняются.

Если MR требует изменить любой из этих пунктов, scope MR-S1 нарушен.

## Локальные тесты

```bash
flutter test \
  test/wear_runtime_store_test.dart \
  test/wear_runtime_store_atomicity_test.dart \
  test/wear_screen_ownership_registry_test.dart
```

## Контракты, которые должны быть доказаны

### Replayable state

- новый subscriber сразу получает current snapshot;
- no-op не публикует новый snapshot;
- committed revision публикуется один раз;
- после dispose stream закрывается.

### Version tuple

- внутри epoch revision возрастает только при state change;
- новый epoch сбрасывает revision в `0`;
- `(epoch + 1, 0)` новее любой revision старого epoch;
- stale legacy snapshot не меняет state.

### Dispatch queue

- concurrent intents применяются в порядке очереди;
- nested dispatch не re-enter reducer и идёт в хвост;
- reducer exception отклоняет только текущий intent;
- последующий intent продолжает обрабатываться.

### Commit/effect/receipt

- candidate state и effect identities проверяются до публикации;
- expected operation ID committed до effect start;
- receipt завершается после effect scheduling;
- receipt не ждёт завершения внешнего effect;
- invalid effect identity не оставляет partial committed state;
- rejected intent не запускает effect.

### Async result admission

- result принимается только для current epoch и expected operation ID;
- stale result не меняет state и revision;
- unexpected effect error может быть превращён в typed result intent;
- late effect result после terminal barrier игнорируется.

### Terminal lifecycle

- `dispose()` идемпотентен;
- terminal snapshot supersede текущий epoch;
- expected operations очищаются;
- queued receipts завершаются terminal rejection;
- blocked external effect не удерживает dispose;
- dispatch после terminal не мутирует state.

### Ownership

- legacy mirror однонаправленный;
- aggregate snapshot не предоставляет setter в legacy owner;
- duplicate logical-screen claim падает при построении registry;
- shell не содержит printer/scan/availability writable slices.

## Статическое ревью

Обратить внимание на следующие ошибки:

- state публикуется раньше полной проверки effects;
- `await` external effect находится внутри reducer queue;
- effect напрямую меняет state;
- broadcast stream не отдаёт current snapshot новому subscriber;
- no-op увеличивает revision;
- dispose ждёт зависший effect;
- error path не использует ту же operation identity, что success;
- compatibility mirror имеет обратный mutation callback;
- feature state случайно продублирован в aggregate root.

## Stop/revert

Остановить merge, если:

- появляется второй writable owner любого business value;
- terminal intent может ждать network/native effect;
- invalid effect способен оставить committed state;
- caller не получает typed accepted/rejected receipt;
- тесты требуют построения feature widget tree;
- MR меняет production feature behavior.

## Что не проверял агент

Агент не запускал Flutter, analyzer, тесты, Gradle, сборку или устройство. После локального прогона результат нужно дописать сюда или в PR comment с exact HEAD.
