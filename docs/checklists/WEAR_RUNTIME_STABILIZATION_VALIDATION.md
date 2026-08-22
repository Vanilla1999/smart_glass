# Проверка стабилизации Wear runtime

Документ относится к MR `fix/wear-runtime-barcode-scanner-stabilization` и фиксирует обязательные проверки перед использованием изменений как основы для дальнейшего перехода к единому Wear state.

## Что именно проверяется

Изменения должны подтвердить следующие инварианты:

1. `WearFlowController` и application runtimes владеют logical/business state.
2. Телефонный route является наблюдением UI и не блокирует screen-off flow.
3. Barcode для мигрированных экранов проходит только через runtime.
4. Scanner hardware lifecycle отделён от barcode admission.
5. События старого экрана, старой операции или завершённого lifecycle не изменяют новый state.
6. Телефон и очки получают согласованный результат одного runtime flow.
7. Android foreground service остаётся host/liveness-слоем и не становится владельцем Dart state.

## Ограничение проверки в MR

При подготовке MR не запускались:

- `flutter analyze`;
- `flutter test`;
- Gradle-задачи;
- сборка приложения.

Поэтому пункты ниже являются обязательной локальной и аппаратной проверкой владельца проекта.

## Минимальный локальный прогон

Сначала выполнить новые точечные regression tests:

```bash
flutter test \
  test/wear_background_runtime_readiness_test.dart \
  test/wear_scanner_runtime_policy_test.dart \
  test/wear_runtime_stabilization_test.dart
```

Затем связанные существующие тесты:

```bash
flutter test \
  test/wear_flow_controller_test.dart \
  test/wear_availability_runtime_test.dart \
  test/wear_printer_runtime_test.dart \
  test/wear_barcode_dispatcher_test.dart \
  test/wear_scanner_runtime_test.dart
```

После этого желательно выполнить полный `flutter test`, потому что изменения затрагивают routing input, lifecycle и общую runtime-композицию.

## Критические сценарии на устройстве

### 1. Runtime-first barcode при активном UI

Проверить отдельно:

- availability direct scan;
- availability check на шаге сканирования товара;
- availability check на шаге сканирования ценника;
- availability fill;
- обычный scan idle.

Ожидаемый результат:

- один физический scan создаёт ровно одну runtime-операцию;
- нет повторного repository вызова;
- нет двойного перехода;
- нет `StackOverflow`;
- UI телефона и очков показывают один и тот же результат.

Признак регрессии:

- один barcode добавляет две позиции;
- дважды открывается следующий экран;
- scan обрабатывается старым widget callback;
- fill зависает или приложение падает.

### 2. Ручной ввод

1. Открыть manual input с barcode-экрана.
2. Пока открыт input route, выполнить физическое сканирование.
3. Затем отправить код кнопкой подтверждения.

Ожидаемый результат:

- физический barcode не уходит в предыдущий logical screen;
- подтверждённый ручной код проходит один раз через `WearFlowController.handleBarcode`;
- после возврата scanner admission восстанавливается только для актуального logical screen.

### 3. Screen-off flow при отстающем phone route

1. Авторизоваться.
2. Выключить экран телефона.
3. Голосом пройти к экрану, принимающему barcode, например `scanIdle`.
4. Выполнить сканирование до включения телефона.
5. Включить телефон.

Ожидаемый результат:

- scanner hardware остаётся prepared;
- barcode принимается logical runtime;
- очки обновляются без участия phone widget tree;
- после resume телефон догоняет logical screen;
- barcode не теряется и не выполняется повторно.

### 4. Быстрый input сразу после перехода

1. Голосом или кнопкой перейти на новый runtime-screen.
2. Сразу, не ожидая визуального обновления телефона, нажать `select` или выполнить scan.

Ожидаемый результат:

- событие ждёт завершения `enterScreen()` целевого runtime;
- оно не выполняется на старом внутреннем screen;
- после готовности выполняется не более одного раза.

### 5. Отмена старого input новым logical screen

1. Начать переход на экран с медленной загрузкой.
2. До завершения загрузки отправить barcode или `select`.
3. Перейти на другой logical screen.

Ожидаемый результат:

- ожидающий input старого screen завершается как непринятый;
- переход на новый screen не ждёт старую зависшую загрузку;
- старый runtime не получает barcode/command;
- позднее завершение старого `enterScreen()` не восстанавливает старую готовность.

### 6. Voice clarification

1. Получить неоднозначное голосовое совпадение на runtime-owned списке.
2. Открыть clarification.
3. Выбрать один из вариантов голосом или кнопкой.

Ожидаемый результат:

- source runtime сохраняет список для выбора кандидата;
- выбранный `itemId` выполняется в source runtime;
- через clarification нельзя отправить обычный barcode, phrase или command в старый screen;
- после выбора state возвращается к правильному source flow.

### 7. Availability duplicate barcode

1. Отсканировать код, которому соответствуют две позиции.
2. Проверить телефон и очки.
3. До выбора позиции отсканировать другой код.
4. Выбрать позицию.

Ожидаемый результат:

- очки показывают `Дубль ШК` и список позиций;
- focus и страницы совпадают с runtime state;
- новый barcode во время duplicate selection отклоняется;
- после выбора открывается check именно выбранного товара.

### 8. Availability fill reset

1. Добавить несколько позиций в fill.
2. Запустить очистку.
3. Пока repository reset не завершён, выполнить scan.
4. После завершения выполнить scan ещё раз.

Ожидаемый результат:

- во время reset runtime находится в `busy`;
- barcode admission выключен;
- scan во время reset не добавляет позицию;
- после успешного reset count равен нулю;
- следующий scan после reset принимается;
- при ошибке reset старые данные не очищаются молча, а runtime показывает ошибку.

### 9. Stale async result

Проверить два варианта:

- fill-add начался, затем пользователь ушёл на другой availability screen;
- photo capture начался, затем пользователь ушёл на другой availability screen.

Ожидаемый результат:

- поздний fill result не меняет `savedCount` и message нового screen;
- поздняя ошибка photo capture не записывает error в новый screen;
- старый success/error не вызывает обратный переход.

### 10. Printer reload reconciliation

Проверить три варианта.

#### Оба выбранных принтера остались

Ожидаемый результат:

- selection сохраняется;
- runtime использует свежие модели и актуальные имена;
- `WearSession` содержит обновлённую пару.

#### Исчез белый принтер

Ожидаемый результат:

- очищаются white, yellow и итоговый selection;
- очищается `WearSession` selection;
- runtime возвращается к выбору белого принтера.

#### Исчез только жёлтый принтер

Ожидаемый результат:

- белый принтер сохраняется;
- итоговый selection очищается;
- runtime возвращается к выбору жёлтого принтера;
- исчезнувший жёлтый не остаётся в `WearSession`.

### 11. Scanner hardware и barcode admission

Проверить переходы:

- barcode screen → photo step;
- barcode screen → menu;
- barcode screen → settings;
- background barcode screen → resume;
- logout;
- `detached`.

Ожидаемый результат:

- на photo/non-barcode screen hardware может оставаться prepared, но barcode admission выключен;
- при logout scanner останавливается;
- после `detached` scanner не запускается снова от позднего callback;
- active route drift блокирует barcode;
- background route drift не блокирует актуальный logical barcode screen.

### 12. Terminal lifecycle

1. Начать voice startup или runtime loading.
2. Перевести приложение в `detached` либо уничтожить Wear module.
3. Спровоцировать позднее завершение операции, authorization callback, voice callback или route callback.

Ожидаемый результат:

- foreground service не стартует повторно;
- scanner не становится prepared;
- barcode admission остаётся выключен;
- voice не перезапускается;
- logical state не реактивируется;
- callback аппаратной кнопки игнорируется.

## На что смотреть в логах

Особое внимание уделить сообщениям:

```text
[WearFlowController]
[WearModuleApp]
[ROUTER-CHANGE]
[VOICE-ROUTE]
scanner runtime sync failed
```

Нежелательные признаки:

- обработка одного barcode более одного раза;
- команда выполняется после сообщения о смене logical screen;
- scanner `start` после `detached`;
- переход назад на старый screen после завершения старой async-операции;
- повторный foreground-service start после terminal teardown;
- актуальный screen не совпадает с payload на очках после стабилизации.

## Критерий приёмки

MR можно считать аппаратно подтверждённым только когда:

- все указанные точечные тесты проходят;
- полный основной flow печати проходит с включённым и выключенным экраном;
- availability direct/check/fill проходят без двойных barcode events;
- все stale-operation сценарии остаются на новом screen;
- после logout и `detached` ресурсы не поднимаются повторно;
- телефон и очки показывают согласованный logical state.

Результат проверки желательно зафиксировать в PR-комментарии с моделью устройства, версией приложения, отмеченными сценариями и найденными отклонениями.
