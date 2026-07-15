# Smart Glasses
FLUTTER 3.41.6 !

Flutter-приложение для Android с dual-screen: основной экран телефона + отдельный runtime для smart glasses.

## Архитектура

Feature-First. Основное приложение использует Cubit/BLoC, wear-модуль использует Riverpod/Notifier и собственный `GoRouter`.

```
lib/
├── app/             # DI, приложение, glasses runtime
├── core/            # constants, services, utils
├── features/        # home, glasses, initialization, scanner, voice
└── modules/wear/    # сценарий печати/проверки товара
```

Два entrypoint:

- `main()` — основной runtime телефона.
- `glassesMain()` — runtime очков (`GlassesRuntimeApp`).

Связь с native Android идет через `MethodChannelService`. UI не вызывает MethodChannel напрямую.

## Реализовано

- Home Screen с управлением и отображением
- Offline voice recognition (Vosk)
- Barcode scanner (multi_scanner)
- Runtime очков: main, screen2, empty, initialization, wear
- MethodChannel связь Main ↔ Glasses
- Wear-модуль: авторизация, выбор принтера, сканирование, голосовой/цифровой ввод, печать ценника
- Wear glasses output через `WearGlassesBridge` / `WearFlowController`
- Проверка наличия товара в wear-модуле с projection state на очки

## Wear module

`WearModuleApp` открывается из `HomeScreen` через `Navigator.push` в отдельном `ProviderScope`.

Основные части:

- `application/` — `WearFlowController`, ports, navigation requests
- `config/` — `WearDependencies`, `WearSession`, mock/env config
- `data/` — auth через `dio`, Firebird REST-client через `fbdb`
- `domain/` — use cases, voice typing, voice commands
- `infrastructure/` — Flutter/Noop adapters
- `navigation/wear_routes.dart` — маршруты wear-модуля
- `presentation/` — screens, cubits/notifiers, widgets
- `services/` — voice session, wifi/printer/status services

Голосовые сервисы wear используют общий `AudioStreamService` и `SpeechRecognitionService`. `WearVoiceSession` переключает Vosk между `grammar` для системных команд и `freeText` для списков/диктовки без перезапуска микрофона.

Wear UI на очках получает только `WearGlassesPayload`: business logic остается в phone runtime, а glasses runtime отображает projection state через `/wear`.

## Env

Env загружается из `assets/develop.env`. Если ключ не задан, `main.dart` применяет defaults:

| Key | Default |
|---|---|
| `WEAR_GLASSES_ENABLED` | `true` |
| `WEAR_USE_MOCKS` | `false` |
| `WEAR_MOCK_AUTH_ON_LOGO` | `false` |
| `WEAR_MOCK_SKIP_AUTH_ON_LOGO` | `false` |
| `WEAR_SKIP_SCANNER_CONNECT_SCREEN` | `false` |

## Документация

- [ARCHITECTURE.md](ARCHITECTURE.md) — основная архитектура проекта
- [docs/wear_ARCHITECTURE.md](docs/wear_ARCHITECTURE.md) — архитектура wear-модуля
- [docs/wear_voice_background_navigation_problem.md](docs/wear_voice_background_navigation_problem.md) — контекст по voice/background navigation
- [docs/INDEX.md](docs/INDEX.md) — индекс документации

## Добавление экрана в очки

### 1. State + Cubit + Screen

```dart
// state
sealed class GlassesScreenXState { const GlassesScreenXState(); }
class GlassesScreenXInitial extends GlassesScreenXState {}
class GlassesScreenXUpdated extends GlassesScreenXState {
  const GlassesScreenXUpdated({required this.data});
  final String data;
}

// cubit
class GlassesScreenXCubit extends Cubit<GlassesScreenXState> {
  GlassesScreenXCubit() : super(const GlassesScreenXInitial());
  void updateData(String data) => emit(GlassesScreenXUpdated(data: data));
}

// screen
class GlassesScreenX extends StatelessWidget {
  @override
  Widget build(BuildContext context) => BlocBuilder<GlassesScreenXCubit, GlassesScreenXState>(
    builder: (context, state) => Text(state is GlassesScreenXUpdated ? state.data : ''),
  );
}
```

### 2. Подключение в `GlassesRuntimeApp`

```dart
late final GlassesScreenXCubit _screenXCubit;
_screenXCubit = GlassesScreenXCubit();

// _buildScreen:
case '/screenX': return const GlassesScreenX();

// providers:
BlocProvider.value(value: _screenXCubit),

// dispose:
_screenXCubit.close(),
```

### 3. Навигация

```kotlin
// MainActivity.kt
methodChannel.invokeMethod("navigateGlassesToRoute", "/screenX")
```

## Build

```bash
flutter pub get
flutter run
```

Targeted checks used for recent voice/glasses changes:

```bash
flutter test test/voice_list_matcher_test.dart test/voice_command_parser_service_test.dart test/wear_flow_controller_test.dart
```

`./gradlew app:compileDebugKotlin` может падать в external `multi_scanner` из `.pub-cache` на unresolved `BTDevices` / `BattaryStateList` / `BattaryState`.
