# Модуль Wear — Архитектура

## Назначение

Модуль `wear` реализует flow **печати ценников** и **проверки наличия** для сотрудников розничного магазина с использованием smart glasses. Портирован из проекта `nbo` (ветка `MDVTM-4425/voice-test`).

**Бизнес-процесс:**

```
Авторизация (бейдж) → Выбор принтера → Сканирование штрихкода товара → Голосовой/цифровой ввод → Печать ценника

Авторизация (бейдж) → Раздел "Доступность" → Группа/товар или прямое сканирование → Пошаговая проверка наличия
```

---

## Текущий стек

| Зона | Решение |
|---|---|
| Язык | Dart 3.x, Flutter |
| State management | `flutter_riverpod` (StateNotifierProvider) + `flutter_bloc`/Cubit |
| DI | Ручной singleton `WearDependencies` |
| Navigation | `go_router` в изолированном `MaterialApp.router` |
| DB | `fbdb` — Firebird REST-клиент (stored procedures) |
| Auth | `dio` — HTTP-клиент для REST API (`auth/login`) |
| Voice | `vosk_flutter_service` + `record` (offline, русский) |
| Scanner | `multi_scanner` (подключение заглушено) |
| UI kit | Flutter widgets + `flutter_svg` |
| Env | `flutter_dotenv` |
| Persistence | `shared_preferences` (настройки БД) |
| Feedback | `haptic_feedback`, системный звук |

---

## Структура каталогов

```
lib/modules/wear/
├── application/                     # Flow state, command routing, ports
│   ├── ports/
│   │   ├── wear_glasses_output.dart
│   │   └── wear_navigation_output.dart
│   ├── wear_command_router.dart
│   ├── wear_flow_controller.dart
│   ├── wear_flow_state.dart
│   ├── wear_navigation_request.dart
│   ├── wear_screen_id.dart
│   └── wear_ui_lifecycle.dart
│
├── config/                          # DI и глобальное состояние
│   ├── wear_dependencies.dart       #   Singleton-контейнер
│   └── wear_session.dart            #   Текущая сессия (AuthenticatedUser)
│
├── data/                            # Внешние источники данных
│   ├── availability/
│   │   └── local_wear_availability_repository.dart
│   ├── auth/
│   │   ├── data_source/
│   │   │   ├── auth_data_source.dart    # HTTP POST auth/login
│   │   │   └── auth_dio_client.dart     # Dio-клиент (baseUrl из .env)
│   │   └── model/
│   │       └── auth_user.dart           # Freezed-модель ответа API
│   └── bdto/
│       ├── data_source/
│       │   ├── bdto_datasource.dart     # Firebird stored procedures
│       │   └── fbdb_error_handler.dart  # Парсинг ошибок fbdb
│       └── model/                       # Freezed-модели Firebird
│           ├── barcode_info.dart
│           ├── price_tag_info.dart
│           ├── price_tag_type.dart
│           ├── print_add_art_result.dart
│           ├── print_price_tags_result.dart
│           ├── print_task_get_result.dart
│           ├── printer_list_item.dart
│           ├── printer_selection_result.dart
│           └── enum/                     # Enum-ы для значений Firebird
│               ├── barcode_mode.dart
│               ├── price_tag_action_flag.dart
│               ├── price_tag_color.dart
│               ├── print_mode.dart
│               ├── printer_kind.dart
│               ├── printer_mobility_type.dart
│               ├── printer_selection_type.dart
│               └── printer_subkind.dart
│
├── domain/                          # Бизнес-логика
│   ├── availability/
│   │   ├── model/
│   │   ├── repository/
│   │   └── use_case/
│   ├── auth/
│   │   ├── model/
│   │   │   └── authenticated_user.dart  # ID пользователя/сотрудника
│   │   └── use_case/
│   │       └── authenticate_user_use_case.dart
│   ├── price_tag_print/
│   │   ├── model/
│   │   │   ├── available_printer.dart
│   │   │   └── barcode_product_info.dart
│   │   └── use_case/
│   │       ├── get_available_printers_use_case.dart
│   │       ├── get_barcode_info_use_case.dart
│   │       └── print_price_tag_use_case.dart
│   └── service/
│       ├── voice_command/               # Парсер и поток голосовых команд
│       └── voice_typing/                # Конвейер голосового ввода чисел
│           ├── audio_stream_service.dart
│           ├── number_parser_service.dart
│           ├── speech_recognition_service.dart
│           ├── tokenizer.dart
│           └── voice_typing_service.dart
│
├── models/                          # Plain Dart-модели (без freezed)
│   ├── wear_printer.dart
│   └── wear_printer_selection.dart
│
├── infrastructure/                  # Adapters for application ports
│   ├── flutter_wear_glasses_output.dart
│   ├── flutter_wear_navigation_output.dart
│   ├── noop_wear_glasses_output.dart
│   ├── noop_wear_navigation_output.dart
│   └── screen_lifecycle_logging.dart
│
├── navigation/
│   └── wear_routes.dart             # GoRouter-конфигурация wear routes
│
├── presentation/                    # UI слой
│   ├── glasses/                         # Payload builders + MethodChannel bridge
│   │   ├── wear_availability_glasses_payloads.dart
│   │   ├── wear_glasses_bridge.dart
│   │   └── wear_glasses_payload.dart
│   ├── input/
│   │   ├── cubit/
│   │   │   └── ear_print_code_input_cubit.dart  # Bloc
│   │   └── wear_print_code_input_screen.dart
│   ├── screens/
│   │   ├── main/
│   │   │   ├── cubit/
│   │   │   │   └── wear_auth_cubit.dart         # Riverpod
│   │   │   ├── wear_main_screen.dart
│   │   │   └── wear_scanner_connect_screen.dart
│   │   ├── availability/                # Проверка наличия товара
│   │   ├── continue_scan/
│   │   ├── help/
│   │   ├── menu/
│   │   │   └── wear_menu_screen.dart
│   │   ├── printers/
│   │   │   ├── cubit/
│   │   │   │   └── wear_printer_select_cubit.dart # Riverpod
│   │   │   └── wear_printer_select_screen.dart
│   │   ├── scan/
│   │   │   ├── cubit/
│   │   │   │   └── wear_scan_cubit.dart          # Riverpod
│   │   │   ├── wear_product_select_screen.dart
│   │   │   └── wear_scan_idle_screen.dart
│   │   ├── settings/
│   │   │   ├── wear_settings_screen.dart
│   │   │   └── db_settings_screen.dart
│   │   └── status/
│   │       ├── wear_status_args.dart
│   │       └── wear_status_screen.dart
│   ├── utils/
│   │   └── wear_feedback.dart
│   └── widgets/
│       ├── home_button.dart
│       ├── wear_key_button.dart
│       ├── wear_loading.dart
│       ├── wear_module_app.dart
│       ├── wear_mode_toggle.dart
│       ├── wear_pill.dart
│       ├── wear_position_indicator.dart
│       ├── wear_scaling_list_view.dart
│       ├── wear_scanner_status_indicator.dart
│       ├── wear_screen_scaffold.dart
│       ├── wear_svg_icon.dart
│       ├── wear_voice_command_listener.dart
│       └── wear_voice_indicator.dart
│
├── services/
│   ├── wear_voice_session.dart          # Lifecycle voice command service
│   ├── wear_wifi_status_service.dart
│   ├── wear_printer_status_service.dart
│   └── wear_status_icon_reporter.dart
│
└── theme/
    ├── wear_colors.dart
    ├── wear_images.dart
    └── wear_typography.dart
```

---

## Навигационный Flow

```
HomeScreen (телефон, основное приложение)
  └─ Push WearModule (ProviderScope + WearModuleApp)
     ├─ [WearScannerConnectScreen]  — опционально (env)
      └─ WearMainScreen                    — авторизация по бейджу
         └─ WearStatusScreen                — успех/ошибка → auto-dismiss
            └─ WearMenuScreen               — главное меню
               ├─ WearPrinterSelectScreen   — выбор белого + жёлтого принтера
               │  └─ WearScanIdleScreen     — сканирование товаров
               │     ├─ WearProductSelectScreen   — если товаров >1
               │     ├─ WearPrintCodeInputScreen  — голосовой/цифровой ввод
               │     └─ WearContinueScanScreen    — продолжить сканирование
               ├─ WearAvailabilityInteractionScreen — проверка наличия
               │  ├─ WearAvailabilityGroupScreen
               │  │  └─ WearAvailabilityProductScreen
               │  │     └─ WearAvailabilityCheckScreen
               │  ├─ WearAvailabilityDirectScanScreen
               │  │  └─ WearAvailabilityCheckScreen
               │  └─ WearAvailabilityFillScreen
               ├─ WearSettingsScreen        — настройки модуля
               ├─ WearHelpScreen            — помощь
               └─ DBSettingsScreen          — настройки Firebird
```

### Таблица роутов

| Экран | Путь | Назначение |
|---|---|---|
| `WearScannerConnectScreen` | `/wear_scanner_connect` | Подключение Bluetooth-сканера (env: `WEAR_SKIP_SCANNER_CONNECT_SCREEN`) |
| `WearMainScreen` | `/wear_main_screen` | Авторизация: сканирование бейджа / mock logo-tap |
| `WearStatusScreen` | `/wear_status_screen` | Универсальный статус (success/error) с auto-dismiss |
| `WearMenuScreen` | `/wear_menu` | Главное меню: печать, настройки, выход |
| `WearHomeConfirmScreen` | `/wear_home_confirm` | Подтверждение перехода домой |
| `WearPrinterSelectScreen` | `/wear_printer_select` | Выбор белого (обычный) + жёлтого (акционный) принтера |
| `WearScanIdleScreen` | `/wear_scan_idle` | Сканирование товаров + отображение результата |
| `WearProductSelectScreen` | `/wear_product_select` | Выбор товара при множественных результатах |
| `WearPrintCodeInputScreen` | `/wear_print_code_input` | Ввод количества (голос / цифровая клавиатура) |
| `WearAvailabilityInteractionScreen` | `/wear_availability_interaction` | Выбор режима проверки наличия |
| `WearAvailabilityGroupScreen` | `/wear_availability_groups` | Выбор группы товаров |
| `WearAvailabilityProductScreen` | `/wear_availability_products` | Выбор товара в группе |
| `WearAvailabilityDirectScanScreen` | `/wear_availability_direct_scan` | Прямое сканирование товара для проверки наличия |
| `WearAvailabilityCheckScreen` | `/wear_availability_check` | Пошаговая проверка наличия |
| `WearAvailabilityFillScreen` | `/wear_availability_fill` | Ручной ввод/очистка для проверки наличия |
| `WearContinueScanScreen` | `/wear_continue_scan` | Продолжение сканирования после действия |
| `WearHelpScreen` | `/wear_help` | Справка |
| `WearSettingsScreen` | `/wear_settings` | Настройки модуля |
| `WearWifiSettingsScreen` | `/wear_wifi_settings` | Статус/повторная проверка Wi-Fi |
| `WearPrinterSettingsScreen` | `/wear_printer_settings` | Статус/повторная проверка выбранного принтера |
| `DBSettingsScreen` | `/db_settings` | Настройки подключения к Firebird |

---

## State Management

### Riverpod (основной)

Модуль использует `flutter_riverpod` для большинства экранов. Провайдеры создаются через `StateNotifierProvider.autoDispose` и живут в пределах изолированного `ProviderScope`.

| Провайдер | Notifier | Экран | Назначение |
|---|---|---|---|
| `wearAuthNotifierProvider` | `WearAuthNotifier` | WearMainScreen | Авторизация, имплементирует `MultiScannerDelegate` |
| `wearPrinterSelectNotifierProvider` | `WearPrinterSelectNotifier` | WearPrinterSelectScreen | Загрузка + выбор принтеров (white/yellow) |
| `wearScanNotifierProvider` (family) | `WearScanNotifier` | WearScanIdleScreen | Сканирование, поиск товара, печать |
| `wearAvailabilityGroupsProvider` | `FutureProvider` | WearAvailabilityGroupScreen | Загрузка групп проверки наличия |
| `wearAvailabilityProductsProvider` (family) | `FutureProvider` | WearAvailabilityProductScreen | Загрузка товаров выбранной группы |
| `wearAvailabilityDirectScanProvider` | `StateNotifierProvider` | WearAvailabilityDirectScanScreen | Прямое сканирование/дубли для проверки наличия |

**Паттерн навигации:** старые notifiers могут отдавать одноразовый `navStatus` / `navSelect`, но глобальная маршрутизация и projection-state должны проходить через `WearFlowController` и `WearNavigationOutput`, а не через разрозненные UI-сайд-эффекты.

### Bloc/Cubit (голосовой ввод)

`WearPrintCodeInputCubit` — единственный Cubit в модуле. Причина: портирован из nbo как есть, без переписывания на Riverpod.

Управляет:
- переключением режимов (digits / voice);
- состоянием голосового ввода (idle → starting → listening → error);
- вводом цифр через клавиатуру (pressDigit, backspace, clearAll, setCursor);
- подпиской на `VoiceTypingService.resultsStream` и `audioLevelStream`.

### Голосовые команды навигации

Голосовые команды навигации отделены от голосового ввода чисел. Жизненный цикл распознавания владеется только `WearModuleApp`:

```text
WearModuleApp.initState()
  → addPostFrameCallback
  → WearVoiceSession.I.start()

AppLifecycleState.detached
  → WearVoiceSession.I.stop()

AppLifecycleState.resumed
  → WearVoiceSession.I.restart(reason: 'app_lifecycle_resumed')

AppLifecycleState.paused / hidden / inactive
  → только print diagnostics (запись продолжается)

WearModuleApp.dispose()
  → WearVoiceSession.I.stop()
  → _router.dispose()
```

Экраны не должны напрямую вызывать `WearVoiceSession.I.start()` или `WearVoiceSession.I.stop()`. Экран регистрирует только локальные callbacks через `WearFlowController.registerScreenActions(...)`.

```text
WearVoiceSession
  → WearVoiceControlService.commandStream / phraseStream / partialPhraseStream
  → WearModuleApp stream subscriptions
  → WearFlowController.handleVoiceCommand / handleVoicePhrase / handleVoicePartialPhrase
  → WearScreenActionHandler активного WearScreenId
```

Команды:

| Команда | Примеры фраз | Назначение |
|---|---|---|
| `up` | `вверх`, `наверх`, `выше` | Перемещение фокуса вверх |
| `down` | `вниз`, `ниже` | Перемещение фокуса вниз |
| `select` | `выбрать`, `выбери`, `выбор`, `ок`, `окей` | Подтвердить текущий выбор |
| `back` | `назад` | Глобальный возврат через `context.pop()` |
| `home` | `домой`, `выход` | Глобальный переход в `WearMenuScreen` |

`WearFlowController` обрабатывает глобальные `back/home` централизованно. Остальные команды делегируются handler'у текущего `WearScreenId`. Экраны обязаны симметрично регистрировать и удалять handler в lifecycle (`initState`/`dispose` или эквивалент).

`VoiceCommandParserService` нормализует регистр и пунктуацию, поддерживает exact aliases и token-based fallback. Partial-word совпадения не считаются командами.

### Режимы распознавания: grammar и freeText

`WearModuleApp` подписан на `WearFlowController.stateStream` и при смене экрана вызывает `WearVoiceSession.I.configureForScreen(screen)`. Экран выбирает режим распознавания:

| Режим | Экраны | Назначение |
|---|---|---|
| `grammar` | все экраны по умолчанию | Быстрые системные команды из `VoiceCommandParserService.grammarPhrases` |
| `freeText` | `printerSelect`, `productSelect`, `availabilityGroup`, `availabilityProduct`, `availabilityFill`, `printCodeInput` | Свободный поиск по списку или диктовка чисел |

`SpeechRecognitionService` держит два recognizer'а: `_freeTextRecognizer` и `_grammarRecognizer`. `setRecognitionGrammar(null)` включает freeText, `setRecognitionGrammar(nonEmptyList)` включает grammar. Смена режима не останавливает микрофон: target recognizer готовится внутри `_audioProcessing`, затем mode и `_recognitionModeEpoch` публикуются атомарно. Chunks, поставленные в очередь со старым epoch, отбрасываются до передачи в новый recognizer. Пока grammar recognizer не готов, chunks отбрасываются без free-text fallback. Одинаковая готовая grammar переиспользуется.

Partial/final правила:

- partial-фразы идут в `WearFlowController.handleVoicePartialPhrase(...)`;
- command partial не выполняются; все команды ждут final;
- на freeText-экранах команды распознаются только по exact alias, а остальные final результаты передаются как phrase;
- для списков unique partial только перемещает фокус и не выбирает элемент; выбор выполняется по final;
- длинные partial проходят через `VoiceListMatcher.canMatchPartial(...)` (`minPartialMatchLength = 8`);
- короткие названия принтеров (`белый`, `желтый`, `мобильный`) обрабатываются только через exact-word `VoiceListMatcher.matchExactWord(..., minLength: 5)`.

---

## DI (WearDependencies)

Ручной singleton `WearDependencies.I` с ленивой инициализацией:

```
WearDependencies
 ├─ WearFlowController      — source of truth для wear flow и glasses projection
 ├─ AudioStreamService        — запись микрофона (создаётся сразу)
 ├─ SpeechRecognitionService  — Vosk recognizer (создаётся сразу, общий для typing и команд)
 ├─ VoiceTypingService        — подписчик результатов для голосового ввода чисел
 ├─ WearVoiceControlService   — голосовые команды (SpeechRecognitionService + VoiceCommandParserService)
 ├─ WearGlassesOutput         — Flutter/Noop adapter для runtime очков
 ├─ WearNavigationOutput      — Flutter/Noop adapter для GoRouter
 ├─ BdtoDataSource            — Firebird (создаётся сразу)
 └─ AuthenticateUserUseCase   — лениво, при первой авторизации
     ├─ AuthDioClient
     └─ AuthDataSource
```

Use case'ы для принтеров/печати создаются фабричными методами (`getAvailablePrintersUseCase()`, `getBarcodeInfoUseCase()`, `printPriceTagUseCase`). Навигационный и glasses output adapters можно заменить на noop для тестов.

---

## Слои и направление зависимостей

```
presentation (экраны, cubit'ы/notifier'ы, widgets)
    ↓  вызывает
application (WearFlowController, ports, navigation requests)
    ↓  вызывает
domain (use case'ы, сервисы, domain-модели)
    ↓  вызывает
data (data sources, data-модели)

infrastructure реализует application ports для Flutter/GoRouter/MethodChannel
```

Обратные импорты запрещены. `domain` не знает о Flutter. `data` реализует контракты, используемые `domain`. Известное исключение: `WearGlassesPayload` сейчас лежит в `presentation/glasses`, но используется как projection DTO для `WearGlassesOutput`; при крупной чистке его лучше перенести в `application` или отдельный DTO слой.

---

## Ключевые потоки данных

### 1. Авторизация (WearAuthNotifier)

```
onScanEvent(barcode)
  → WearDependencies.I.authenticateUserUseCase
    → AuthDataSource.authenticate(badgeUuid)
      → POST /auth/login {badge_uuid}
      ← AuthUser
    ← AuthenticatedUser
  → WearSession.setUser(user)
  → emit(nav → WearStatusScreen → WearMenuScreen)
```

Mock-режимы (env):
- `WEAR_MOCK_AUTH_ON_LOGO=true` — вход по тапу на логотипе с тестовым barcode
- `WEAR_MOCK_SKIP_AUTH_ON_LOGO=true` — вход по long-press на логотипе без вызова API

### 2. Выбор принтера (WearPrinterSelectNotifier)

```
load()
  → WearDependencies.I.getAvailablePrintersUseCase()
    → BdtoDataSource.getPrinterSelectionType()  — PPRINT_PRINTERSORT
    → BdtoDataSource.getPrinterList()           — PPRINT_PRINTERLIST
  ← List<WearPrinter>

selectPrinter(printer):
  step=white → сохранить whitePrinter, step=yellow
  step=yellow → сохранить yellowPrinter → готово к сканированию
```

### 3. Сканирование + печать (WearScanNotifier)

```
onScanEvent(barcode)
  → GetBarcodeInfoUseCase.call(barcode)
    → BdtoDataSource.getBarcodeInfo()  — PPRINT_INFO_BARCODE2
  ← List<BarcodeProductInfo>

  if empty → WearStatusScreen (ошибка)
  if 1 → PrintPriceTagUseCase.call()
    → BdtoDataSource.getOrCreatePrintTask()    — PPRINT_GETTASK
    → BdtoDataSource.getPriceTagInfo()         — PPRINT_CENNIK2
    → BdtoDataSource.addPriceTagToPrintQueue() — PPRINT_PRINTADDART
    → BdtoDataSource.printPriceTags()          — PPRINT_PRINT
    → WearStatusScreen (успех)
  if >1 → WearProductSelectScreen (выбор товара)
    → printSelectedProduct(product)
```

### 4. Голосовой ввод (WearPrintCodeInputCubit + VoiceTypingService)

```
startVoice()
  → Permission.microphone.request()
  → VoiceTypingService.requestPermission()
  → ensureVoicePrepared()
    → SpeechRecognitionService.prepare()  — загрузка Vosk-модели
  → VoiceTypingService.startSession()
    → переиспользует listening/session, которыми владеет WearVoiceSession
  → SpeechRecognitionService.resultsStream
    → NumberParserService.parseToNumber() (слова → цифры)
    → _onVoiceResult(digits)
      → emit(value: newDigits)
```

### 5. Голосовые команды навигации и free-text фразы

```text
WearVoiceSession.I.start()
  → WearVoiceControlService.start()
  → commandStream: WearVoiceCommand
  → phraseStream: String
  → partialPhraseStream: String
  → WearModuleApp subscriptions
  → WearFlowController
  ├─ handleVoiceCommand(command)
  ├─ handleVoicePhrase(phrase)
  └─ handleVoicePartialPhrase(phrase)
      → WearScreenActionHandler активного WearScreenId
```

`WearModuleApp` также подписан на `WearFlowController.stateStream` и вызывает `WearVoiceSession.configureForScreen(...)`, чтобы переключать recognizer между `grammar` и `freeText` без остановки аудио. При logout модуль отменяет health checks и останавливает voice session. При inactive lifecycle controller не вызывает widget callbacks; navigation хранится как pending action (`goTo`, `home` или `pop`) до resume. Для `continueScan` pending pop сохраняет текущий `WearPrinterSelection`.

Availability screens используют одинаковый паттерн:

- `up/down` меняют локальный focused/selected index;
- `select` выполняет действие выбранного элемента;
- payload для glasses получает `selectedIndex`, чтобы подсветка на телефоне и в очках совпадала.

Особенности availability flow:

- `WearAvailabilityInteractionScreen`: `select` открывает список групп или прямое сканирование;
- `WearAvailabilityGroupScreen`: `select` открывает товары выбранной группы;
- `WearAvailabilityProductScreen`: `select` открывает проверку выбранного товара;
- `WearAvailabilityDirectScanScreen`: `select` открывает ручной ввод или выбранный дубль товара;
- `WearAvailabilityCheckScreen`: `up` = да, `down` = нет, `select` выполняет действие текущего шага;
- `WearAvailabilityFillScreen`: `select` открывает ручной ввод, `down` очищает ввод.

### 6. Wear glasses projection

Очки получают не UI-виджеты телефона, а готовый `WearGlassesPayload`:

```text
WearFlowController._payloadForState(state)
  → WearGlassesOutput.send(payload)
  → FlutterWearGlassesOutput
  → WearStatusIconReporter.sendFast(payload)
  → WearGlassesBridge.update(payload)
  → MethodChannelService.updateWearGlasses(payload.toJson())
  → MainActivity.updateWearGlasses
  → glasses_channel.updateWearGlasses
  → GlassesCoordinatorCubit
  → WearGlassesCubit.updateFromPayload
  → WearGlassesScreen
```

`WearGlassesPayload` содержит только projection data: `screenType`, `phase`, `title`, `subtitle`, `statusText`, `items`, `bodyLines`, `checkLines`, `selectedIndex`, action labels и status icons (`showWifiIcon`, `wifiAvailable`, `wifiLevel`, `showPrinterIcon`, `printerAvailable`). Business logic, HTTP/Firebird, scanner delegate и voice/audio pipeline не выполняются в glasses runtime.

Правила projection state:

- `WearFlowController` - source of truth для текущего `WearScreenId` и fallback payload;
- экраны со списками вызывают `rememberScreenPayload(screen, payload)`; cache сбрасывается при входе в новый printer/availability/product context;
- для быстрых визуальных реакций (`up/down`, partial focus) используется fast-send путь через `WearStatusIconReporter.sendFast...`, без ожидания нового polling snapshot;
- `WearStatusIconReporter` каждые 2 секунды обновляет Wi-Fi/printer snapshot и подмешивает его в payload;
- payload и lifecycle generations не позволяют медленному refresh перезаписать более новый экран или focus;
- первый payload после `stop()` отправляется через `showWearGlasses`, поэтому повторное открытие модуля возвращает glasses runtime с `/empty` на `/wear`;
- glasses transport сериализован и не блокирует phone navigation при ошибке;
- native show/update/hide acknowledgement имеет timeout 5 секунд, защищено от двойного completion и supersede при новом route;
- phone `Navigator` не должен быть source of truth для UI очков.

---

## WearSession

Глобальный singleton для хранения текущего пользователя:

```dart
WearSession.setUser(user);
WearSession.user;          // AuthenticatedUser
WearSession.isAuthorized;  // bool
WearSession.clear();
```

Живёт в памяти, не персистится. Очищается при выходе из модуля.

---

## Интеграция с основным приложением

Модуль открывается из `HomeScreen` через `Navigator.push` с изолированным `ProviderScope + WearModuleApp`. `WearModuleApp` создаёт собственный `MaterialApp.router`, `GoRouter` и lifecycle голосовой сессии. Demo-overlay предпросмотра очков в телефоне удалён; состояние очков отправляется только в runtime второго экрана через `WearGlassesBridge`:

```dart
Navigator.push(
  context,
  MaterialPageRoute(
    builder: (_) => ProviderScope(
      child: WearModuleApp(),
    ),
  ),
);
```

Весь модуль работает в изолированном контуре: собственный `GoRouter`, `ProviderScope`, `MaterialApp`, DI и voice-command lifecycle. `domain`/`application` не должны зависеть от `app/` и `core/`; интеграция с основным приложением допускается только через infrastructure/presentation adapters (`WearGlassesBridge`, `FlutterWearNavigationOutput`, `MethodChannelService`).

---

## Firebird Stored Procedures

| Процедура | Метод BdtoDataSource | Назначение |
|---|---|---|
| `PPRINT_PRINTERSORT` | `getPrinterSelectionType()` | Тип выбора принтера |
| `PPRINT_PRINTERLIST` | `getPrinterList()` | Список доступных принтеров |
| `PPRINT_INFO_BARCODE2` | `getBarcodeInfo()` | Информация по ШК |
| `PPRINT_CENNIK2` | `getPriceTagInfo()` | Цвет ценника (акция/не акция) |
| `PPRINT_GETTASK` | `getOrCreatePrintTask()` | Создать/получить задание печати |
| `PPRINT_PRINTADDART` | `addPriceTagToPrintQueue()` | Добавить товар в очередь печати |
| `PPRINT_PRINT` | `printPriceTags()` | Выпустить ценники на печать |
| `PPRINT_SCHEMALIST` | `getPriceTagsTypes()` | Доступные форматы ценников |

Данные для подключения: `DBTO_HOST`, `DBTO_PORT`, `DBTO_PATH`, `DBTO_USER`, `DBTO_PASSWORD`, `DBTO_ROLE` (из `.env` или `SharedPreferences`).

---

## Env-переменные

| Переменная | Назначение |
|---|---|
| `DBTO_HOST` | Хост Firebird |
| `DBTO_PORT` | Порт Firebird |
| `DBTO_PATH` | Путь к БД |
| `DBTO_USER` | Пользователь БД |
| `DBTO_PASSWORD` | Пароль БД |
| `DBTO_ROLE` | Роль БД |
| `AUTH_SERVICE_HOST` | Host REST API авторизации |
| `AUTH_SERVICE_PORT` | Port REST API авторизации |
| `DIO_PROXY_HOST` / `DIO_PROXY_PORT` | Опциональный proxy для Dio |
| `WEAR_GLASSES_ENABLED` | Включить отправку wear projection на runtime очков |
| `WEAR_SKIP_SCANNER_CONNECT_SCREEN` | Пропустить экран подключения сканера |
| `WEAR_MOCK_AUTH_ON_LOGO` | Mock-авторизация по тапу на лого |
| `WEAR_MOCK_SKIP_AUTH_ON_LOGO` | Mock-вход без API по long-press |

---

## Известный технический долг

- `deprecated_member_use` в `bdto_datasource.dart` (устаревшие методы `fbdb`)
- Закомментированные импорты Bluetooth/Scanner из оригинального nbo (`wear_auth_cubit.dart`, `wear_scan_cubit.dart`)
- `print`-логирование вместо сервиса логирования
- Отсутствие `ProviderScope` на уровне корневого `MaterialApp` (создаётся динамически)
- Firebird reconnection — параллельные запросы могут перекрыть соединение
- Dependencies auth-части (`ApiRequest`) завязаны на `app/data/` главного приложения
- `WearGlassesPayload` находится в `presentation/glasses`, хотя используется application port'ом `WearGlassesOutput`
- `./gradlew app:compileDebugKotlin` может падать в external `multi_scanner` из `.pub-cache` на unresolved `BTDevices` / `BattaryStateList` / `BattaryState`
