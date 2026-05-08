# Smart Glasses
FLUTTER 3.41.6 !

Flutter-приложение для Android с dual-screen (телефон + очки).

## Архитектура

Feature-First + Cubit (BLoC)

```
lib/
├── app/           # DI, приложение, glasses runtime
├── core/          # Константы, services
└── features/      # home, glasses, initialization, scanner, voice
```

## Реализовано

- Home Screen с управлением и отображением
- Offline voice recognition (Vosk)
- Barcode scanner (multi_scanner)
- 2 экрана для очков с анимацией
- MethodChannel связь Main ↔ Glasses

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
