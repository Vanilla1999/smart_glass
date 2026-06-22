## Goal
- Фикс двух багов: голосовые команды `вверх/вниз` не работают на меню после нажатия «Завершить»; задержка ~10 секунд перед распознаванием после авторизации
- Усиление громкости live PCM (3x gain) для Vosk-распознавания
- Голосовая заметка (VoiceMemo) — быстрый WAV-рекордер на HomeScreen

## Constraints & Preferences
- Минимальные targeted правки без реструктуризации
- Совместимость с существующим `WearFlowController`, `WearVoiceSession`, lifecycle модуля
- Vosk sample rate 16kHz, `AndroidAudioSource.mic`

## Progress

### Done
#### Wear: громкость
- `lib/modules/wear/domain/service/voice_typing/audio_stream_service.dart`:
  - Явно указан `audioSource: AndroidAudioSource.mic` (раньше полагался на default, который мог быть `voice_communication` с подавлением)
  - Добавлен `_boostPcm16()` — 3x gain на live PCM-сэмплы перед отдачей в Vosk и колбэки
  - Все подписчики получают усиленные `boostedBytes`
  - Статистика лога (`_pcmStats`) теперь считается по усиленным данным

#### Wear: warmup Vosk
- `lib/modules/wear/presentation/widgets/wear_module_app.dart:62`:
  - `WearDependencies.I.warmupVoiceTypingInBackground();` в `initState()` сразу после `super.initState()`
  - Модель Vosk начинает загружаться при старте `WearModuleApp`, а не при `WearVoiceSession.start()`, который вызывается только после прохождения авторизации

#### Wear: race condition после «Завершить»
- `lib/modules/wear/presentation/screens/continue_scan/wear_continue_scan_screen.dart:132`:
  - `_flow.enterScreen(WearScreenId.menu);` добавлен **до** `context.go(WearMenuScreen.route)`
  - `WearFlowController._state.screen` синхронно переключается на `menu`, поэтому `invokeScreenAction()` сразу начинает роутить `up/down/select` команды на обработчик меню

#### Main App: голосовая заметка (VoiceMemo)
- Новая feature: `lib/features/voice_memo/`
  - `.../presentation/cubit/voice_memo_cubit.dart` — `VoiceMemoCubit` (Cubit): запись WAV 44.1kHz, нормализация пика
  - `.../presentation/cubit/voice_memo_state.dart` — sealed-состояния: `VoiceMemoIdle`, `VoiceMemoRecording`, `VoiceMemoSaved`, `VoiceMemoError`
  - Сохраняет в `getExternalStorageDirectory()/VoiceMemos/voice_memo_<timestamp>.wav`
  - Нормализация peak → 0.98 множителем в `_normalizeWavFile()`
- `lib/app/di/dependencies_container.dart`: добавлен `VoiceMemoCubit` в контейнер
- `lib/features/home/presentation/screens/home_screen.dart`:
  - FAB-кнопка микрофона на HomeScreen
  - Состояния: idle (mic icon, secondaryContainer), recording (stop icon, red), saved (check icon, green)
  - SnackBar с именем файла / ошибкой

### Known Issues
- `flutter analyze`: 0 errors, ~255 pre-existing warnings/infos (те же, что и до изменений)
- `AudioStreamService._boostPcm16()` делает копию `Uint8List` на каждый чанк — дополнительный аллокации; для embedded-очков малозначимо
- VoiceMemo использует `path_provider` — тесты могут требовать Platform Channel mocking

## Key Decisions
- `3.0` gain выбран эмпирически; не вынесен в env, т.к. требуется быстрый фикс на устройстве
- `warmupVoiceTypingInBackground()` стартует перед `WearModuleApp._router` и авторизацией — если модель не готова к моменту `WearVoiceSession.start()`, повторный вызов будет no-op
- `enterScreen()` перед `context.go()` — дизайн `WearFlowController` требует синхронного обновления `_state.screen` для `invokeScreenAction()`, router transition GoRouter — асинхронный

## Relevant Files
- `lib/modules/wear/domain/service/voice_typing/audio_stream_service.dart` — 3x gain boost
- `lib/modules/wear/presentation/widgets/wear_module_app.dart` — warmup call
- `lib/modules/wear/presentation/screens/continue_scan/wear_continue_scan_screen.dart` — enterScreen fix
- `lib/features/voice_memo/presentation/cubit/voice_memo_cubit.dart` — VoiceMemoCubit
- `lib/features/voice_memo/presentation/cubit/voice_memo_state.dart` — sealed states
- `lib/app/di/dependencies_container.dart` — DI registration
- `lib/features/home/presentation/screens/home_screen.dart` — UI кнопка
