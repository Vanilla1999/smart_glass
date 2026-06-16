# План дублирования Wear UI на второй экран очков

Документ предназначен как **пошаговое ТЗ для слабой модели**. Цель — сохранить существующую бизнес-логику модуля `wear`, но добавить параллельное отображение ключевых экранов на **втором дисплее очков** с дизайном из `design.pen`.

---

## 1. Что нужно получить

Когда пользователь проходит flow печати ценников на основном экране телефона, информация должна одновременно отображаться:

- на **1 экране** — обычный смартфон, текущий/нормальный дизайн wear-модуля;
- на **2 экране очков** — отдельный UI 640×480, по макетам из `design.pen`.

Бизнес-логика должна остаться в существующих Riverpod/Cubit/use case классах модуля `wear`. Новый слой очков должен быть в основном **view/projection layer**: брать уже вычисленное состояние и показывать его на втором экране.

---

## 2. Важные ограничения

### Разрешения экранов

Из логов устройства:

```text
Display id=0, default phone screen: 480x800
Display id=2, SecondDisplay glasses: 640x480
```

Для очков считать целевым размером:

```text
width: 640
height: 480
orientation: landscape
```

### Ограничения UI очков

- Не использовать телефонные виджеты 1-в-1: экран очков меньше и шире.
- Текст крупный, контрастный.
- Основные цвета из макета: тёмный фон `#2A2828`, зелёный акцент `#26BC00`.
- Не делать скролл как основной сценарий: на очках пользователь должен видеть самое важное состояние сразу.
- На очках не должно быть сложных интерактивных форм телефона, если они не нужны для текущего сценария.

---

## 3. Что уже есть в проекте

### Dual-runtime архитектура

В проекте уже есть отдельный runtime для второго дисплея:

```text
main()        -> phone runtime
glassesMain() -> glasses runtime
```

Ключевые файлы:

- `lib/main.dart` — содержит `glassesMain()`.
- `android/app/src/main/kotlin/ru/tander/smart_glasses/MainActivity.kt` — создаёт `FlutterEngineGroup`, запускает `glassesMain`, показывает `Presentation` на `SecondDisplay`.
- `lib/core/services/method_channel_service.dart` — единственная Dart-точка для вызовов native bridge.
- `lib/app/glasses/glasses_runtime_app.dart` — отдельное Flutter-приложение для очков.
- `lib/app/glasses/glasses_coordinator_cubit.dart` — принимает команды из native и маршрутизирует данные по экранам очков.
- `lib/features/glasses/presentation/screens/*` — текущие примеры экранов очков.

### Текущие методы bridge

Сейчас есть каналы:

```text
app_channel     — phone Flutter -> Android native
glasses_channel — Android native -> glasses Flutter
```

Существующие методы phone -> native:

- `showGlasses`
- `showGlassesInitialization`
- `navigateGlassesToEmpty`
- `showGlassesScreen2`
- `updateCounter`
- `updateRecognizedText`
- `saveLogs`
- `clearLogs`

Существующие методы native -> glasses:

- `navigateToRoute`
- `navigateToScreen`
- `updateCounter`
- `updateRecognizedText`
- `getInitialCounter`

---

## 4. Дизайн из Pencil

Файл дизайна:

```text
/home/viadmin/StudioProjects/smart_glasses/design.pen
```

Макеты уже сделаны в размере `640x480`, что совпадает со вторым экраном очков.

Основные найденные top-level frames:

| Pencil frame | Назначение |
|---|---|
| `Авторизация_Поиск ШК` | ожидание сканирования бейджа |
| `Авторизация_Сканирую` | сканирование бейджа |
| `Авторизация_Распознаю` | распознавание/проверка ШК |
| `Авторизация_Авторизация` | авторизация сотрудника |
| `Авторизация_Успешно` | успешная авторизация |
| `Авторизация_ШК не распознан` | бейдж/ШК не найден |
| `Авторизация_Ошибка авторизации` | ошибка auth API |
| `Выбор раздела_Инициализация` | загрузка разделов меню |
| `Выбор раздела_Список` | список разделов |
| `Выбор Режима печати_Список` | выбор режима печати |
| `Выбор Принтера Белый_Список` | выбор белого принтера |
| `Выбор Принтера Желтый_Список` | выбор жёлтого принтера |
| `Сканирование товара_Поиск ШК` | ожидание сканирования товара |
| `Сканирование товара_ШК отсканирован` | товар отсканирован |
| `Сканирование товара_Дубль ШК` | несколько товаров по одному ШК |
| `Сканирование товара_ШК не распознан` | товар по ШК не найден |
| `Сканирование товара_Ошибка сканирования (техническая)` | scanner error |
| `Сканирование товара_Ценник не найден` | нет ценника |
| `Сканирование товара_Отправляем на печать` | процесс отправки на печать |
| `Сканирование товара_Техническая ошибка` | ошибка печати/БД |
| `Сканирование товара_Продолжить печать` | вопрос продолжить/завершить |
| `Справка` | help / controls mapping |

---

## 5. Главный архитектурный принцип

**Не переносить бизнес-логику в glasses runtime.**

Очки должны получать только готовое состояние для отображения. Например:

```dart
WearGlassesState(
  route: '/wear_glasses_auth',
  title: 'Авторизация',
  subtitle: 'Наведите камеру на штрих-код',
  status: WearGlassesStatus.scanning,
  items: [],
  selectedIndex: 0,
)
```

Нельзя делать в glasses runtime:

- HTTP авторизацию;
- Firebird-запросы;
- печать;
- работу со scanner delegate;
- работу с voice/audio pipeline;
- изменение `WearSession`.

Можно делать в glasses runtime:

- отображать `title/subtitle/status/items`;
- подсвечивать выбранный элемент;
- показывать success/error/progress;
- принимать route/state через `MethodChannel`.

---

## 6. Env и конфигурация

Для разработки использовать env-файл:

```text
assets/develop.env
```

Важно: слабая модель должна учитывать, что часть поведения wear-модуля уже управляется через `flutter_dotenv`. Нельзя хардкодить эти значения в новых classes для очков.

Текущие переменные в `assets/develop.env`:

| Переменная | Пример | Назначение |
|---|---|---|
| `ENVIRONMENT` | `dev` | окружение приложения |
| `WEAR_MOCK_AUTH_ON_LOGO` | `false` | mock-авторизация по тапу на логотип |
| `WEAR_MOCK_SKIP_AUTH_ON_LOGO` | `false` | mock-пропуск авторизации по long-press |
| `WEAR_SKIP_SCANNER_CONNECT_SCREEN` | `true` | пропустить стартовый экран подключения сканера |
| `METRICS_BASE_URL` | `http://10.5.97.75:80` | endpoint метрик |
| `DIO_PROXY_HOST` | commented | proxy host для Dio, если нужен |
| `DIO_PROXY_PORT` | commented | proxy port для Dio, если нужен |
| `DBTO_HOST` | `192.168.140.1` | Firebird host |
| `DBTO_PORT` | `3050` | Firebird port |
| `DBTO_PATH` | `/base/ws578096.gdb` | путь к БД |
| `DBTO_USER` | `C_WATCH` | пользователь БД |
| `DBTO_PASSWORD` | задано в env | пароль БД |
| `DBTO_ROLE` | `R_TSDSERVER` | роль БД |
| `AUTH_SERVICE_HOST` | `192.168.140.1` | host auth-сервиса |
| `AUTH_SERVICE_PORT` | `9950` | port auth-сервиса |

### Правила для реализации

- Перед запуском wear flow env должен быть загружен через `dotenv.load(fileName: 'assets/develop.env')` или уже существующий bootstrap проекта.
- Не добавлять новые `.env` файлы без необходимости.
- Не переносить значения из `assets/develop.env` прямо в Dart/Kotlin код.
- Если для второго экрана понадобится feature flag, добавить его в `assets/develop.env`, например:

```env
WEAR_GLASSES_ENABLED=true
WEAR_GLASSES_AUTO_SHOW=true
```

- На первом этапе можно не добавлять новые env-переменные, а включить дублирование всегда для wear flow. Но если нужен быстрый rollback на устройстве — лучше добавить `WEAR_GLASSES_ENABLED`.
- Если `WEAR_SKIP_SCANNER_CONNECT_SCREEN=true`, initial route wear-модуля сразу `WearMainScreen`, и очки должны показывать auth waiting screen сразу при входе в `WearMainScreen`.
- Если `WEAR_MOCK_AUTH_ON_LOGO` или `WEAR_MOCK_SKIP_AUTH_ON_LOGO` включены, glasses UI должен отображать те же состояния авторизации, что и реальный flow: waiting → loading/success или error. Mock не должен обходить отправку состояния на очки.
- Если env не загружен или обязательные переменные отсутствуют, бизнес-ошибка остаётся в phone wear flow, а на очки отправляется только display-state ошибки через `WearGlassesBridge`.

### Проверить перед реализацией

Найти место загрузки env в проекте и убедиться, что `assets/develop.env` реально используется до входа в wear-модуль. Если загрузки нет или она использует другой файл, сначала согласовать с пользователем, где правильно грузить env.

---

## 7. Рекомендуемая структура файлов

Добавить отдельную feature внутри существующего `features/glasses`, а не смешивать с phone `wear` UI:

```text
lib/features/glasses/presentation/
├── cubit/
│   └── wear/
│       ├── wear_glasses_cubit.dart
│       └── wear_glasses_state.dart
├── screens/
│   └── wear/
│       ├── wear_glasses_auth_screen.dart
│       ├── wear_glasses_menu_screen.dart
│       ├── wear_glasses_printer_screen.dart
│       ├── wear_glasses_scan_screen.dart
│       ├── wear_glasses_product_select_screen.dart
│       ├── wear_glasses_print_screen.dart
│       ├── wear_glasses_status_screen.dart
│       └── wear_glasses_help_screen.dart
└── widgets/
    └── wear/
        ├── wear_glasses_scaffold.dart
        ├── wear_glasses_title_block.dart
        ├── wear_glasses_status_bar.dart
        ├── wear_glasses_progress.dart
        ├── wear_glasses_list.dart
        └── wear_glasses_action_buttons.dart
```

Добавить mapper/service на стороне phone runtime:

```text
lib/modules/wear/presentation/glasses/
├── wear_glasses_bridge.dart
├── wear_glasses_payload.dart
└── wear_glasses_route_mapper.dart
```

Назначение:

- `WearGlassesBridge` — отправляет команды в `MethodChannelService`.
- `WearGlassesPayload` — DTO для передачи на очки.
- `WearGlassesRouteMapper` — маппит состояния wear flow в route/payload для очков.

---

## 8. Расширение MethodChannel

### Добавить методы в `MethodChannelService`

Файл:

```text
lib/core/services/method_channel_service.dart
```

Добавить методы:

```dart
Future<void> showWearGlasses(Map<String, dynamic> payload)
Future<void> updateWearGlasses(Map<String, dynamic> payload)
Future<void> hideWearGlasses()
```

Методы должны вызывать `app_channel`:

```text
showWearGlasses
updateWearGlasses
hideWearGlasses
```

### Добавить обработку в Android

Файл:

```text
android/app/src/main/kotlin/ru/tander/smart_glasses/MainActivity.kt
```

В `app_channel` добавить cases:

```kotlin
"showWearGlasses" -> { ... }
"updateWearGlasses" -> { ... }
"hideWearGlasses" -> { ... }
```

Логика:

1. `showWearGlasses`:
   - убедиться, что `glassesPresentation` показан на втором дисплее;
   - отправить в `glassesChannel.invokeMethod("navigateToRoute", "/wear")` или сразу `navigateToScreen`;
   - отправить payload через `glassesChannel.invokeMethod("updateWearGlasses", payload)`.
2. `updateWearGlasses`:
   - если presentation уже есть — отправить payload на glasses runtime;
   - если presentation нет — можно создать presentation или просто залогировать, решение выбрать явно.
3. `hideWearGlasses`:
   - навигировать на `/empty` или скрыть presentation. Безопаснее сначала `/empty`.

### Добавить обработку в `GlassesCoordinatorCubit`

Файл:

```text
lib/app/glasses/glasses_coordinator_cubit.dart
```

Добавить обработку method call:

```dart
case 'updateWearGlasses':
  _handleUpdateWearGlasses(call.arguments);
```

Передать callback в `WearGlassesCubit`:

```dart
final Function(Map<String, dynamic> payload) onUpdateWearGlasses;
```

---

## 9. Роуты glasses runtime

Файл:

```text
lib/app/glasses/glasses_runtime_app.dart
```

Добавить `WearGlassesCubit`:

```dart
late final WearGlassesCubit _wearGlassesCubit;
```

В `initState()`:

```dart
_wearGlassesCubit = WearGlassesCubit();
```

Передать callback в coordinator:

```dart
onUpdateWearGlasses: _wearGlassesCubit.updateFromPayload,
```

В `MultiBlocProvider`:

```dart
BlocProvider.value(value: _wearGlassesCubit),
```

В `_buildScreen()` добавить route:

```dart
case '/wear':
  return const WearGlassesScreen();
```

Где `WearGlassesScreen` — общий экран-router, который внутри выбирает конкретное представление по `state.screenType`:

```dart
switch (state.screenType) {
  case WearGlassesScreenType.auth: return WearGlassesAuthScreen(...);
  case WearGlassesScreenType.menu: return WearGlassesMenuScreen(...);
  case WearGlassesScreenType.printer: return WearGlassesPrinterScreen(...);
  case WearGlassesScreenType.scan: return WearGlassesScanScreen(...);
  case WearGlassesScreenType.productSelect: return WearGlassesProductSelectScreen(...);
  case WearGlassesScreenType.printing: return WearGlassesPrintScreen(...);
  case WearGlassesScreenType.status: return WearGlassesStatusScreen(...);
  case WearGlassesScreenType.help: return WearGlassesHelpScreen(...);
}
```

---

## 10. Payload contract

Сделать простой JSON-совместимый контракт, без передачи Dart-объектов напрямую.

Пример:

```dart
{
  "screenType": "auth",
  "phase": "waitingBarcode",
  "title": "Авторизация",
  "subtitle": "Наведите камеру на штрих-код",
  "statusText": "Поиск ШК",
  "isLoading": false,
  "isError": false,
  "items": [],
  "selectedIndex": 0,
  "pageText": null,
  "primaryAction": null,
  "secondaryAction": null,
}
```

Минимальная модель:

```dart
enum WearGlassesScreenType {
  auth,
  menu,
  printer,
  scan,
  productSelect,
  printing,
  status,
  help,
}

enum WearGlassesPhase {
  idle,
  loading,
  scanning,
  recognizing,
  success,
  error,
}
```

Поля:

| Поле | Тип | Назначение |
|---|---|---|
| `screenType` | String | какой glasses screen показывать |
| `phase` | String | состояние: idle/loading/scanning/success/error |
| `title` | String | главный заголовок |
| `subtitle` | String? | вторичный текст |
| `statusText` | String? | короткий статус |
| `isLoading` | bool | показать progress/spinner |
| `isError` | bool | error styling |
| `items` | List<Map> | элементы списка |
| `selectedIndex` | int | выбранный элемент |
| `pageText` | String? | например `Страница: 1 из 2` |
| `primaryAction` | String? | текст основной кнопки |
| `secondaryAction` | String? | текст второй кнопки |

---

## 11. Маппинг wear flow -> glasses UI

### Авторизация

Phone screen:

```text
WearMainScreen + WearAuthNotifier
```

Glasses design frames:

- `Авторизация_Поиск ШК`
- `Авторизация_Сканирую`
- `Авторизация_Распознаю`
- `Авторизация_Авторизация`
- `Авторизация_Успешно`
- `Авторизация_ШК не распознан`
- `Авторизация_Ошибка авторизации`

План:

1. При входе на `WearMainScreen` вызвать `showWearGlasses(auth waitingBarcode)`.
2. При scan event отправить `auth scanning/recognizing`.
3. Во время API auth отправить `auth loading` с title `Авторизация`.
4. При успехе отправить `auth success`, затем при переходе телефона на menu отправить `menu`.
5. При ошибке отправить `auth error`.

Важно: не менять `AuthenticateUserUseCase`, `AuthDataSource`, `WearSession`.

### Главное меню / выбор раздела

Phone screen:

```text
WearMenuScreen
```

Glasses design frames:

- `Выбор раздела_Инициализация`
- `Выбор раздела_Список`

Payload:

```dart
screenType: "menu"
title: "Выбор раздела"
items: ["Печать ценников", "Настройки", "Выход"]
selectedIndex: currentIndex
```

На первом этапе можно показывать статический список, без управления выбором с очков. Phone остаётся источником навигации.

### Выбор режима печати

Если в текущей бизнес-логике режим печати явно отсутствует, не добавлять новый бизнес-step. Можно оставить этот design frame как будущий экран.

### Выбор принтера

Phone screen:

```text
WearPrinterSelectScreen + WearPrinterSelectNotifier
```

Glasses design frames:

- `Выбор Принтера Белый_Список`
- `Выбор Принтера Желтый_Список`

Payload:

```dart
screenType: "printer"
title: "Выбор принтера"
subtitle: step == white ? "Белые ценники" : "Жёлтые ценники"
items: printers.map((p) => p.name).toList()
selectedIndex: selectedIndex
pageText: "Страница: 1 из N"
```

Не менять use case загрузки принтеров.

### Сканирование товара

Phone screen:

```text
WearScanIdleScreen + WearScanNotifier
```

Glasses design frames:

- `Сканирование товара_Поиск ШК`
- `Сканирование товара_ШК отсканирован`
- `Сканирование товара_ШК не распознан`
- `Сканирование товара_Ошибка сканирования (техническая)`
- `Сканирование товара_Ценник не найден`

Payload examples:

```dart
// waiting
screenType: "scan"
phase: "scanning"
title: "Сканирование товара"
subtitle: "Наведите камеру на штрих-код"

// barcode found
screenType: "scan"
phase: "success"
title: "Сканирование товара"
subtitle: "ШК отсканирован"

// error
screenType: "status"
phase: "error"
title: "ШК не распознан"
subtitle: errorMessage
```

### Дубль ШК / выбор товара

Phone screen:

```text
WearProductSelectScreen
```

Glasses design frame:

- `Сканирование товара_Дубль ШК`

Payload:

```dart
screenType: "productSelect"
title: "Дубль ШК"
subtitle: "Выберите нужный товар"
items: products.map((p) => p.name).toList()
selectedIndex: selectedIndex
pageText: "Страница: 1 из N"
```

### Отправка на печать / успех / продолжить

Phone screens/states:

```text
WearScanNotifier -> PrintPriceTagUseCase -> WearStatusScreen
```

Glasses design frames:

- `Сканирование товара_Отправляем на печать`
- `Сканирование товара_Техническая ошибка`
- `Сканирование товара_Продолжить печать`

Payload:

```dart
// printing
screenType: "printing"
phase: "loading"
title: "Печать ценника"
subtitle: "<product name>\nЦена: <price>"
statusText: "Отправляем на печать"

// continue prompt
screenType: "printing"
phase: "success"
title: "Продолжить\nпечать ценников?"
primaryAction: "Продолжить"
secondaryAction: "Завершить"
```

---

## 12. Где подключать отправку состояния

Слабой модели лучше делать маленькими безопасными шагами.

### Шаг 1 — создать bridge без интеграции

Создать:

```text
lib/modules/wear/presentation/glasses/wear_glasses_payload.dart
lib/modules/wear/presentation/glasses/wear_glasses_bridge.dart
```

`WearGlassesBridge` должен принимать `MethodChannelService` и иметь методы:

```dart
Future<void> show(WearGlassesPayload payload)
Future<void> update(WearGlassesPayload payload)
Future<void> hide()
```

### Шаг 2 — подключить только вход/выход модуля

В `WearMainScreen.initState` или безопасном lifecycle месте:

```dart
WearGlassesBridge.show(authWaitingPayload)
```

При выходе из wear-модуля:

```dart
WearGlassesBridge.hide()
```

Если lifecycle экрана неудобен, сначала сделать вызовы из Notifier при старте/событии, но не ломать provider lifecycle.

### Шаг 3 — добавить auth updates

В `WearAuthNotifier` при изменении состояний отправлять payload на очки.

Не менять порядок бизнес-операций.

### Шаг 4 — добавить menu/printer/scan updates

Подключать по одному экрану:

1. `WearMenuScreen`
2. `WearPrinterSelectScreen`
3. `WearScanIdleScreen`
4. `WearProductSelectScreen`
5. `WearStatusScreen`

После каждого шага запускать `flutter analyze`.

---

## 13. UI-компоненты очков

### `WearGlassesScaffold`

Общие параметры:

```dart
Scaffold(
  backgroundColor: const Color(0xFF2A2828),
  body: SizedBox.expand(...),
)
```

Safe layout:

```dart
Padding(
  padding: EdgeInsets.fromLTRB(30, 20, 30, 80),
  child: ...
)
```

Почему нижний padding большой: в макете используется `[20,30,80,30]`, нижняя зона оставлена под ограничения отображения/видимости очков.

### Типографика

Ориентиры из макета:

- title: `36-40`, weight `500`, color `#26BC00`;
- subtitle: `20`, color `#26BC00`;
- list item: `18-20`;
- page text: `15`.

### Списки

Для списков на очках:

- максимум 4-5 элементов на странице;
- выбранный элемент подсвечивать рамкой/полупрозрачным зелёным фоном;
- если элементов больше — показывать `Страница: X из Y`;
- не пытаться делать полноценный scroll на первом этапе.

---

## 14. Что слабой модели запрещено менять

Без отдельного согласования не менять:

- `BdtoDataSource` stored procedure calls;
- `AuthenticateUserUseCase`;
- `PrintPriceTagUseCase`;
- `WearSession` semantics;
- voice pipeline (`VoiceTypingService`, `AudioStreamService`, `SpeechRecognitionService`);
- scanner delegate lifecycle;
- существующие phone screens layout, если задача только про очки;
- names существующих MethodChannel методов без обновления Android side;
- значения из `assets/develop.env` — не хардкодить их в Dart/Kotlin.

---

## 15. Проверки после каждого этапа

Минимум:

```bash
flutter analyze
```

Перед ручной проверкой убедиться, что приложение использует:

```text
assets/develop.env
```

И что для локальной разработки актуальны значения:

```text
WEAR_SKIP_SCANNER_CONNECT_SCREEN=true
AUTH_SERVICE_HOST=192.168.140.1
AUTH_SERVICE_PORT=9950
DBTO_HOST=192.168.140.1
DBTO_PORT=3050
```

Если менялись generated/freezed файлы:

```bash
dart run build_runner build --delete-conflicting-outputs
```

Если менялся Android bridge:

```bash
flutter build apk --debug
```

Ручная проверка на устройстве:

1. Запустить приложение.
2. Убедиться, что в логах есть `SecondDisplay 640x480`.
3. Открыть wear flow на телефоне.
4. Проверить, что на очках показывается auth screen.
5. Пройти авторизацию.
6. Проверить смену экранов: menu → printer → scan → status.
7. Проверить, что телефонный flow не изменился.

---

## 16. Риски и когда звать сильную модель

Эта задача затрагивает high-risk зоны:

- `MethodChannelService`;
- Android `MainActivity.kt` bridge;
- `glassesMain` / `GlassesRuntimeApp`;
- навигацию второго runtime;
- одновременное отображение phone + glasses;
- env/bootstrap, если окажется, что `assets/develop.env` не загружается до wear flow.

После плана и первого implementation pass нужен review сильной моделью или ручной архитектурный review.

Перед review подготовить:

- список изменённых файлов;
- diff summary;
- результаты `flutter analyze`;
- если менялся Android — результат `flutter build apk --debug`;
- какие экраны уже дублируются на очки.

---

## 17. Рекомендуемый порядок реализации для слабой модели

```text
1. Прочитать:
   - arhitecture.md
   - lib/modules/wear/ARCHITECTURE.md
   - этот файл
   - assets/develop.env
   - MethodChannelService
   - MainActivity.kt
   - GlassesRuntimeApp
   - GlassesCoordinatorCubit

2. Проверить, где и когда загружается flutter_dotenv, и убедиться, что используется assets/develop.env.

3. Создать payload/bridge классы без подключения к UI.

4. Расширить MethodChannelService новыми методами show/update/hide wear glasses.

5. Расширить Android MainActivity.kt обработкой новых методов.

6. Создать WearGlassesCubit/State в glasses runtime.

7. Добавить route `/wear` в GlassesRuntimeApp.

8. Создать базовый WearGlassesScreen с auth waiting UI по макету.

9. Подключить показ auth waiting при входе в WearMainScreen. Учитывать `WEAR_SKIP_SCANNER_CONNECT_SCREEN=true`: при таком env очки должны открываться сразу на auth waiting.

10. Запустить flutter analyze.

11. Только после успешной проверки добавлять остальные состояния:
    - auth loading/success/error
    - menu
    - printer selection
    - scan waiting/found/error
    - product duplicate list
    - printing/success/continue

12. После каждого блока снова запускать flutter analyze.
```

---

## 18. Минимальный первый результат

Если нужно сделать минимальный безопасный MVP, то реализовать только:

1. `showWearGlasses` / `updateWearGlasses` bridge.
2. Route `/wear` в glasses runtime.
3. Один универсальный `WearGlassesScreen`.
4. Отображение:
   - авторизация: ожидание ШК / loading / success / error;
   - меню: title + список;
   - сканирование товара: ожидание ШК / отправляем на печать / success/error.

Это уже даст параллельное отображение на 1 и 2 экране без глубокого вмешательства в бизнес-логику.

---

## 19. Короткий JSON-план для агента

```json
{
  "task_type": "feature",
  "goal": "Duplicate wear module status screens to glasses second display while preserving phone business logic",
  "assumptions": [
    "Second display resolution is 640x480",
    "design.pen frames are source of truth for glasses UI",
    "assets/develop.env is the development env file and must not be hardcoded into code",
    "Phone wear flow remains source of business state",
    "Glasses runtime is display-only projection"
  ],
  "affected_scope": {
    "features": ["wear", "glasses", "native_bridge"],
    "files": [
      "lib/core/services/method_channel_service.dart",
      "android/app/src/main/kotlin/ru/tander/smart_glasses/MainActivity.kt",
      "lib/app/glasses/glasses_runtime_app.dart",
      "lib/app/glasses/glasses_coordinator_cubit.dart",
      "lib/features/glasses/presentation/cubit/wear/*",
      "lib/features/glasses/presentation/screens/wear/*",
      "lib/features/glasses/presentation/widgets/wear/*",
      "lib/modules/wear/presentation/glasses/*",
      "assets/develop.env only if adding explicit feature flags",
      "selected lib/modules/wear/presentation/screens/* files only for sending display state"
    ]
  },
  "architecture_checks": [
    "MethodChannel method names match Dart and Android",
    "flutter_dotenv loads assets/develop.env before wear flow",
    "Glasses runtime does not contain wear business logic",
    "Phone flow still works without second display",
    "Cubit/provider lifecycle is not broken",
    "All glasses UI fits 640x480"
  ],
  "plan_steps": [
    {"step": "Verify env loading", "why": "Wear flow depends on assets/develop.env values", "verify": "find dotenv.load and confirm fileName"},
    {"step": "Create payload and bridge", "why": "Centralize glasses communication", "verify": "flutter analyze"},
    {"step": "Extend MethodChannelService and Android handler", "why": "Allow wear module to control glasses display", "verify": "flutter analyze and debug apk build"},
    {"step": "Create WearGlassesCubit and route /wear", "why": "Store glasses display state in glasses runtime", "verify": "manual second display route"},
    {"step": "Implement 640x480 UI components from design.pen", "why": "Match target glasses design", "verify": "screenshot/device check"},
    {"step": "Wire auth/menu/printer/scan/status states one by one", "why": "Low-risk incremental integration", "verify": "flutter analyze after each block"}
  ],
  "verification_commands": [
    "flutter analyze",
    "flutter build apk --debug"
  ],
  "risk_level": "high",
  "escalate_to_strong": true
}
```
