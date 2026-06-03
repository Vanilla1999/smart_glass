# Architecture

## Назначение проекта

`smart_glasses` - Flutter-приложение для Android с двумя runtime-контурами:

- основной экран телефона;
- отдельный экран для smart glasses, запускаемый через entrypoint `glassesMain`.

Приложение объединяет управление очками, offline-распознавание речи через Vosk, сканер штрихкодов через `multi_scanner` и связь с native Android через `MethodChannel`.

## Текущий стек

| Зона | Решение |
|---|---|
| UI | Flutter Material |
| State management | `flutter_bloc` / Cubit |
| DI | Ручной контейнер `DependenciesContainer` + `AppScope` |
| Native bridge | `MethodChannelService` |
| Voice recognition | `vosk_flutter_service` + `record` |
| Scanner | `multi_scanner` |
| Assets | `assets/vosk-model-small-ru-0.22.zip` |
| Wi‑Fi status | `wifi_info_plugin_plus` + `permission_handler` |

## Структура каталогов

```text
lib/
├── main.dart
├── app/
│   ├── app.dart
│   ├── di/
│   │   ├── app_scope.dart
│   │   └── dependencies_container.dart
│   └── glasses/
│       ├── glasses_runtime_app.dart
│       ├── glasses_coordinator_cubit.dart
│       └── glasses_coordinator_state.dart
├── core/
│   ├── constants/
│   │   └── app_constants.dart
│   ├── services/
│   │   └── method_channel_service.dart
│   └── utils/
│       └── inherited_extension.dart
└── features/
    ├── initialization/
    ├── home/
    ├── scanner/
    ├── voice/
    └── glasses/
```

Проект использует Feature-First подход. Общие инфраструктурные вещи живут в `app/` и `core/`, пользовательские сценарии - в `features/`.

## Runtime-Контуры

### Основное приложение

Основной entrypoint - `main()` в `lib/main.dart`.

Порядок запуска:

1. `WidgetsFlutterBinding.ensureInitialized()`.
2. Создание `DependenciesContainer`.
3. Оборачивание приложения в `AppScope`.
4. Запуск `MyApp`.
5. Стартовый экран - `InitializationScreen`.

Основной flow:

```text
main()
  -> DependenciesContainer.create()
  -> AppScope
  -> MyApp
  -> InitializationScreen
  -> HomeScreen
```

### Glasses runtime

Отдельный entrypoint - `glassesMain()` в `lib/main.dart`.

Он запускает `GlassesRuntimeApp`, который:

- создает собственные Cubit'ы для экранов очков;
- создает `GlassesCoordinatorCubit`;
- слушает команды из native через `MethodChannelService`;
- управляет локальным `Navigator` для экранов очков.

Flow очков:

```text
glassesMain()
  -> GlassesRuntimeApp
  -> GlassesCoordinatorCubit
  -> MethodChannel handler
  -> Navigator
  -> GlassesInitializationScreen / GlassesEmptyScreen / GlassesScreen / GlassesScreen2
```

## Зависимости И DI

Глобальные зависимости создаются в `DependenciesContainer.create()`:

- `MethodChannelService`;
- `ScannerCubit`;
- `VoiceCubit`;
- `HomeCubit`.

`AppScope` передает контейнер вниз по дереву через `InheritedWidget`. Экраны получают зависимости через `AppScope.of(context)` и подключают Cubit'ы через `BlocProvider.value`.

Правила:

- не создавать второй экземпляр глобального Cubit'а внутри экрана, если он уже есть в `DependenciesContainer`;
- закрывать глобальные Cubit'ы только в `DependenciesContainer.dispose()`;
- для локальных Cubit'ов, созданных экраном через `BlocProvider(create: ...)`, lifecycle принадлежит экрану;
- `MethodChannelService` является singleton-фасадом над каналами `app_channel` и `glasses_channel`.

## State Management

Основной паттерн состояния - Cubit + sealed-like state classes.

Зоны ответственности:

| Cubit | Ответственность |
|---|---|
| `InitializationCubit` | Инициализация scanner/voice, прогресс запуска, переход на `HomeScreen` |
| `HomeCubit` | Счетчик, команды показа экранов очков, сохранение/очистка логов |
| `ScannerCubit` | Подключение к `multi_scanner`, обработка scan/error events |
| `VoiceCubit` | Загрузка Vosk, запись аудио, распознавание, throttling, отправка текста на очки |
| `GlassesCoordinatorCubit` | Прием MethodChannel-событий в runtime очков, маршрутизация данных на активный экран |
| `GlassesScreenCubit` | State первого экрана очков: счетчик и распознанный текст |
| `GlassesScreen2Cubit` | State второго экрана очков: распознанный текст |

Правила:

- UI не должен напрямую вызывать native `MethodChannel`, для этого используется `MethodChannelService`;
- бизнес-события и side effects должны проходить через Cubit;
- Cubit не должен зависеть от Flutter widget tree, кроме случаев передачи callback'ов навигации в coordinator;
- асинхронные подписки должны отменяться в `close()`.

## Native Bridge

`MethodChannelService` инкапсулирует два канала:

- `app_channel` - команды из Flutter main runtime в native Android;
- `glasses_channel` - команды и данные для glasses runtime.

Основные команды:

| Метод | Назначение |
|---|---|
| `showGlasses` | Показать основной экран очков со счетчиком |
| `showGlassesInitialization` | Показать экран инициализации очков |
| `navigateGlassesToEmpty` | Перевести очки на empty screen |
| `showGlassesScreen2` | Показать второй экран очков |
| `updateCounter` | Передать счетчик на очки |
| `updateRecognizedText` | Передать распознанный текст на очки |
| `saveLogs` | Запросить сохранение логов native-слоем |
| `clearLogs` | Запросить очистку логов native-слоем |
| `getInitialCounter` | Получить начальное значение счетчика в glasses runtime |

Правила изменения bridge:

- добавляя новый native method, обновлять Flutter service и Android handler одновременно;
- имена методов держать стабильными и строково совпадающими между Flutter и Android;
- ошибки native bridge не глотать молча: минимум логировать и возвращать управляемое состояние в Cubit;
- не вызывать `MethodChannel` напрямую из widgets.

## Initialization Flow

`InitializationScreen` создает `InitializationCubit`, который:

1. Просит native показать initialization screen на очках.
2. Подписывается на `ScannerCubit` и `VoiceCubit`.
3. Запускает инициализацию scanner и voice.
4. Ждет voice до 30 секунд.
5. Ждет scanner до 10 секунд.
6. Обновляет прогресс.
7. При готовности voice переводит очки на empty screen.
8. После полной готовности переводит телефон на `HomeScreen`.

Scanner считается важным, но более мягким компонентом: timeout scanner короче, а voice является обязательным для финального перехода очков на empty screen.

## Voice Flow

`VoiceCubit` отвечает за offline speech recognition:

```text
VoiceCubit.init()
  -> load Vosk model from assets
  -> create model
  -> create recognizer(sampleRate: 16000)
  -> VoiceReady

startListening()
  -> check microphone permission
  -> record.startStream(PCM 16 bit, 16 kHz, mono)
  -> recognizer.acceptWaveformBytes(chunk)
  -> parse result/partial
  -> emit VoiceRecognized
  -> MethodChannelService.updateRecognizedText
```

Важные инварианты:

- sample rate должен оставаться согласованным между `RecordConfig` и Vosk recognizer;
- аудио chunks обрабатываются с backpressure через `_isProcessingAudioChunk`;
- UI updates и отправка на очки throttled через константы в `AppConstants`;
- Vosk model asset должен быть объявлен в `pubspec.yaml`.

## Scanner Flow

`ScannerCubit` реализует `MultiScannerDelegate`.

Flow:

```text
ScannerCubit.init()
  -> _scanner.addDelegate(this)
  -> _baseController.init()
  -> _baseController.setRecomendedSettings()
  -> listen isServiceConnected
  -> ScannerReady

onScanEvent(payload)
  -> ScannerScanned(payload)

onErrorScan(error)
  -> ScannerError(error.toString())
```

Правила:

- delegate добавляется при init и удаляется в `close()`;
- подписка `_serviceSub` отменяется в `close()`;
- UI читает результат сканирования только через `ScannerState`.

## Glasses Navigation

Навигация очков управляется `GlassesRuntimeApp` и `GlassesCoordinatorCubit`.

Поддерживаемые route:

| Route | Экран |
|---|---|
| `/` или `/screen1` | `GlassesScreen` |
| `/initialization` | `GlassesInitializationScreen` |
| `/empty` | `GlassesEmptyScreen` |
| `/screen2` | `GlassesScreen2` |

`GlassesCoordinatorCubit` принимает события:

- `navigateToScreen`;
- `navigateToRoute`;
- `updateCounter`;
- `updateRecognizedText`.

Данные маршрутизируются на активный экран:

- counter идет только на screen1;
- recognized text идет на screen1 или screen2 в зависимости от `_currentRoute`.

Правила добавления нового экрана очков:

1. Добавить state и Cubit в `features/glasses/presentation/cubit/...`.
2. Добавить screen в `features/glasses/presentation/screens/...`.
3. Создать Cubit в `GlassesRuntimeApp.initState()`.
4. Добавить `BlocProvider.value` в `MultiBlocProvider`.
5. Добавить route в `_buildScreen()`.
6. Закрыть Cubit в `dispose()`.
7. При необходимости добавить callback в `GlassesCoordinatorCubit`.
8. Обновить native Android route/method mapping.

## Модуль Wear (Печать ценников)

Модуль `wear` портирован из проекта `nbo` (ветка `MDVTM-4425/voice-test`) и реализует flow печати ценников: авторизация сотрудника → выбор принтера → сканирование товаров → голосовой ввод → печать.

### Отличия стека

Модуль использует собственный набор технологий, независимый от основного приложения:

| Зона | Основное приложение | Модуль Wear |
|---|---|---|
| State management | `flutter_bloc` / Cubit | `flutter_riverpod` (StateNotifierProvider) |
| Navigation | `Navigator` (MaterialPageRoute) | `go_router` |
| DB | нет | `fbdb` (Firebird через REST) |
| DI | `DependenciesContainer` + InheritedWidget | `WearDependencies` (ручной singleton) |
| Voice | `vosk_flutter_service` напрямую | `WearDependencies` + `VoiceTypingService` |

Сосуществование двух state management-подходов в одном приложении допустимо: Bloc работает в основном дереве виджетов, а Riverpod — внутри изолированного `ProviderScope`, создаваемого при входе в wear-модуль.

### Структура каталогов

```
lib/modules/wear/
├── config/
│   ├── wear_dependencies.dart       # Singleton-контейнер зависимостей
│   └── wear_session.dart            # Текущая сессия (пользователь)
├── data/
│   ├── auth/
│   │   ├── data_source/
│   │   │   ├── auth_data_source.dart    # HTTP-запросы к API аутентификации
│   │   │   └── auth_dio_client.dart     # Настройка Dio-клиента
│   │   └── model/
│   │       └── auth_response.dart
│   ├── bdto/
│   │   ├── data_source/
│   │   │   ├── bdto_datasource.dart     # Firebird-запросы через fbdb
│   │   │   └── fbdb_error_handler.dart  # Обработка ошибок fbdb
│   │   └── model/
│   │       └── db_models.dart
│   └── printer/
│       └── data_source/
│           └── printer_datasource.dart
├── domain/
│   ├── auth/
│   │   ├── model/
│   │   │   └── authenticated_user.dart
│   │   └── use_case/
│   │       └── authenticate_user_use_case.dart
│   ├── price_tag_print/
│   │   └── use_case/
│   │       ├── get_available_printers_use_case.dart
│   │       ├── get_barcode_info_use_case.dart
│   │       └── print_price_tag_use_case.dart
│   └── service/
│       └── voice_typing/
│           ├── audio_stream_service.dart
│           ├── number_parser_service.dart
│           ├── speech_recognition_service.dart
│           ├── tokenizer.dart
│           └── voice_typing_service.dart
├── models/
│   └── wear_printer_selection.dart
├── navigation/
│   └── wear_routes.dart            # GoRouter-конфигурация (10 роутов)
├── services/
│   ├── wear_wifi_status_service.dart      # Реальный Wi‑Fi статус через wifi_info_plugin_plus
│   ├── wear_printer_status_service.dart   # Статус выбранного принтера (доступен/нет)
│   └── wear_status_icon_reporter.dart     # Реактивная отправка статуса на очки (polling 2s)
├── presentation/
│   ├── input/
│   │   ├── cubit/
│   │   │   └── ear_print_code_input_cubit.dart
│   │   └── wear_print_code_input_screen.dart
│   ├── screens/
│   │   ├── main/
│   │   │   ├── cubit/
│   │   │   │   └── wear_auth_cubit.dart
│   │   │   ├── wear_main_screen.dart         # Экран авторизации (вход по бейджу)
│   │   │   └── wear_scanner_connect_screen.dart
│   │   ├── menu/
│   │   │   └── wear_menu_screen.dart         # Главное меню после входа
│   │   ├── printers/
│   │   │   └── wear_printer_select_screen.dart
│   │   ├── scan/
│   │   │   ├── cubit/
│   │   │   │   └── wear_scan_cubit.dart
│   │   │   ├── wear_product_select_screen.dart
│   │   │   └── wear_scan_idle_screen.dart
│   │   ├── settings/
│   │   │   ├── wear_settings_screen.dart
│   │   │   └── db_settings_screen.dart
│   │   └── status/
│   │       ├── cubit/
│   │       │   └── wear_status_cubit.dart
│   │       ├── wear_status_args.dart
│   │       └── wear_status_screen.dart
│   ├── utils/
│   │   └── wear_feedback.dart
│   └── widgets/
│       ├── wear_loading.dart
│       ├── wear_mode_toggle.dart
│       ├── wear_pill.dart
│       ├── wear_position_indicator.dart
│       ├── wear_scanner_status_indicator.dart
│       ├── wear_screen_scaffold.dart          # Общая обёртка экранов (статус-бар + сканер-индикатор)
│       ├── wear_status_bar.dart              # Device-side Wi‑Fi / printer status icons (polling 10s)
│       └── wear_svg_icon.dart
└── theme/
    ├── wear_colors.dart
    ├── wear_images.dart
    └── wear_typography.dart
```

### Навигационный Flow

```
Телефон (HomeScreen)
  └─ кнопка "Печать ценников"
     └─ WearMainScreen (авторизация по штрихкоду бейджа)
        └─ WearStatusScreen (успех/ошибка)
           └─ WearMenuScreen (главное меню)
              ├─ WearPrinterSelectScreen (выбор принтера)
              │  └─ WearScanIdleScreen (сканирование товаров)
              │     ├─ WearProductSelectScreen (выбор из списка)
              │     └─ WearPrintCodeInputScreen (голосовой ввод кол-ва)
              ├─ WearSettingsScreen (настройки)
              └─ DBSettingsScreen (настройки БД)
```

### Ключевые экраны

| Экран | Маршрут | Назначение |
|---|---|---|
| `WearMainScreen` | `/wear_main_screen` | Авторизация сотрудника по бейджу (mock logo-tap для dev) |
| `WearScannerConnectScreen` | `/wear_scanner_connect` | Подключение Bluetooth-сканера (опционально, через env) |
| `WearStatusScreen` | `/wear_status` | Универсальный статус (успех/ошибка) с auto-dismiss |
| `WearMenuScreen` | `/wear_menu` | Главное меню: печать, настройки, выход |
| `WearScanIdleScreen` | `/wear_scan_idle` | Сканирование товаров, отображение результата |
| `WearPrinterSelectScreen` | `/wear_printer_select` | Выбор принтера из списка |
| `WearProductSelectScreen` | `/wear_product_select` | Выбор товара при множественных результатах |
| `WearPrintCodeInputScreen` | `/wear_print_code_input` | Голосовой ввод количества (ear-print code) |
| `WearSettingsScreen` | `/wear_settings` | Экран настроек |
| `DBSettingsScreen` | `/db_settings` | Настройки подключения к Firebird |

#### Дизайн-конвенции статусных иконок

Очки нормально воспринимают только один цвет, поэтому:

- все статусные иконки (Wi‑Fi, принтер) отображаются зелёным;
- offline-состояние показывается не цветом, а перечёркиванием (slash-линия);
- Wi‑Fi иконка рисуется через `CustomPainter` (3 уровня сигнала + точка);
- принтер — SVG-ассет `WearImages.printer`.

### Dependencies

`WearDependencies` — ручной singleton с ленивой инициализацией:

- `BdtoDataSource` — Firebird-запросы (создаётся сразу);
- `VoiceTypingService` — Vosk-распознавание (warmup в фоне при старте `WearMainScreen`);
- `AuthenticateUserUseCase` — создаётся лениво при первой авторизации (Dio + AuthDataSource).

Riverpod-провайдеры создаются через `autoDispose` и живут в пределах `ProviderScope`:

| Провайдер | Тип | Назначение |
|---|---|---|
| `wearAuthNotifierProvider` | StateNotifierProvider | Состояние авторизации, навигационные команды |
| `wearPrinterSelectControllerProvider` | — | Выбор принтера |
| `wearScanCubitProvider` | — | Сканирование и печать |

#### Сервисы статусных иконок

`WearStatusIconReporter` — singleton, который:

- каждые 2 секунды опрашивает `WearWifiStatusService` и `WearPrinterStatusService`;
- сравнивает snapshot статуса с предыдущим;
- при изменении пересылает на очки новый payload с полями `showWifiIcon`, `wifiAvailable`, `wifiLevel`, `showPrinterIcon`, `printerAvailable`;
- используется всеми экранами вместо прямого вызова `wearGlassesBridge`.

`WearWifiStatusService`:

- вызывает `WifiInfoPlugin.wifiDetails`;
- проверяет `Permission.locationWhenInUse` (запрашивает при необходимости);
- определяет доступность через `connectionType`, `ssid`, `ipAddress`, `networkId`, `signalStrength`;
- маппит `signalStrength` (0..9 от `calculateSignalLevel(rssi, 10)`) в уровни 1..3.

`WearPrinterStatusService`:

- читает выбранные принтеры из `WearSession.printerSelectionOrNull`;
- в реальном режиме сверяет их с `GetAvailablePrintersUseCase`;
- в mock-режиме возвращает доступность, если выбор принтера существует.

#### Барьер повторного ШК

В `WearScanNotifier` добавлена блокировка: одинаковый ШК подряд (`_lastAcceptedBarcode`) не уходит в печать повторно.

### Внешние заглушки

Некоторые зависимости nbo недоступны в текущем окружении и заменены заглушками:

| Заглушка | Реальный источник |
|---|---|
| `packages/pole_base_kit/` | GitLab: `coderepo.corp.tander.ru/...` (PBTextStyles, PBIcon) |
| `lib/app/data/network/network_requests/api_request.dart` | `package:nbo/...` (базовый HTTP-клиент) |

`pole_base_kit` — временный локальный path-пакет, экспортирующий только то, что используется в wear (PBTextStyles, PBIcon, PBIconData). При появлении доступа к GitLab заменяется на git-ссылку.

### Интеграция с телефоном

Модуль открывается из HomeScreen через `Navigator.push` с `ProviderScope + MaterialApp.router`:

```dart
Navigator.push(
  context,
  MaterialPageRoute(
    builder: (_) => ProviderScope(
      child: MaterialApp.router(
        routerConfig: GoRouter(
          initialLocation: '/wear_main_screen',
          routes: WearRoute.goRouteWear,
        ),
      ),
    ),
  ),
);
```

Весь модуль работает в изолированном контуре: собственный GoRouter, собственный ProviderScope, собственный DI.

### Известный технический долг

- `deprecated_member_use` в `bdto_datasource.dart` (методы fbdb);
- `pole_base_kit` как локальный path-пакет вместо git-зависимости;
- Закомментированные импорты Bluetooth/Scanner-зависимостей, которые были в оригинальном nbo;
- Отсутствие `ProviderScope` на уровне корневого `MaterialApp` (создаётся динамически при входе в модуль).
- `assets/develop.env` объявлен в `pubspec.yaml`, но игнорируется `.gitignore` — свежий checkout/CI без него упадёт на сборке assets.
- `dart analyze` на большом наборе файлов может лагать и виснуть — рекомендуется запускать по 1–2 файлам за раз.

## Правила Изменений

### Минимальный scope

- Менять только файлы, относящиеся к задаче.
- Не переносить проект на другой state management без отдельного решения.
- Не вводить domain/data слои формально, пока нет реальной бизнес-логики или внешних источников данных.
- Если feature растет, сначала выделять понятные Cubit/state/widgets внутри текущей структуры.

### Когда добавлять слой

Сейчас проект фактически presentation-heavy: Cubit'ы напрямую координируют services/plugins. Это допустимо для текущего размера.

Добавлять `domain/` и `data/` внутри feature стоит только если появляется хотя бы одно условие:

- несколько источников данных;
- сложные правила обработки, которые нужно тестировать отдельно от Flutter;
- один сценарий используется несколькими Cubit'ами;
- требуется стабильный контракт результата между plugin/native и UI;
- появляются persistency, network или repository abstractions.

Если слой добавлен, направление зависимостей должно быть таким:

```text
presentation -> domain -> data
```

Обратные импорты запрещены.

### Ошибки

- Plugin/native ошибки переводить в state (`VoiceError`, `ScannerError` или отдельное состояние feature).
- Не оставлять критичные ошибки только в `print`.
- Для новых user-facing ошибок показывать понятное сообщение в UI.

### Логи

Сейчас в проекте используются `print`. Для production-кода это технический долг.

Правило для новых изменений:

- не увеличивать хаотичное использование `print`;
- если добавляется значимый лог, помечать место как кандидат на общий logging service;
- для высокочастотных событий, например audio chunks, не логировать каждый event.

## Проверки

Базовые команды перед завершением задачи:

```bash
flutter analyze
flutter test
```

Если используется FVM в текущем окружении, предпочтительно запускать:

```bash
fvm flutter analyze
fvm flutter test
```

Для изменений Android/native bridge дополнительно проверять запуск на устройстве или эмуляторе, потому что часть ошибок `MethodChannel` не ловится статическим анализом Dart.

## OpenCode Workflow По Отчету

Файл `/home/viadmin/Загрузки/deep-research-report.md` рекомендует не держать один огромный контекст для всех задач. Для этого проекта применяем risk-based workflow.

### Роли моделей

| Задача | Модель по умолчанию | Причина |
|---|---|---|
| Поиск файлов, чтение структуры, grep | слабая | дешево, read-only, низкая цена ошибки |
| Первый план изменений | слабая | модель выступает как планировщик и компрессор контекста |
| Суммаризация diff/test output | слабая | это сжатие фактов, не архитектурный суд |
| Локальная правка одного widget/Cubit | слабая или средняя | scope ограничен |
| Изменение MethodChannel, Android bridge, glasses flow | сильная review-модель | высокий интеграционный риск |
| Изменение DI/lifecycle глобальных Cubit'ов | сильная review-модель | высокий риск утечек и double-dispose |
| Финальное архитектурное ревью PR | сильная review-модель | нужна проверка глобальных инвариантов |

### Триггеры эскалации

Звать сильную модель или делать ручной архитектурный review, если задача затрагивает:

- `MethodChannelService` и Android native handlers;
- `glassesMain`, `GlassesRuntimeApp`, `GlassesCoordinatorCubit`;
- lifecycle Cubit'ов и `DependenciesContainer`;
- voice audio pipeline, sample rate, throttling или Vosk model asset;
- scanner delegate lifecycle;
- navigation между phone runtime и glasses runtime;
- несколько features одновременно;
- добавление нового слоя `domain/` или `data/`;
- падение `analyze`, `test` или runtime-проверки на устройстве.

### Контракт плана

Перед крупной правкой полезно фиксировать короткий plan:

```json
{
  "task_type": "bugfix|feature|refactor|analysis",
  "assumptions": ["..."],
  "affected_scope": {
    "features": ["home", "voice", "scanner", "glasses", "initialization"],
    "files": ["..."]
  },
  "architecture_checks": ["MethodChannel contract", "Cubit lifecycle", "glasses route mapping"],
  "plan_steps": [
    {"step": "...", "why": "...", "verify": "..."}
  ],
  "verification_commands": ["flutter analyze", "flutter test"],
  "risk_level": "low|medium|high",
  "escalate_to_strong": true
}
```

### Контракт review

Для review передавать не весь диалог, а короткий контекст:

- plan JSON;
- список измененных файлов;
- summary diff;
- результаты `analyze`/`test`;
- релевантные фрагменты этого файла.

Review должен отвечать на вопросы:

- не сломан ли dual-runtime flow;
- не нарушен ли lifecycle Cubit'ов и подписок;
- совпадают ли MethodChannel method names с native частью;
- не добавлен ли лишний глобальный state;
- достаточны ли проверки;
- можно ли уменьшить scope.

## Архитектурные Инварианты

- `main()` запускает phone runtime, `glassesMain()` запускает glasses runtime.
- Phone UI не управляет Navigator очков напрямую; связь идет через native bridge и coordinator.
- `MethodChannelService` - единственная точка Flutter-вызовов к native channels.
- Глобальные Cubit'ы создаются в `DependenciesContainer` и передаются через `AppScope`.
- Локальные Cubit'ы glasses runtime создаются и закрываются внутри `GlassesRuntimeApp`.
- Voice recognition работает offline через Vosk asset, объявленный в `pubspec.yaml`.
- Scanner lifecycle обязан добавлять и удалять delegate симметрично.
- Любой новый route очков должен быть согласован в Flutter runtime и native Android mapping.
- Перед завершением изменений нужно запускать `analyze`; для логики Cubit/widget желательно добавлять или запускать tests.
