# Проверка MR-S6: authoritative availability slice

## Область

MR-S6 переносит в единый `WearRuntimeState`:

- группы и товары доступности;
- выбранную группу и товар;
- direct-scan и duplicate selection;
- пошаговый availability-check;
- focus;
- barcode dedupe;
- fill count/message;
- photo/print/complete/fill operation identity;
- loading/error.

`WearAvailabilityRuntime` после MR является только compatibility input/projection adapter. В нём не должно быть mutable business-полей.

## Ownership ledger

| Значение | Owner до MR-S6 | Owner после MR-S6 |
|---|---|---|
| Availability flow/step | legacy `WearAvailabilityRuntime` | `WearAvailabilityTaskSlice` |
| Groups/products/duplicates | legacy runtime | aggregate slice |
| Availability focus | legacy runtime | aggregate slice |
| Fill count/dedupe | legacy runtime | aggregate slice |
| Repository/photo/print | runtime methods | versioned effects |
| Phone/glasses view | runtime snapshot | read-only adapter projection |

## Статический review

- [ ] `wear_availability_runtime.dart` экспортирует adapter, а не старый owner.
- [ ] Adapter не содержит writable groups/products/step/focus/count.
- [ ] Reducer не вызывает repository, navigation, photo или print.
- [x] Все external operations имеют `sessionEpoch + operationId`; operation identity не переиспользуется после same-epoch adapter dispose/reset.
- [x] Success и error проверяют одинаковые epoch/operation/busy guards и отклоняют stale result симметрично.
- [ ] Screen change supersede все `availability.*` expected operations.
- [ ] Same-screen widget re-entry не перезапускает активный effect.
- [ ] List-changing result сбрасывает focus в допустимый индекс.
- [ ] Fill reset и fill add используют общий busy gate.
- [ ] Duplicate selection запрещает новый barcode.
- [ ] Completion перечитывает groups после repository mutation.
- [ ] Auth/logout/terminal одним snapshot очищают printer, scan и availability.
- [ ] Photo/print/fill Future не блокируют dispatch queue.
- [x] Executor lease деактивируется при dispose adapter; replacement adapter покрыт сценарием с заблокированным старым effect.

## Точечные тесты владельца

```bash
flutter test \
  test/wear_runtime_availability_slice_test.dart \
  test/wear_availability_runtime_test.dart \
  test/wear_runtime_availability_review_guards_test.dart \
  test/wear_runtime_stabilization_test.dart
```

Связанные тесты стека:

```bash
flutter test \
  test/wear_runtime_store_test.dart \
  test/wear_runtime_control_slices_test.dart \
  test/wear_runtime_printer_slice_test.dart \
  test/wear_runtime_scan_slice_test.dart
```

## Ручные сценарии

### Группы и товары

1. Открыть список групп.
2. Убедиться, что loading виден до ответа repository.
3. Выбрать группу.
4. Проверить, что телефон и очки показывают один список и focus.
5. Вернуться и открыть группу повторно — загрузка не должна дублироваться без причины.

### Direct scan

1. ШК без совпадений → сообщение об отсутствии.
2. Один товар → переход к проверке.
3. Несколько товаров → список дублей.
4. Во время duplicate selection новый ШК не принимается.
5. Выбор дубля переводит к тому же товару на телефоне и очках.

### Пошаговая проверка

Проверить ветви:

- `yes/no`;
- product barcode;
- price-tag barcode;
- outdated price tag и print;
- photo capture;
- manual inventory;
- completion.

После completion counters групп должны быть перечитаны, а не взяты из старого snapshot.

### Fill

1. Сканировать товар — count увеличивается один раз.
2. Повтор delivery того же ШК/step не создаёт вторую запись.
3. Запустить reset и сразу прислать barcode — barcode отклоняется.
4. После завершения reset count равен нулю, dedupe очищен.
5. Ошибка fill-add допускает повторный scan.

### Stale results

- начать direct scan и перейти на fill до ответа;
- начать photo и выполнить logout;
- начать print и открыть другой logical screen;
- начать fill reset и завершить session.

Ни success, ни error старой операции не должны менять новый snapshot.

## Stop/revert

MR не готов, если:

- production DI всё ещё создаёт legacy mutable availability owner;
- logical screen и task screen расходятся после failed navigation;
- error старой операции попадает в новый screen;
- fill reset выполняется одновременно с fill add;
- completion показывает старые group counters;
- adapter dispose завершает общий authority;
- один business value writable одновременно в runtime и aggregate slice.

## Не запускалось агентом

По требованию владельца не запускались Flutter, analyzer, tests, Gradle и builds. Чек-лист является спецификацией для последующей локальной и аппаратной проверки.
