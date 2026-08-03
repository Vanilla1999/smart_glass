# План фоновой работы Wear при выключенном экране

## Статус реализации от 3 августа 2026

Реализовано:

- `multi_scanner` перенесён в `packages/multi_scanner` и подключён через path;
- автоматический `ViScanner.pause()` удалён из `Activity.ON_PAUSE`;
- добавлены явные `prepareForWear()` и `pauseForWear()`;
- scanner runtime запускается, приостанавливается и освобождается явно;
- foreground service удерживает non-reference-counted partial wake lock;
- service и wake lock завершаются при teardown/уничтожении Activity;
- `paused`/`hidden` останавливают phone UI, но не Wear runtime;
- voice health-check продолжает работать при screen-off;
- Vosk screen context и grammar привязаны к logical screen;
- widget callbacks не вызываются аппаратными командами при inactive UI;
- printer selection загружается и обрабатывается application runtime;
- основной barcode lookup, выбор дубля и печать выполняются runtime;
- availability groups/products/check выполняются application runtime;
- barcode dispatcher живёт на протяжении Wear-сессии;
- photo/availability print вызываются без зависимости от widget tree;
- Wi-Fi refresh в paused использует последнее известное состояние;
- после `resumed` pending logical navigation синхронизируется с phone UI.

Подтверждено на T2151:

- release APK устанавливается поверх существующего приложения без потери данных;
- при `mWakefulness=Asleep` процесс приложения остаётся жив;
- `WearControlForegroundService` остаётся foreground;
- `smart_glasses:WearControlRuntime` удерживается как `PARTIAL_WAKE_LOCK`;
- force-stop освобождает wake lock.

Ожидает аппаратной проверки:

- 20 физических barcode scans при screen-off;
- `takePhoto()`/`deletePhoto()` при screen-off;
- непрерывность PCM в течение 30 минут;
- Firebird-запросы через 5 и 30 минут screen-off;
- полный голосовой сценарий на очках без включения телефона.

## 1. Цель

Обеспечить работу полного основного Wear-сценария при настоящем выключении
экрана телефона, когда Android переводит приложение в `paused`/`hidden`:

```text
Меню
-> выбор принтеров
-> сканирование товара
-> выбор товара
-> проверка доступности
-> печать
-> фотоконтроль камерой очков
-> завершение
```

Во время screen-off должны продолжать работать:

- UAC4-аудиопоток с очков;
- Vosk и разбор голосовых команд;
- `WearFlowController` и бизнес-переходы;
- загрузка списка принтеров;
- загрузка групп и товаров доступности;
- аппаратный сканер через `multi_scanner`;
- камера очков через `MovfastGlassController.takePhoto()`;
- печать и сохранение результата;
- обновление интерфейса очков.

## 2. Согласованные границы

Поддерживаются:

- обычный `onPause`/`onStop` при выключении экрана;
- длительный screen-off при живом процессе;
- возврат приложения в `resumed` с синхронизацией телефонного UI;
- foreground service с активной Wear-сессией.

Не поддерживаются:

- восстановление после уничтожения процесса;
- восстановление после `force-stop`;
- продолжение работы после уничтожения `MainActivity`;
- автоматический перезапуск Wear-сессии после перезагрузки устройства;
- отдельный headless Flutter engine или второй Dart isolate.

Если Activity или Flutter engine уничтожены, Wear-сессия, голос, сканер,
foreground service и wake lock должны корректно остановиться.

## 3. Текущее состояние и проблемы

### 3.1 Голос

`WearModuleApp` не останавливает голос на `paused`/`hidden`, но переводит
`WearFlowController` в `WearUiLifecycle.inactive`. Из-за этого блокируются:

- свободные голосовые фразы;
- `yes`/`no`;
- большинство screen-specific callbacks;
- часть команд `up`/`down`/`select`;
- действия, зарегистрированные Flutter-экранами.

Health-check голоса останавливается при screen-off, а на `resumed` выполняется
принудительный restart UAC4 даже при здоровом PCM-потоке.

### 3.2 PCM и питание

Каждый PCM-пакет должен получить Dart ACK не позднее двух секунд. Foreground
service повышает приоритет процесса, но сам по себе не гарантирует работу CPU
при выключенном экране.

Разрешение `WAKE_LOCK` уже объявлено, но wake lock не захватывается.

### 3.3 Навигация и бизнес-состояние

Логический переход может изменить `WearFlowController.state.screen`, пока
Flutter route остаётся прежним. При screen-off новый Flutter-экран может не
построиться, поэтому:

- его `WearScreenActionHandler` не регистрируется;
- Riverpod provider не создаётся;
- данные не загружаются;
- голосовая грамматика остаётся привязана к старому реальному route;
- последующие команды могут обрабатываться в неверном контексте.

### 3.4 Принтеры

`WearPrinterSelectNotifier` создаётся через `autoDispose` provider. Загрузка
принтеров запускается в конструкторе notifier и зависит от построения
`WearPrinterSelectScreen`.

При фоновом логическом переходе экран может не построиться, поэтому запрос
списка принтеров не начнётся.

### 3.5 Доступность

Группы и товары загружаются через `FutureProvider.autoDispose`, которые
запускаются из `build()` соответствующих экранов.

При screen-off загрузка не должна зависеть от Flutter frame или widget tree.

### 3.6 Сканер и камера

Текущий `multi_scanner` вызывается из Git-зависимости. Его Android plugin на
`Activity.ON_PAUSE` выполняет `ViScanner.pause()`, поэтому сканирование в фоне
не гарантируется.

Фото выполняется через API очков:

```text
WearPhotoStore
-> MovfastGlassController.takePhoto()
-> multi_scanner MethodChannel
-> ViScanner.getAdditionalMovfastGlass().takePhoto()
```

Системная камера телефона не открывается. Однако камера использует тот же
`ViScanner`, поэтому её работу после `ViScanner.pause()` необходимо исключить
из lifecycle-конфликта и проверить на T2151.

## 4. Целевая архитектура

Используется существующий основной Flutter engine. Его не нужно переносить в
foreground service.

Разделяются два lifecycle:

### Wear runtime lifecycle

Активен при `resumed`, `inactive`, `hidden` и `paused`, пока существует Wear-
сессия. Владеет:

- аудиопотоком;
- Vosk;
- голосовыми командами;
- логическим экраном;
- бизнес-состоянием;
- принтерами;
- доступностью;
- scanner callbacks;
- фотоконтролем;
- отправкой состояния на очки.

### Phone UI lifecycle

Активен только при `resumed`. Владеет:

- `GoRouter`;
- Flutter widgets;
- `ScrollController`;
- визуальными диалогами;
- отображением состояния на телефоне.

При screen-off runtime продолжает выполнять бизнес-переходы, а телефонная
навигация сохраняет желаемый route для последующей синхронизации.

Источником истины для голоса и экрана очков является логическое состояние
`WearFlowController`, а не текущий Flutter route.

## 5. План реализации

### Этап 1. Локальный multi_scanner

1. Добавить отслеживаемую копию пакета в `packages/multi_scanner` на базе
   текущей версии `3.17.4-glass`.
2. Заменить Git-зависимость в `pubspec.yaml` на `path` dependency.
3. Убрать автоматический вызов `ViScanner.pause()` из `Activity.ON_PAUSE`.
4. Добавить явные API управления Wear scanner runtime:
   - `prepareForWear()`;
   - `pauseForWear()`.
5. Вызывать `prepareForWear()` при старте авторизованной Wear-сессии.
6. Вызывать `pauseForWear()` при выходе из Wear, logout, `detached` и teardown.
7. Не использовать `ViScanner.release()` для обычного screen-off.
8. Сохранить `ViScanner.release()` для полного завершения scanner runtime.
9. Проверить, что barcode callback остаётся зарегистрированным в `paused`.
10. Проверить `takePhoto()`, `deletePhoto()` и flashlight в `paused`.

Автоматический pause удаляется только из lifecycle Activity. Явное завершение
scanner runtime обязательно, чтобы оборудование не оставалось активным после
выхода из Wear.

### Этап 2. Foreground service и wake lock

1. Оставить один существующий `WearControlForegroundService`.
2. Оставить `START_NOT_STICKY`.
3. Добавить non-reference-counted `PowerManager.PARTIAL_WAKE_LOCK`.
4. Захватывать wake lock после успешного `startForeground()`.
5. Освобождать wake lock в `onDestroy()` и при явной остановке сервиса.
6. Сделать start/stop идемпотентными.
7. Логировать acquire/release и ошибки.
8. Обновить описание `specialUse` в manifest: сервис поддерживает активную
   голосовую и scanner-сессию очков, а не только аппаратные кнопки.
9. Не добавлять второй foreground service.
10. Не создавать Flutter engine внутри сервиса.

### Этап 3. Разделение runtime и UI lifecycle

1. Не переводить Wear runtime в inactive на `paused`/`hidden`.
2. Не останавливать voice session на `paused`/`hidden`.
3. Продолжать voice health-check при живой Wear-сессии независимо от
   `_appResumed`.
4. Останавливать runtime только при logout, dispose или `detached`.
5. Ввести отдельный признак доступности телефонного UI.
6. Выполнять бизнес-команды при активном runtime.
7. Не выполнять UI-only операции через `BuildContext` в фоне.
8. Сохранять желаемую телефонную навигацию как pending UI state.
9. На `resumed` синхронизировать `GoRouter` с логическим экраном.
10. Не удалять принудительный restart на resume до аппаратного теста
    непрерывности UAC4.
11. После успешного длительного теста заменить безусловный restart на
    `ensureHealthy()`, который перезапускает поток только при реальной ошибке.

### Этап 4. Логический экран и голосовая грамматика

1. Разделить:
   - `logicalScreen` для Wear runtime и очков;
   - `actualScreen` для реального Flutter route.
2. Перестраивать Vosk grammar при изменении `logicalScreen`.
3. Проверять voice events относительно logical screen и его revisions.
4. Не ждать построения Flutter widget для регистрации фоновых действий.
5. Хранить focus/index списков в application state.
6. Отправлять glasses payload сразу после логического перехода.
7. Ввести явную логическую историю для команды `back`.
8. Не заменять любой фоновый `back` безусловным переходом в меню.

### Этап 5. Принтеры вне widget tree

1. Сделать printer selection controller долгоживущей частью Wear runtime.
2. Запускать `GetAvailablePrintersUseCase` при логическом входе в
   `printerSelect`.
3. Хранить список, ошибки, выбранный белый и жёлтый принтер в application
   state.
4. Формировать dynamic voice items из application state.
5. Выполнять голосовой выбор принтера без screen-owned handler.
6. После выбора обновлять `WearSession` и логический flow напрямую.
7. Flutter provider должен отображать существующее состояние, а не владеть
   его жизненным циклом.
8. Повторную загрузку и ошибки отправлять на экран очков.

### Этап 6. Доступность вне widget tree

1. Хранить `WearAvailabilityFlowState` в application controller.
2. При входе в доступность вызывать `WearAvailabilityFlowUseCase.start()`.
3. Загружать группы независимо от Flutter frame.
4. При выборе группы вызывать `selectGroup()` и загружать товары.
5. Формировать dynamic voice items из application state.
6. Выполнять выбор товара и ответы `yes`/`no` напрямую через use case.
7. Обрабатывать barcode через application controller.
8. Выполнять переходы price-tag/photo/completed как логические переходы.
9. Flutter-экраны должны только наблюдать и отображать состояние.

Каталог доступности локальный, поэтому его загрузка не зависит от сети или
режима Doze.

### Этап 7. Единый barcode dispatcher

1. Убрать зависимость основного flow от screen-owned scanner delegates.
2. Зарегистрировать один долгоживущий barcode listener на время Wear-сессии.
3. Маршрутизировать barcode по текущему logical screen и flow step.
4. Защитить обработку от повторной доставки одного barcode.
5. Сохранять revision/epoch scanner-сессии.
6. Отменять listener при завершении Wear runtime.
7. Не создавать параллельные scanner-сессии.

### Этап 8. Фото через API очков

1. Вызывать `WearPhotoStore.captureLatestPhoto()` из application flow, а не из
   screen-owned callback.
2. Во время съёмки отображать на очках состояния `taking` и `saving`.
3. Проверять непустой URI от `MovfastGlassController.takePhoto()`.
4. Копировать фото в app storage через `ContentResolver`.
5. Сохранять путь последнего фото в `SharedPreferences`.
6. Удалять исходное фото после успешного копирования.
7. После успеха отмечать `photoCaptured` и продолжать flow.
8. После ошибки оставаться на photo step и позволять повтор команды.
9. Проверить API на T2151 при screen-off до признания этапа завершённым.

### Этап 9. Печать и статусные переходы

1. Вызывать use case печати из application flow.
2. Не зависеть от `context.push()` и результата route для начала печати.
3. Хранить статус печати в application state.
4. Отправлять статус на очки сразу.
5. Выполнять следующий логический переход после результата операции.
6. Синхронизировать телефонный status screen после `resumed`.

### Этап 10. Wi-Fi и сеть

1. Не считать невозможность UI-проверки Wi-Fi при `paused` фактическим
   отключением сети.
2. Использовать последнее известное состояние или `unknown`.
3. Не открывать автоматически Wi-Fi settings из lifecycle-suppressed refresh.
4. Проверить Firebird-запрос принтеров сразу после screen-off, через 5 минут и
   через 30 минут.
5. Не запрашивать battery-optimization exemption без подтверждённой проблемы
   в глубоком Doze.

## 6. Порядок внедрения

Изменения внедряются вертикальными этапами, каждый из которых должен быть
проверен на T2151 до продолжения:

1. Локальный `multi_scanner`, scanner lifecycle и camera API.
2. Wake lock и непрерывный PCM при screen-off.
3. Runtime/UI lifecycle и голосовые команды на уже открытом экране.
4. Логическая навигация и grammar revisions.
5. Printer selection в фоне.
6. Availability flow в фоне.
7. Barcode dispatcher.
8. Фото и печать.
9. Синхронизация UI после `resumed`.
10. Длительный screen-off и regression suite.

Нельзя переходить к следующему этапу, если текущий не имеет воспроизводимого
аппаратного подтверждения.

## 7. Автоматические тесты

Необходимы тесты:

1. `paused` не останавливает voice session.
2. `paused` не переводит runtime в inactive.
3. `detached` останавливает voice, scanner runtime и service.
4. Health-check продолжает работать при screen-off.
5. Голосовая команда обрабатывается при UI inactive/runtime active.
6. Logical screen меняет grammar revision без Flutter navigation.
7. Pending UI route синхронизируется на `resumed`.
8. Printer controller загружает данные без построенного widget.
9. Availability controller загружает группы и товары без widget.
10. Barcode dispatcher направляет код в правильный flow step.
11. Повторный barcode не выполняет бизнес-операцию дважды.
12. Фото успешно меняет `photoCaptured`.
13. Ошибка фото допускает повторную команду.
14. Wake lock захватывается и освобождается ровно один раз.
15. Повторный start/stop foreground service идемпотентен.
16. Logout и выход из Wear освобождают все ресурсы.

## 8. Проверка на T2151

### Базовая непрерывность

1. Авторизоваться и открыть Wear.
2. Дождаться стабильного PCM.
3. Записать capture lease, revision и sequence.
4. Выключить экран на 5 минут.
5. Проверить непрерывный рост PCM sequence.
6. Убедиться в отсутствии `PCM_ACK_TIMEOUT`, `PCM_TIMEOUT`,
   `PCM_QUEUE_OVERRUN`, `RECOGNITION_BACKLOG` и Binder death.

### Голос и навигация

1. Начать с меню.
2. Выключить экран телефона.
3. Голосом открыть выбор принтеров.
4. Выбрать два принтера.
5. Перейти к сканированию.
6. Проверить каждый переход по экрану очков.
7. Убедиться, что grammar соответствует logical screen.

### Принтеры

1. Открыть printer selection голосом при screen-off.
2. Проверить запуск Firebird-запроса без Flutter build.
3. Проверить список и dynamic voice items на очках.
4. Повторить через 5 и 30 минут screen-off.

### Доступность

1. Открыть доступность голосом при screen-off.
2. Проверить загрузку групп из локального каталога.
3. Выбрать группу голосом.
4. Проверить загрузку товаров.
5. Выбрать товар и пройти проверки.

### Сканер

1. Оставить устройство в screen-off.
2. Выполнить не менее 20 сканирований.
3. Проверить доставку каждого barcode.
4. Проверить отсутствие повторов и потерь.
5. Проверить, что `ViScanner.pause()` не вызывается от Activity lifecycle.

### Камера

1. Дойти до photo step при screen-off.
2. Произнести `сделать фото`.
3. Проверить URI от очков.
4. Проверить копирование файла в app storage.
5. Проверить сохранение последнего фото.
6. Проверить удаление исходного URI.
7. Проверить продолжение flow после снимка.

### Возврат телефона

1. Пройти несколько логических экранов при screen-off.
2. Включить экран телефона.
3. Проверить отсутствие потери бизнес-состояния.
4. Проверить синхронизацию Flutter route с logical screen.
5. Проверить актуальные focus, printer selection, product и flow step.

### Завершение

1. Выйти из Wear обычным способом.
2. Проверить остановку scanner runtime.
3. Проверить остановку voice session.
4. Проверить исчезновение foreground notification.
5. Проверить освобождение wake lock.

## 9. Критерии готовности

Решение считается готовым, когда одновременно выполнены условия:

- 30 минут screen-off без разрыва PCM;
- нет `PCM_ACK_TIMEOUT` и terminal capture errors;
- весь основной Wear-сценарий проходится по очкам без включения телефона;
- команды не блокируются из-за UI lifecycle;
- принтеры загружаются без построенного Flutter screen;
- группы и товары доступности загружаются без построенного Flutter screen;
- scanner доставляет barcodes при `paused`;
- камера очков делает и сохраняет фото при `paused`;
- печать завершается при доступной сети;
- после `resumed` телефон показывает фактически достигнутый этап;
- выход из Wear освобождает scanner, voice, service и wake lock;
- уничтожение процесса не оставляет ожидаемого требования восстановления.

## 10. Основные риски

- длительный partial wake lock увеличивает расход батареи и нагрев;
- Firebird/HTTP могут ограничиваться глубоким Doze независимо от wake lock;
- `ViScanner` может иметь внутреннюю зависимость от resumed Activity;
- camera API очков может зависеть от prepared-состояния `ViScanner`;
- Flutter widgets и post-frame callbacks нельзя считать работающими в
  `paused`;
- старые screen-owned handlers могут конфликтовать с application runtime во
  время миграции;
- строгий двухсекундный PCM ACK оставляет мало времени для блокирующего I/O;
- текущий `specialUse` foreground-service subtype потребует актуального
  описания фактической фоновой работы.

Каждый риск должен быть закрыт тестом или явно принят как ограничение до
завершения соответствующего этапа.
