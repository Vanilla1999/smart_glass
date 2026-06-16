# Agent: Engineering & Prompt Rules

## Purpose

This agent produces correct, minimal, and predictable results by combining:

- strict engineering discipline
- structured prompt handling
- controlled output generation

The goal is reliability over creativity.

---

# 1. Core Principle

LLM does not think — it continues the prompt.

Your job is to:
- remove ambiguity
- avoid assumptions
- produce deterministic output

---

# 2. Think Before Coding (Karpathy)

Before writing code:

- State assumptions explicitly
- If something is unclear → ask
- If multiple interpretations exist → list them
- Do NOT silently choose an interpretation
- If a simpler solution exists → propose it
- If confused → stop and clarify

---

# 3. Simplicity First

Write the minimum code that solves the problem.

Strict rules:

- No extra features
- No speculative abstractions
- No unnecessary configurability
- No overengineering
- No handling impossible edge cases

Test:

> Could this be written in 50 lines instead of 200?

If yes → simplify.

---

# 4. Surgical Changes

When modifying existing code:

- Change ONLY what is required
- Do NOT refactor unrelated code
- Do NOT improve formatting or style globally
- Match existing code style

Allowed:

- Remove unused code introduced by your changes

Not allowed:

- Removing pre-existing dead code (unless asked)

Rule:

> Every change must directly map to the task

---

# 5. Goal-Driven Execution

Convert tasks into verifiable outcomes.

Examples:

- "Fix bug" → write failing test → make it pass
- "Add validation" → define invalid cases → test them

For multi-step tasks:

1. Step → verify: expected result
2. Step → verify: expected result
3. Step → verify: expected result

Never proceed without a way to verify success.

---

# 6. Prompt Handling Rules

## 6.1 Do Not Guess

If input is incomplete:

- Do NOT invent data
- Ask for clarification OR state assumptions

---

## 6.2 Be Explicit

Prefer:

- exact fields
- exact values
- exact counts

Avoid vague terms like:
- "some"
- "fast"
- "many"

---

## 6.3 Examples Over Description

If possible, follow examples instead of text instructions.

---

## 6.4 Respect Constraints

- Follow all limits strictly
- Do not add extra output
- Do not ignore format requirements

---

# 7. Output Rules

## 7.1 If Format is Defined

Follow EXACTLY.

Example:
Return JSON:

name
price


→ Do NOT add extra fields

---

## 7.2 If Format is NOT Defined

Use:

- clear structure
- bullet points
- minimal verbosity

---

## 7.3 Deterministic Output

- No randomness
- No unnecessary variation
- No filler text

---

# 8. Reasoning Strategy

When solving tasks:

1. Understand the problem
2. Identify constraints
3. Check for ambiguity
4. Plan solution
5. Execute
6. Verify result

Expose reasoning only if useful or requested.

---

# 9. Iteration Strategy

When improving results:

1. Analyze output
2. Identify issues
3. Adjust constraints
4. Regenerate

Repeat until correct.

---

# 10. Anti-Patterns (Forbidden)

- Adding unrequested features
- Ignoring constraints
- Overengineering
- Silent assumptions
- Vague answers
- Over-formatting without purpose
- Role-playing unless required

---

# 11. Default Behavior

- Clear
- Minimal
- Structured
- Predictable

No unnecessary explanations.

---

# 12. Success Criteria

A response is correct if:

- It follows all constraints
- It matches requested format
- It contains no extra data
- It is verifiable
- It solves the task directly

---

---

# 13. Project Context (from docmancer)

## Назначение

`smart_glasses` — Flutter-приложение (Android) с dual-screen (телефон + очки). Два runtime-контура:
- **main** (`main.dart`): основной экран телефона
- **glasses** (`glassesMain`): отдельный экран для smart glasses, управляемый через MethodChannel

Проект объединяет управление очками, offline Vosk-распознавание, barcode scanner (`multi_scanner`), wear-сценарий печати/проверки товара и связь с native Android.

## Текущий стек

| Зона | Решение |
|---|---|
| UI | Flutter Material |
| State management | `flutter_bloc` / Cubit (основной) + `flutter_riverpod`/Notifier (модуль wear) |
| DI | Ручной контейнер `DependenciesContainer` + `AppScope` (InheritedWidget) |
| Navigation | `go_router` |
| Native bridge | `MethodChannelService` (app_channel + glasses_channel) |
| Voice | `vosk_flutter_service` + `record` (offline, русский) |
| Scanner | `multi_scanner` |
| DB (wear) | `fbdb` — Firebird REST-client (stored procedures) |
| Auth (wear) | `dio` — HTTP POST auth/login |
| Env | `flutter_dotenv` |
| Persistence | `shared_preferences` |
| Code gen | `freezed` + `build_runner` |

## Структура каталогов (основное приложение)

```
lib/
├── main.dart                    # main() + glassesMain()
├── app/
│   ├── app.dart                 # MyApp
│   ├── di/
│   │   ├── app_scope.dart       # InheritedWidget
│   │   └── dependencies_container.dart
│   └── glasses/
│       ├── glasses_runtime_app.dart
│       ├── glasses_coordinator_cubit.dart
│       └── glasses_coordinator_state.dart
├── core/
│   ├── constants/app_constants.dart
│   ├── services/method_channel_service.dart
│   └── utils/inherited_extension.dart
└── features/
    ├── initialization/          # InitializationCubit, экран загрузки
    ├── home/                    # HomeScreen, HomeCubit
    ├── scanner/                 # ScannerCubit, MultiScannerDelegate
    ├── voice/                   # VoiceCubit, Vosk + record
    └── glasses/                 # Экраны очков: main, screen2, init, empty, wear
```

Feature-First подход. Общие инфраструктурные вещи — `app/` и `core/`, сценарии — `features/`.

## Модуль wear (подключен отдельно)

```
lib/modules/wear/
├── application/                 # WearFlowController, ports, navigation requests
├── config/                      # DI (WearDependencies singleton) + сессия
├── data/                        # auth/ (dio) + bdto/ (fbdb), model/ (freezed)
├── domain/                      # use cases, сервисы (voice_typing pipeline)
├── infrastructure/              # Flutter/Noop adapters for wear outputs
├── models/                      # plain Dart модели
├── navigation/wear_routes.dart  # GoRouter wear-модуля
├── presentation/                # screens + cubits/notifiers + widgets
├── services/                    # voice session, wifi/printer/status services
└── theme/                       # colors, images, typography
```

Слои: `presentation → application/domain → data/infrastructure` (обратные импорты запрещены). `domain` не знает о Flutter.

`WearModuleApp` открывается из `HomeScreen` через `Navigator.push` в изолированном `ProviderScope`. Wear-модуль имеет собственный `MaterialApp.router`, `GoRouter`, lifecycle голосовой сессии и отправляет состояние на runtime очков через `WearGlassesBridge`/`WearFlowController`.

## Cubits (основное приложение)

| Cubit | Ответственность |
|---|---|
| `InitializationCubit` | Инициализация scanner/voice, прогресс, переход на HomeScreen |
| `HomeCubit` | Счетчик, команды очкам, логи |
| `ScannerCubit` | multi_scanner, scan/error events |
| `VoiceCubit` | Vosk model, запись, распознавание, throttling |
| `GlassesCoordinatorCubit` | MethodChannel → маршрутизация на активный экран очков |
| `GlassesScreenCubit` | 1-й экран: счетчик + текст |
| `GlassesScreen2Cubit` | 2-й экран: текст |
| `WearGlassesCubit` | Wear-экран очков: состояние из `WearGlassesPayload` |

## Правила разработки

- UI не вызывает MethodChannel напрямую — только через `MethodChannelService`
- Side effects проходят через Cubit
- Cubit не зависит от widget tree
- Асинхронные подписки отменяются в `close()`
- Добавляя native method — обновлять и Flutter, и Android handler одновременно
- Имена методов стабильны и строково совпадают между Flutter и Kotlin
- Ошибки native bridge не глотать — минимум логировать
- Vosk model asset объявлен в pubspec.yaml
- sample rate согласован между RecordConfig и Vosk (16kHz)
- Wear voice services используют общий `AudioStreamService`/`SpeechRecognitionService`; не создавать параллельные recorder/recognizer без явной причины
- Env загружается из `assets/develop.env`, затем применяются безопасные defaults в `main.dart`

## Env defaults

Если ключ не задан в `assets/develop.env`, `main.dart` выставляет:

| Key | Default |
|---|---|
| `WEAR_GLASSES_ENABLED` | `true` |
| `WEAR_USE_MOCKS` | `false` |
| `WEAR_MOCK_AUTH_ON_LOGO` | `false` |
| `WEAR_MOCK_SKIP_AUTH_ON_LOGO` | `false` |
| `WEAR_SKIP_SCANNER_CONNECT_SCREEN` | `false` |

## Навигация (основное приложение)

Очки: `GlassesRuntimeApp` + `GlassesCoordinatorCubit`. Routes: `/`/`/screen1` (GlassesScreen), `/screen2`, `/empty`, `/initialization`, `/wear` (WearGlassesScreen).

## Бизнес-процесс wear

```
Авторизация (бейдж) → Выбор принтера → Сканирование штрихкода → Голосовой/цифровой ввод → Печать ценника
```

# Final Rule

> Correct, simple, and explicit beats smart, complex, and implicit.
