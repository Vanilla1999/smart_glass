# Проверка MR-S4: authoritative printer slice

Stack base: MR-S3 (`refactor/wear-runtime-control-slices`).

## Ownership transfer

| Значение | До MR-S4 | После MR-S4 | Compatibility |
|---|---|---|---|
| printer list/loading/error | `WearPrinterRuntime` fields | `WearPrinterTaskSlice` | runtime state adapter |
| white/yellow step and focus | `WearPrinterRuntime` | aggregate printer slice | controller/widget methods dispatch intents |
| final printer pair | runtime + mutable `WearSession` | aggregate printer slice | `WearSession` read-only getter/stream |
| load/navigation work | runtime methods | versioned effects | leased printer executor |
| scan/availability | legacy runtimes | unchanged | MR-S5/MR-S6 |

## Локальные тесты

```bash
flutter test \
  test/wear_runtime_printer_slice_test.dart \
  test/wear_runtime_printer_compatibility_test.dart \
  test/wear_printer_runtime_test.dart \
  test/wear_runtime_stabilization_test.dart
```

Связанные stacked tests:

```bash
flutter test \
  test/wear_runtime_store_test.dart \
  test/wear_runtime_session_authority_test.dart \
  test/wear_runtime_control_slices_test.dart
```

## Load/effect contract

- loading snapshot и expected operation ID committed до loader call;
- dispatch receipt не ждёт loader;
- success/error используют одинаковые epoch/operation/screen guards;
- session clear и terminal делают late result stale;
- duplicate load во время loading rejected как busy;
- один effect domain имеет только один active executor;
- adapter dispose освобождает executor lease и не уничтожает authority.

## Selection contract

- сначала выбирается white, затем yellow;
- yellow list исключает выбранный white;
- один printer не может быть обеими ролями;
- focus всегда clamped к visible list;
- page movement использует тот же focus state;
- return-selection mode не запускает navigation;
- обычный complete selection создаёт ровно один navigation effect;
- повторный select не дублирует navigation;
- `WearSession.printerSelectionOrNull` совпадает с aggregate slice.

## Reload reconciliation

1. Оба ID существуют: пара сохраняется и перепривязывается к fresh models.
2. White исчез: white/selection очищаются, step=`white`.
3. Yellow исчез: fresh white сохраняется, selection очищается, step=`yellow`.

## Session/terminal

- session clear одним snapshot очищает identity, controls и printer task;
- terminal очищает printer list/selection;
- printer compatibility adapter не может оживить terminal authority;
- late load/navigation result не меняет следующий epoch.

## Статическое ревью

Блокировать MR, если:

- `WearPrinterRuntime` содержит mutable `_printers`, `_whitePrinter` или `_selection`;
- `WearSession` хранит отдельную printer pair;
- loader awaited внутри dispatch queue;
- navigation effect запускается до committed selection/request identity;
- два active printer executors разрешены;
- reload сравнивает object identity вместо stable printer ID;
- error path не проверяет operation identity;
- adapter dispose закрывает общий authority/store;
- scan или availability ownership случайно перенесён вместе с printer.

## Ручная проверка позже

1. Открыть printer screen: loading виден одновременно на телефоне и очках.
2. Выбрать white голосом/кнопкой/touch, убедиться, что yellow list исключает его.
3. Выбрать yellow: один переход на scan idle.
4. Вернуться и выполнить reload всех трёх reconciliation вариантов.
5. Выключить экран во время load: результат принимается только для current epoch/screen.
6. Logout во время load: late result не возвращает printer state.

## Не запускалось агентом

Flutter, analyzer, tests, Gradle, build и устройство не запускались.
