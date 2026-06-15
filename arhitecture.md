# Architecture

## Содержание

1. [Назначение проекта](#назначение-проекта)
2. [Технологический стек](#технологический-стек)
3. [Архитектурные принципы](#архитектурные-принципы)
   - [Separation of Concerns](#separation-of-concerns)
   - [Unidirectional Data Flow](#unidirectional-data-flow)
   - [Dependency Inversion](#dependency-inversion)
4. [Структура каталогов](#структура-каталогов)
5. [Слои приложения](#слои-приложения)
   - [Presentation Layer](#presentation-layer)
   - [Domain Layer](#domain-layer)
   - [Data Layer](#data-layer)
6. [Управление состоянием](#управление-состоянием)
   - [BLoC/Cubit](#bloccubit)
   - [Riverpod](#riverpod)
   - [State Management Guidelines](#state-management-guidelines)
7. [Dependency Injection](#dependency-injection)
   - [Принципы DI](#принципы-di)
   - [Provider Pattern](#provider-pattern)
8. [Обработка ошибок](#обработка-ошибок)
   - [Result Pattern](#result-pattern)
   - [Error Handling Best Practices](#error-handling-best-practices)
9. [Навигация](#навигация)
   - [GoRouter](#gorouter)
   - [Navigator](#navigator)
10. [Native Bridge](#native-bridge)
11. [Тестирование](#тестирование)
    - [Unit Tests](#unit-tests)
    - [Widget Tests](#widget-tests)
    - [Integration Tests](#integration-tests)
12. [Правила изменений](#правила-изменений)
13. [Runtime-контуры](#runtime-контуры)
14. [Архитектурные инварианты](#архитектурные-инварианты)

---

## Назначение проекта

`smart_glasses` - Flutter-приложение для Android с двумя runtime-контурами:

- **Основной экран телефона** - управление очками, инициализация голоса и сканера
- **Отдельный экран для smart glasses** - запуск через entrypoint `glassesMain`

Приложение объединяет:
- Управление smart glasses
- Offline-распознавание речи через Vosk
- Сканер штрихкодов через `multi_scanner`
- Связь с native Android через `MethodChannel`
- Печать ценников (модуль Wear)

---

## Технологический стек

| Категория | Основное приложение | Модуль Wear |
|-----------|-------------------|-------------|
| **UI Framework** | Flutter Material | Flutter Material |
| **State Management** | `flutter_bloc` / Cubit | `flutter_riverpod` (StateNotifierProvider) |
| **Navigation** | Navigator (MaterialPageRoute) | `go_router` |
| **DI** | DependenciesContainer + InheritedWidget | `WearDependencies` (ручной singleton) |
| **Voice Recognition** | `vosk_flutter_service` + `record` | Vosk через WearDependencies |
| **Scanner** | `multi_scanner` | `multi_scanner` |
| **Database** | - | `fbdb` (Firebird через REST) |
| **Network** | `dio` | `dio` |
| **Immutable Models** | `freezed` | `freezed` |
| **Native Bridge** | `MethodChannelService` | - |

---

## Архитектурные принципы

### Separation of Concerns

Согласно [Flutter Architecture Guide](https://github.com/flutter/website/blob/main/sites/docs/src/content/app-architecture/recommendations.md), приложение должно быть разделено на слои, где каждый компонент имеет **distinct responsibilities**, **well-defined interface**, **boundaries**, и **dependencies**.

```
┌─────────────────────────────────────────────────────────────┐
│                    Presentation Layer                        │
│  (Widgets, Screens, Cubits/ViewModels, State Management)     │
├─────────────────────────────────────────────────────────────┤
│                      Domain Layer                            │
│  (Use Cases, Entities, Repository Interfaces)               │
├─────────────────────────────────────────────────────────────┤
│                       Data Layer                             │
│  (Repository Implementations, Data Sources, DTOs)            │
└─────────────────────────────────────────────────────────────┘
```

### Unidirectional Data Flow

```
User Action → Event → Business Logic → State Update → UI Re-render
```

Каждый слой взаимодействует только с соседними слоями:
- **Presentation** → вызывает use cases
- **Domain** → содержит business logic, не зависит от фреймворков
- **Data** → реализует repository interfaces

### Dependency Inversion

```
┌─────────────────┐         ┌─────────────────┐
│  Presentation   │────────▶│     Domain      │
│                 │         │                 │
│  зависит от    │         │  НЕ зависит от │
│  Domain         │         │  Presentation   │
└─────────────────┘         └─────────────────┘
         │                           ▲
         │                           │
         ▼                           │
┌─────────────────┐         ┌─────────────────┐
│      Data       │────────▶│     Domain      │
│                 │         │                 │
│  реализует     │         │  определяет    │
│  interfaces    │         │  interfaces    │
└─────────────────┘         └─────────────────┘
```

---

## Структура каталогов

```
lib/
├── main.dart                      # Entry point телефона
├── app/
│   ├── app.dart                   # MyApp widget
│   ├── data/
│   │   └── network/              # Network layer
│   │       └── network_requests/
│   │           └── api_request.dart
│   ├── di/                       # Dependency Injection
│   │   ├── app_scope.dart
│   │   └── dependencies_container.dart
│   └── glasses/                  # Glasses runtime
│       ├── glasses_runtime_app.dart
│       ├── glasses_coordinator_cubit.dart
│       └── glasses_coordinator_state.dart
├── core/                         # Shared infrastructure
│   ├── constants/
│   │   └── app_constants.dart
│   ├── services/
│   │   └── method_channel_service.dart
│   └── utils/
│       └── inherited_extension.dart
├── features/                     # Feature-first modules
│   ├── initialization/
│   │   └── presentation/
│   │       ├── cubit/
│   │       │   ├── initialization_cubit.dart
│   │       │   └── initialization_state.dart
│   │       └── screens/
│   │           └── initialization_screen.dart
│   ├── home/
│   │   └── presentation/
│   │       ├── cubit/
│   │       ├── screens/
│   │       └── widgets/
│   ├── scanner/
│   │   └── presentation/
│   │       └── cubit/
│   ├── voice/
│   │   └── presentation/
│   │       └── cubit/
│   └── glasses/
│       └── presentation/
│           ├── cubit/
│           ├── screens/
│           └── widgets/
└── modules/                      # Standalone modules
    └── wear/                      # Price tag printing module
        ├── config/                # DI & session
        ├── data/                  # Data sources & DTOs
        │   ├── auth/
        │   ├── bdto/
        │   └── printer/
        ├── domain/                # Business logic
        │   ├── auth/
        │   │   ├── model/
        │   │   └── use_case/
        │   ├── price_tag_print/
        │   │   ├── model/
        │   │   └── use_case/
        │   └── service/           # Domain services
        │       ├── voice_typing/
        │       └── voice_command/
        ├── presentation/         # UI layer
        │   ├── cubit/            # BLoC/Cubit
        │   ├── providers/         # Riverpod providers
        │   ├── screens/
        │   └── widgets/
        ├── navigation/            # GoRouter config
        └── theme/                 # Colors, typography, images
```

### Структура модуля Wear (Clean Architecture)

```
modules/wear/
├── config/
│   ├── wear_dependencies.dart     # DI container
│   └── wear_session.dart          # Session state
├── data/                          # Data Layer
│   ├── auth/
│   │   ├── data_source/
│   │   │   ├── auth_data_source.dart
│   │   │   └── auth_dio_client.dart
│   │   └── model/
│   │       └── auth_user.dart
│   ├── bdto/                      # Backend DTOs
│   │   ├── data_source/
│   │   │   ├── bdto_datasource.dart
│   │   │   └── fbdb_error_handler.dart
│   │   └── model/
│   │       ├── enum/
│   │       └── *.dart
│   └── printer/
│       └── data_source/
├── domain/                        # Domain Layer
│   ├── auth/
│   │   ├── model/
│   │   │   └── authenticated_user.dart
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
│       └── voice_typing/
│           ├── audio_stream_service.dart
│           ├── number_parser_service.dart
│           ├── speech_recognition_service.dart
│           ├── tokenizer.dart
│           └── voice_typing_service.dart
├── presentation/                   # Presentation Layer
│   ├── cubit/
│   ├── providers/
│   ├── screens/
│   ├── widgets/
│   └── utils/
└── navigation/
    └── wear_routes.dart
```

---

## Слои приложения

### Presentation Layer

**Ответственность**: Отображение UI, обработка пользовательского ввода, управление состоянием виджетов.

**Компоненты**:
- `Screens` - полноэкранные виджеты
- `Widgets` - переиспользуемые UI компоненты
- `Cubits/StateNotifiers` - управление состоянием экрана
- `Providers` - Riverpod провайдеры состояния

**Принципы**:
- UI компоненты не содержат бизнес-логику
- Состояние управляется через State Management
- Widgets получают данные через конструктор или Provider
- Нет прямых вызовов к native platform (использовать Service)

**Пример структуры экрана**:

```dart
// presentation/screens/example_screen.dart
class ExampleScreen extends StatelessWidget {
  const ExampleScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ExampleCubit, ExampleState>(
      builder: (context, state) {
        return switch (state) {
          ExampleInitial() => const ExampleInitialWidget(),
          ExampleLoading() => const ExampleLoadingWidget(),
          ExampleLoaded(data: final data) => ExampleLoadedWidget(data: data),
          ExampleError(message: final message) => ExampleErrorWidget(message: message),
        };
      },
    );
  }
}
```

### Domain Layer

**Ответственность**: Business logic, правила предметной области, contracts для data layer.

**Компоненты**:
- `Entities` - бизнес-объекты (не зависят от фреймворков)
- `Use Cases` - описывают действия пользователя
- `Repository Interfaces` - абстракции для доступа к данным
- `Domain Services` - бизнес-логика, не принадлежащая конкретной entity

**Принципы**:
- Не зависит от Flutter или других framework-specific библиотек
- Entities - plain Dart classes
- Use Cases содержат один метод `call()`
- Repository - абстрактный класс/интерфейс

**Пример Use Case**:

```dart
// domain/auth/use_case/authenticate_user_use_case.dart
class AuthenticateUserUseCase {
  final AuthRepository _repository;

  AuthenticateUserUseCase(this._repository);

  Future<Result<AuthenticatedUser>> call(String badgeBarcode) async {
    if (badgeBarcode.isEmpty) {
      return Result.error(AuthException('Badge barcode cannot be empty'));
    }
    return _repository.authenticate(badgeBarcode);
  }
}
```

**Пример Entity**:

```dart
// domain/price_tag_print/model/available_printer.dart
@freezed
class AvailablePrinter with _$AvailablePrinter {
  const factory AvailablePrinter({
    required String id,
    required String name,
    required PrinterKind kind,
    required PrinterMobilityType mobility,
    required bool isAvailable,
  }) = _AvailablePrinter;

  const AvailablePrinter._();
}
```

### Data Layer

**Ответственность**: Реализация repository interfaces, доступ к внешним источникам данных.

**Компоненты**:
- `Repository Implementations` - реализуют domain repository interfaces
- `Data Sources` - абстракции над источниками данных (API, DB, local storage)
- `DTOs` - Data Transfer Objects для сериализации
- `Mappers` - конвертация DTO → Domain Entity

**Принципы**:
- Зависит только от domain layer interfaces
- Data sources инкапсулируют работу с external APIs/BaaS
- DTOs соответствуют структуре API/BaaS responses
- Mappers выполняют преобразование DTO → Entity

**Пример Data Source**:

```dart
// data/auth/data_source/auth_data_source.dart
class AuthDataSource {
  final AuthDioClient _client;

  AuthDataSource(this._client);

  Future<AuthUserDto> authenticate(String badgeBarcode) async {
    final response = await _client.authenticate({'badge': badgeBarcode});
    return AuthUserDto.fromJson(response.data);
  }
}
```

**Пример Repository Implementation**:

```dart
// Реализация в domain использует abstract class
// data/auth/repository/auth_repository_impl.dart
class AuthRepositoryImpl implements AuthRepository {
  final AuthDataSource _dataSource;

  AuthRepositoryImpl(this._dataSource);

  @override
  Future<Result<AuthenticatedUser>> authenticate(String badgeBarcode) async {
    try {
      final dto = await _dataSource.authenticate(badgeBarcode);
      return Result.ok(AuthenticatedUserMapper.fromDto(dto));
    } on AuthException catch (e) {
      return Result.error(e);
    }
  }
}
```

---

## Управление состоянием

### BLoC/Cubit

**Основное приложение** использует BLoC/Cubit паттерн.

**Принципы** (согласно [Flutter BLoC best practices](https://bloclibrary.dev/)):

```dart
// State - immutable
@freezed
class ScannerState with _$ScannerState {
  const factory ScannerState.initial() = ScannerInitial;
  const factory ScannerState.connecting() = ScannerConnecting;
  const factory ScannerState.ready() = ScannerReady;
  const factory ScannerState.scanned(String barcode) = ScannerScanned;
  const factory ScannerState.error(String message) = ScannerError;
}

// Cubit - управляет состоянием
class ScannerCubit extends Cubit<ScannerState> {
  final MultiScanner _scanner;

  ScannerCubit(this._scanner) : super(const ScannerState.initial());

  Future<void> init() async {
    emit(const ScannerState.connecting());
    try {
      _scanner.addDelegate(this);
      await _scanner.init();
      emit(const ScannerState.ready());
    } catch (e) {
      emit(ScannerState.error(e.toString()));
    }
  }

  @override
  Future<void> close() {
    _scanner.removeDelegate(this);
    return super.close();
  }
}
```

**Правила**:
- Использовать sealed classes для states
- Каждый screen имеет свой Cubit
- Глобальные Cubits создаются в DependenciesContainer
- Локальные Cubits создаются через `BlocProvider(create: ...)`
- Asynchronous subscriptions отменяются в `close()`

### Riverpod

**Модуль Wear** использует Riverpod.

```dart
// presentation/providers/wear_voice_providers.dart
@riverpod
class WearVoiceNotifier extends _$WearVoiceNotifier {
  @override
  FutureOr<VoiceState> build() => const VoiceState.idle();

  Future<void> startListening() async {
    state = const AsyncValue.loading();
    try {
      await _service.start();
      state = const AsyncValue.data(VoiceState.listening());
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }
}
```

### State Management Guidelines

| Ситуация | Рекомендация |
|----------|-------------|
| Простой screen без сложной логики | Stateless widget с данными через конструктор |
| Screen с async операциями | Cubit/StateNotifier |
| Shared state между несколькими screens | Глобальный Cubit в DependenciesContainer |
| Complex state с множеством полей | Freezed immutable state |
| Real-time updates | Stream/Flow + Riverpod StreamProvider |
| Computed derived state | Selector или Provider family |

---

## Dependency Injection

### Принципы DI

**Цель**: Создание объектов в одном месте и передача в компоненты, которые их используют.

**Преимущества**:
- Loose coupling между компонентами
- Легкость тестирования (подмена зависимостей)
- Single source of truth для dependencies
- Lifecycle management объектов

### Provider Pattern

**Рекомендация**: Использовать `package:provider` согласно [Flutter DI Guide](https://github.com/flutter/website/blob/main/sites/docs/src/content/app-architecture/case-study/dependency-injection.md).

```dart
// Основное приложение: ручной DI container
class DependenciesContainer {
  late final MethodChannelService _methodChannelService;
  late final ScannerCubit _scannerCubit;
  late final VoiceCubit _voiceCubit;
  late final HomeCubit _homeCubit;

  static DependenciesContainer create() {
    final container = DependenciesContainer._();
    container._methodChannelService = MethodChannelService();
    container._scannerCubit = ScannerCubit();
    container._voiceCubit = VoiceCubit();
    container._homeCubit = HomeCubit();
    return container;
  }
}
```

**Дополнительно**: При необходимости использовать `get_it` или `injectable` для более сложных сценариев.

---

## Обработка ошибок

### Result Pattern

Согласно [Flutter Result Pattern](https://github.com/flutter/website/blob/main/sites/docs/src/content/app-architecture/design-patterns/result.md), вместо exceptions использовать `Result<T>` sealed class:

```dart
// Sealed Result class - явная обработка успеха и ошибки
sealed class Result<T> {
  const Result();

  factory Result.ok(T value) => Ok(value);
  factory Result.error(Exception error) => Error(error);
}

final class Ok<T> extends Result<T> {
  final T value;
  const Ok(this.value);
}

final class Error<T> extends Result<T> {
  final Exception error;
  const Error(this.error);
}
```

**Пример использования**:

```dart
// В Use Case
Future<Result<AuthenticatedUser>> call(String badgeBarcode) async {
  if (badgeBarcode.isEmpty) {
    return Result.error(AuthException('Badge barcode cannot be empty'));
  }
  return _repository.authenticate(badgeBarcode);
}

// В Presentation (Cubit)
Future<void> authenticate(String badgeBarcode) async {
  emit(state.copyWith(isLoading: true));
  final result = await _authenticateUserUseCase(badgeBarcode);
  switch (result) {
    case Ok(value: final user):
      emit(AuthState.authenticated(user));
    case Error(error: final error):
      emit(AuthState.error(error.message));
  }
}
```

### Error Handling Best Practices

1. **Явная обработка ошибок**: Использовать `Result<T>` вместо exceptions
2. **Domain-specific errors**: Создавать специфичные exceptions (`AuthException`, `NetworkException`)
3. **Логирование**: Логировать ошибки на уровне Data Source
4. **User-friendly messages**: Преобразовывать технические ошибки в понятные пользователю
5. **Не глотать ошибки**: Всегда обрабатывать или пробрасывать

---

## Навигация

### GoRouter

**Модуль Wear** использует `go_router` для declarative routing:

```dart
// navigation/wear_routes.dart
final GoRouter wearRouter = GoRouter(
  initialLocation: '/wear_main_screen',
  routes: [
    GoRoute(
      path: '/wear_main_screen',
      builder: (context, state) => const WearMainScreen(),
    ),
    GoRoute(
      path: '/wear_menu',
      builder: (context, state) => const WearMenuScreen(),
    ),
    // ... другие routes
  ],
);
```

### Navigator

**Основное приложение** использует классический Navigator:

```dart
// Из HomeScreen в Wear module
Navigator.push(
  context,
  MaterialPageRoute(
    builder: (_) => ProviderScope(
      child: MaterialApp.router(
        routerConfig: wearRouter,
      ),
    ),
  ),
);
```

---

## Native Bridge

`MethodChannelService` инкапсулирует взаимодействие с native Android:

```dart
// core/services/method_channel_service.dart
class MethodChannelService {
  static const _appChannel = MethodChannel('com.smart_glasses/app_channel');
  static const _glassesChannel = MethodChannel('com.smart_glasses/glasses_channel');

  Future<void> showGlasses() async {
    try {
      await _appChannel.invokeMethod('showGlasses');
    } on PlatformException catch (e) {
      log('showGlasses failed: ${e.message}');
    }
  }
}
```

**Правила**:
- Все MethodChannel вызовы через `MethodChannelService`
- Имена методов должны совпадать между Flutter и Android
- Ошибки логировать и преобразовывать в state
- Не вызывать из widgets напрямую

---

## Тестирование

Согласно [Flutter Testing Guide](https://github.com/flutter/website/blob/main/sites/docs/src/content/testing/overview.md), автоматизированное тестирование делится на три категории:

### Unit Tests

Тестируют одну функцию, метод или класс.

```dart
// unit test для UseCase
void main() {
  group('AuthenticateUserUseCase', () {
    late AuthenticateUserUseCase useCase;
    late MockAuthRepository mockRepository;

    setUp(() {
      mockRepository = MockAuthRepository();
      useCase = AuthenticateUserUseCase(mockRepository);
    });

    test('returns error for empty badge barcode', () async {
      final result = await useCase('');
      expect(result, isA<Error>());
    });

    test('returns user for valid badge', () async {
      when(() => mockRepository.authenticate(any()))
          .thenAnswer((_) async => Result.ok(testUser));

      final result = await useCase('valid_badge');

      expect(result, isA<Ok>());
      expect(result.value.id, equals(testUser.id));
    });
  });
}
```

### Widget Tests

Тестируют один widget изолированно.

```dart
void main() {
  group('WearStatusBar Widget', () {
    testWidgets('shows wifi icon when connected', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: WearStatusBar(wifiAvailable: true, wifiLevel: 3),
        ),
      );

      expect(find.byIcon(Icons.wifi), findsOneWidget);
    });
  });
}
```

### Integration Tests

Тестируют_complete приложение или значимую часть.

```dart
// integration_test/app_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Wear flow', () {
    testWidgets('complete authentication flow', (tester) async {
      await tester.pumpWidget(const SmartGlassesApp());
      await tester.pumpAndSettle();

      // Tap on wear button
      await tester.tap(find.byKey(const ValueKey('wear_button')));
      await tester.pumpAndSettle();

      // Enter badge barcode
      await tester.enterText(find.byKey(const ValueKey('badge_input')), '123456');
      await tester.tap(find.byKey(const ValueKey('auth_button')));
      await tester.pumpAndSettle();

      // Verify menu screen
      expect(find.text('Меню'), findsOneWidget);
    });
  });
}
```

**Правила тестирования**:
- Использовать Fake/Mock repositories для unit тестов
- Тестировать business logic в domain layer
- Widget tests для UI компонентов
- Integration tests для critical user flows
- Стремиться к высокому code coverage

---

## Правила изменений

### Минимальный scope

- Менять только файлы, относящиеся к задаче
- Не переносить проект на другой state management без отдельного решения
- Если feature растет, сначала выделять понятные Cubit/state/widgets внутри текущей структуры

### Когда добавлять domain/data слои

Добавлять отдельные слои стоит если появляется хотя бы одно условие:

- Несколько источников данных
- Сложные правила обработки, требующие отдельного тестирования
- Один сценарий используется несколькими Cubits
- Требуется стабильный контракт результата
- Появляются persistency, network или repository abstractions

### Направление зависимостей

```
presentation -> domain -> data
```

Обратные импорты запрещены.

---

## Runtime-контуры

### Основное приложение (Phone)

```
main()
  -> DependenciesContainer.create()
  -> AppScope
  -> MyApp
  -> InitializationScreen
  -> HomeScreen
```

### Glasses runtime

```
glassesMain()
  -> GlassesRuntimeApp
  -> GlassesCoordinatorCubit
  -> MethodChannel handler
  -> Navigator
  -> Glasses screens
```

### Wear module (Isolated)

```
Phone HomeScreen
  -> Navigator.push(ProviderScope + MaterialApp.router)
  -> WearRouter
  -> WearProviders
```

---

## Communication Flow: Phone → Glasses

### Архитектурный принцип

**Очки - это "тупой" дисплей**. Они не содержат бизнес-логики, не принимают решений, не валидируют данные. Очки только:
- Отображают полученный payload
- Отправляют raw events обратно (нажатия кнопок, голосовые команды)

**Вся логика находится на телефоне**. Phone runtime:
- Формирует payload для очков
- Принимает events от очков
- Обрабатывает события и принимает решения
- Обновляет payload на очках

### Схема взаимодействия

```
┌─────────────────────────┐                      ┌─────────────────────────┐
│       PHONE RUNTIME     │                      │     GLASSES RUNTIME     │
│                         │                      │                         │
│  ┌─────────────────┐   │     MethodChannel    │   ┌─────────────────┐  │
│  │  Phone Cubit    │────┼────────────────────────▶│  WearGlassesCubit│  │
│  │  (логика +     │   │   showWearGlasses()   │   │  (просто storage)│  │
│  │   формирование  │   │   updateWearGlasses() │   └────────┬────────┘  │
│  │   payload)     │   │                      │            │            │
│  └─────────────────┘   │                      │   ┌────────▼────────┐  │
│         │              │                      │   │ WearGlassesScreen│  │
│         ▼              │                      │   │  (только UI,     │  │
│  ┌─────────────────┐   │                      │   │   Stateless)    │  │
│  │ WearGlassesBridge│──┼────────────────────────▶│                  │  │
│  │                 │   │                      │   └─────────────────┘  │
│  └─────────────────┘   │                      │                         │
│         │              │     Events ◀──────────│──────── raw events      │
│         ▼              │   onScan, onVoice     │   (без обработки)       │
│  ┌─────────────────┐   │                      │                         │
│  │MethodChannelSvc │───┼────────────────────────▶                         │
│  └─────────────────┘   │                      │                         │
└─────────────────────────┘                      └─────────────────────────┘
```

### Компоненты

#### 1. WearGlassesPayload (Phone side)

Модель данных для очков - единый контракт между телефоном и очками:

```dart
class WearGlassesPayload {
  final WearGlassesScreenType screenType;  // auth, menu, scan, status, etc.
  final WearGlassesPhase phase;            // idle, loading, scanning, success, error
  final String title;
  final String? subtitle;
  final String? statusText;
  final bool isLoading;
  final List<String> items;                  // для экранов со списками
  final int selectedIndex;
  // ... status icons, wifi, printer
}
```

**Factory методы** для типичных состояний:
```dart
WearGlassesPayload.authWaitingBarcode()
WearGlassesPayload.scanLoading()
WearGlassesPayload.menu(selectedIndex: 0)
WearGlassesPayload.status(isError: false, title: 'Успех')
```

#### 2. WearGlassesBridge (Phone side)

Обёртка над `MethodChannelService` для отправки на очки:

```dart
class WearGlassesBridge {
  Future<void> show(WearGlassesPayload payload) async {
    await _methodChannelService.showWearGlasses(payload.toJson());
  }

  Future<void> update(WearGlassesPayload payload) async {
    await _methodChannelService.updateWearGlasses(payload.toJson());
  }

  Future<void> hide() async {
    await _methodChannelService.hideWearGlasses();
  }
}
```

#### 3. GlassesCoordinatorCubit (Glasses side)

Принимает MethodChannel вызовы и маршрутизирует на соответствующие cubits:

```dart
Future<dynamic> _handleMethodCall(MethodCall call) async {
  switch (call.method) {
    case 'updateWearGlasses':
      _handleUpdateWearGlasses(call.arguments);  // -> WearGlassesCubit
      break;
    // другие методы...
  }
}
```

#### 4. WearGlassesCubit (Glasses side)

**Просто хранит состояние** - никакой логики:

```dart
class WearGlassesCubit extends Cubit<WearGlassesState> {
  void updateFromPayload(Map<String, dynamic> payload) {
    emit(WearGlassesState.fromPayload(payload));  // Просто сохраняет данные
  }
}
```

#### 5. WearGlassesScreen (Glasses side)

**Stateless презентационный компонент** - только рисует UI:

```dart
class WearGlassesScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return BlocBuilder<WearGlassesCubit, WearGlassesState>(
      builder: (context, state) {
        // Только отображение - никакой логики
        return WearGlassesScaffold(
          child: Column(
            children: [
              _TitleBlock(state: state),
              _Body(state: state),
              _StatusBar(state: state),
            ],
          ),
        );
      },
    );
  }
}
```

### Пример: Отображение меню на очках

**Phone side (в Cubit):**
```dart
void _onMenuEntered() {
  // 1. Phone формирует payload (вся логика здесь)
  final payload = WearGlassesPayload.menu(selectedIndex: _selectedIndex);
  
  // 2. Phone отправляет на очки
  wearGlassesBridge.show(payload);
}

void _onItemSelected(int index) {
  // 3. Phone обрабатывает событие
  _selectedIndex = index;
  
  // 4. Phone обновляет очки новым состоянием
  final payload = WearGlassesPayload.menu(selectedIndex: _selectedIndex);
  wearGlassesBridge.update(payload);
}
```

**Glasses side (только отображение):**
```dart
// Никакой логики, просто показывает что дали
class _WearList extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    // Отображает items из state, selectedIndex из state
    // Клик по item -> отправляет event обратно на phone
  }
}
```

### Правила

1. **Payload формируется на телефоне** - очки не знают о бизнес-логике
2. **Очки Stateless** - только отображение полученного состояния
3. **Events возвращаются как есть** - phone сам решает что делать
4. **Единый payload contract** - `WearGlassesPayload` определеяет все возможные состояния
5. **Никакой логики на очках** - только render и event forwarding

### MethodChannel контракт

| Метод | Направление | Payload |
|-------|------------|---------|
| `showWearGlasses` | Phone → Glasses | Полный payload экрана |
| `updateWearGlasses` | Phone → Glasses | Частичное обновление payload |
| `hideWearGlasses` | Phone → Glasses | Скрыть экран очков |
| `onGlassesEvent` | Glasses → Phone | `{event: 'scan', data: '...}` |

---

## Архитектурные инварианты

1. **`main()`** запускает phone runtime, **`glassesMain()`** запускает glasses runtime
2. **Phone UI** не управляет Navigator очков напрямую; связь через native bridge и coordinator
3. **`MethodChannelService`** - единственная точка Flutter-вызовов к native channels
4. **Глобальные Cubits** создаются в `DependenciesContainer` и передаются через `AppScope`
5. **Локальные Cubits** glasses runtime создаются и закрываются внутри `GlassesRuntimeApp`
6. **Voice recognition** работает offline через Vosk asset
7. **Scanner lifecycle** обязан добавлять и удалять delegate симметрично
8. **Любой новый route** должен быть согласован между Flutter и Android
9. **Dependency direction**: только presentation → domain → data
10. **Очки - stateless display**: WearGlassesScreen и WearGlassesCubit не содержат бизнес-логики, только отображение
11. **Вся логика на телефоне**: Phone формирует WearGlassesPayload и принимает решения
12. **Единый payload contract**: WearGlassesPayload - единственный способ передачи данных на очки

---

## Проверки

Перед завершением изменений:

```bash
flutter analyze
flutter test

# При использовании FVM:
fvm flutter analyze
fvm flutter test
```

Для Android/native bridge изменений обязательна runtime-проверка на устройстве.

---

## Рекомендации по улучшению

### Краткосрочные улучшения

1. **Замена print() на structured logging** - использовать `logging` или `dart:developer`
2. **Unified state management** - рассмотреть миграцию модуля Wear на BLoC для консистентности
3. **Error handling** - внедрить Result pattern в domain layer
4. **Repository pattern** - добавить абстракции там, где есть прямые вызовы data sources

### Долгосрочные улучшения

1. **Пакетная структура** - при росте выделить отдельные пакеты для shared code
2. **Golden tests** - добавить snapshot testing для UI компонентов
3. **Performance monitoring** - интегрировать metrics для анализа производительности
4. **Feature flags** - добавить систему для A/B тестирования и gradual rollouts

---

## Ссылки

- [Flutter App Architecture Guide](https://github.com/flutter/website/blob/main/sites/docs/src/content/app-architecture/index.md)
- [Flutter BLoC Library](https://bloclibrary.dev/)
- [Riverpod Documentation](https://riverpod.dev/)
- [GoRouter Documentation](https://gorouter.dev/)
- [Flutter Testing Overview](https://github.com/flutter/website/blob/main/sites/docs/src/content/testing/overview.md)
- [Clean Architecture in Flutter](https://blog.codemagic.io/clean-architecture-in-flutter/)
