# Wear voice background navigation problem

## Purpose of this document

This document describes the current Flutter Wear module architecture, the voice-control pipeline, and a specific problem observed when the device screen/application is not active: voice commands `вверх` and `вниз` continue to work, but `выбрать` does not navigate to another screen.

The document is intended to be passed to another AI/reviewer for investigation and solution design.

---

## Project context

The project is a Flutter application with a dedicated `wear` module for smart glasses / wearable workflow.

Relevant stack:

- Flutter / Dart
- `go_router` for navigation inside the Wear module
- `flutter_riverpod` for command stream providers
- `record` for microphone audio stream
- `vosk_flutter_service` for offline Russian speech recognition
- Manual singleton DI through `WearDependencies`

The Wear module is located at:

```text
lib/modules/wear/
```

Architecture documentation already exists here:

```text
docs/wear_ARCHITECTURE.md
```

---

## Main Wear navigation flow

The Wear module has its own nested `MaterialApp.router` and `GoRouter`.

Important file:

```text
lib/modules/wear/presentation/widgets/wear_module_app.dart
```

The router is created in `_WearModuleAppState`:

```dart
late final GoRouter _router;

_router = GoRouter(
  initialLocation: WearRoute.initialRoute,
  routes: WearRoute.goRouteWear,
  observers: <NavigatorObserver>[
    _WearNavigatorObserver(),
  ],
);
```

The nested app is built as:

```dart
MaterialApp.router(
  routerConfig: _router,
  builder: (BuildContext context, Widget? child) {
    return WearVoiceCommandOrchestrator(
      onBack: _handleVoiceBack,
      onHome: _handleVoiceHome,
      child: child ?? const SizedBox.shrink(),
    );
  },
)
```

Routes are defined in:

```text
lib/modules/wear/navigation/wear_routes.dart
```

Important screens include:

- `WearMainScreen`
- `WearMenuScreen`
- `WearPrinterSelectScreen`
- `WearAvailabilityInteractionScreen`
- `WearHelpScreen`
- `WearSettingsScreen`
- many child flow screens

The menu screen route is:

```dart
class WearMenuScreen extends StatefulWidget {
  static const String route = '/wear_menu';
}
```

---

## Voice architecture

Voice services are initialized in:

```text
lib/modules/wear/config/wear_dependencies.dart
```

Relevant singleton dependencies:

```dart
audioStreamService = AudioStreamService();
speechRecognitionService = SpeechRecognitionService(
  audioStreamService: audioStreamService,
);
voiceTypingService = VoiceTypingService(
  speechRecognitionService: speechRecognitionService,
  audioStreamService: audioStreamService,
);
voiceControlService = WearVoiceControlService(
  speechRecognitionService: speechRecognitionService,
);
```

There is one shared audio stream and one shared Vosk recognizer for voice typing and voice commands.

---

## Voice command pipeline

The simplified pipeline is:

```text
microphone
  -> AudioStreamService
  -> SpeechRecognitionService / Vosk
  -> WearVoiceControlService
  -> VoiceCommandParserService
  -> wearVoiceCommandsProvider
  -> WearVoiceCommandListener / WearVoiceCommandOrchestrator
  -> screen callbacks / router navigation
```

### Audio stream

File:

```text
lib/modules/wear/domain/service/voice_typing/audio_stream_service.dart
```

This service starts microphone streaming using `record` and forwards PCM chunks to registered callbacks.

Foreground service configuration was added for Android so the stream can survive background/paused state.

Observed logs show that audio chunks continue to arrive even after lifecycle changes to `paused` / `hidden`.

Example observed logs:

```text
[AudioStreamService] startStream done
[SpeechRecognitionService] now listening ... callbacks=1
[AudioStreamService] chunk#1 bytes=2560 callbacks=1
[SpeechRecognitionService] processing chunk#1
[AudioStreamService] chunk#200 bytes=2560 callbacks=1
[SpeechRecognitionService] processing chunk#200
```

### Speech recognition

File:

```text
lib/modules/wear/domain/service/voice_typing/speech_recognition_service.dart
```

This service loads the Vosk model, processes audio chunks, and emits partial/final recognized text streams.

Expected diagnostic logs include:

```text
[VOSK][PARTIAL] ...
[VOSK][FINAL] ...
```

### Voice command control

File:

```text
lib/modules/wear/domain/service/voice_command/wear_voice_control_service.dart
```

The service subscribes to Vosk final and partial text streams:

```dart
_recognitionSubscription = _speechRecognitionService.resultsStream.listen(
  _onRecognitionResult,
);

_partialRecognitionSubscription =
    _speechRecognitionService.partialResultsStream.listen(
  _onPartialRecognitionResult,
);
```

It parses recognized Russian phrases into enum commands and emits them through:

```dart
Stream<WearVoiceCommand> get commandStream => _commandController.stream;
```

Commands are deduplicated with cooldowns. Current cooldowns:

```dart
WearVoiceCommand.select => 2500 ms
WearVoiceCommand.back => 2500 ms
WearVoiceCommand.home => 2500 ms
WearVoiceCommand.up => 900 ms
WearVoiceCommand.down => 900 ms
```

### Voice command enum

File:

```text
lib/modules/wear/domain/service/voice_command/wear_voice_command.dart
```

Commands:

```dart
enum WearVoiceCommand {
  up,
  down,
  select,
  back,
  home,
}
```

### Voice command parser

File:

```text
lib/modules/wear/domain/service/voice_command/voice_command_parser_service.dart
```

Current exact command map includes:

```dart
'вверх': WearVoiceCommand.up,
'верх': WearVoiceCommand.up,
'наверх': WearVoiceCommand.up,
'на верх': WearVoiceCommand.up,
'выше': WearVoiceCommand.up,

'вниз': WearVoiceCommand.down,
'низ': WearVoiceCommand.down,
'в низ': WearVoiceCommand.down,
'ниже': WearVoiceCommand.down,

'выбрать': WearVoiceCommand.select,
'выбери': WearVoiceCommand.select,
'выбор': WearVoiceCommand.select,
'ок': WearVoiceCommand.select,
'окей': WearVoiceCommand.select,
'да': WearVoiceCommand.select,

'назад': WearVoiceCommand.back,
'выход': WearVoiceCommand.home,
'домой': WearVoiceCommand.home,
'дом': WearVoiceCommand.home,
```

---

## Voice listeners in UI

File:

```text
lib/modules/wear/presentation/widgets/wear_voice_command_listener.dart
```

There are two listener widgets.

### Global orchestrator

`WearVoiceCommandOrchestrator` handles only global commands:

- `back`
- `home`

It intentionally ignores:

- `up`
- `down`
- `select`

Code shape:

```dart
switch (cmd) {
  case WearVoiceCommand.back:
    onBack();
    break;
  case WearVoiceCommand.home:
    onHome();
    break;
  case WearVoiceCommand.up:
  case WearVoiceCommand.down:
  case WearVoiceCommand.select:
    break;
}
```

### Screen-level listener

`WearVoiceCommandListener` handles screen-local commands:

- `up`
- `down`
- `select`

It calls callbacks provided by each screen:

```dart
WearVoiceCommandListener(
  onUp: _onVoiceUp,
  onDown: _onVoiceDown,
  onSelect: _onVoiceSelect,
  child: ...,
)
```

It ignores events when its `ModalRoute` is not current:

```dart
final ModalRoute<dynamic>? route = ModalRoute.of(context);
if (route != null && !route.isCurrent) {
  return;
}
```

---

## Menu screen command handling

Important file:

```text
lib/modules/wear/presentation/screens/menu/wear_menu_screen.dart
```

This is the most important screen for the current problem.

It contains:

```dart
int _focusedIndex = 0;
static const int _menuItemCount = 4;
```

Menu items:

```text
0 = Печать ценника
1 = Доступность
2 = Справка
3 = Настройки
```

### Up/down behavior

`_onVoiceUp()` and `_onVoiceDown()` only modify local focused index, animate scroll, and send payload to glasses.

Simplified:

```dart
_focusedIndex = _focusedIndex - 1; // or +1
_scroll.animateTo(...);
WearStatusIconReporter.I.sendFast(
  WearGlassesPayload.menu(selectedIndex: _focusedIndex),
);
```

This does not require `Navigator` or route transition.

### Select behavior

`_onVoiceSelect()` performs navigation using `context.push(route)`.

Simplified:

```dart
void _onVoiceSelect() {
  if (_focusedIndex == 0) {
    _pushAndRefreshMenu(WearPrinterSelectScreen.route);
  } else if (_focusedIndex == 1) {
    _pushAndRefreshMenu(WearAvailabilityInteractionScreen.route);
  } else if (_focusedIndex == 2) {
    _pushAndRefreshMenu(WearHelpScreen.route);
  } else if (_focusedIndex == 3) {
    _pushAndRefreshMenu(WearSettingsScreen.route);
  }
}
```

Navigation helper:

```dart
Future<void> _pushAndRefreshMenu(String route) async {
  await context.push(route);
  if (!mounted) return;
  _sendMenuPayload();
}
```

This is the key suspected weak point: `select` depends on a screen `BuildContext` and Flutter navigation being active.

---

## Lifecycle behavior

Important file:

```text
lib/modules/wear/presentation/widgets/wear_module_app.dart
```

The app observes lifecycle changes:

```dart
void didChangeAppLifecycleState(AppLifecycleState state) {
  print('[WearModuleApp] lifecycle state=$state');
  if (state == AppLifecycleState.detached) {
    WearVoiceSession.I.stop();
    return;
  }
  if (state == AppLifecycleState.resumed) {
    WearVoiceSession.I.restart(reason: 'app_lifecycle_resumed');
    return;
  }
  WearVoiceSession.I.diagnostics().then(...);
}
```

When app returns to `resumed`, voice listening is restarted.

When app goes to `paused` or `hidden`, current code does not stop voice listening; it only prints diagnostics.

Observed behavior after foreground service changes:

- audio chunks continue in background / when screen is off;
- `вверх` and `вниз` still affect glasses/menu state;
- `выбрать` is recognized or at least expected to be recognized, but no visible route transition happens.

---

## Observed problem

When the device/application is active, voice commands are expected to work normally.

When the device screen is off / app is not foreground-active:

- `вниз` works;
- `вверх` works;
- `выбрать` does not navigate to another screen.

The practical user-visible result:

```text
Voice can move menu selection up/down on glasses, but cannot open selected item.
```

---

## Current hypothesis

`вверх` and `вниз` work because they are mostly headless/local actions:

```text
voice command -> local _focusedIndex -> glasses payload
```

They do not need a Flutter route transition.

`выбрать` fails because it requires active UI navigation:

```text
voice command -> screen callback -> context.push(route)
```

When app lifecycle is `paused` / `hidden` / screen off, `context.push()` may be ineffective, delayed, ignored, or impossible to reflect visually.

Another possible issue is that the screen-level `WearVoiceCommandListener` depends on widget lifecycle and `ModalRoute.of(context).isCurrent`. When the app is not active, the widget tree may not be in a reliable state for navigation operations.

---

## Important diagnostic logs to collect

For the command `выбрать`, collect these logs:

```text
[WearVoiceControlService] emitting ... WearVoiceCommand.select
[WearVoiceCommandListener] calling onSelect
[MenuScreen] ========== _onVoiceSelect START ==========
[MenuScreen] NAVIGATING TO: ...
[STACK-DEBUG] didPush: route=...
[WearModuleApp] lifecycle state=...
```

Interpretation:

### If there is no `emitting ... select`

The ASR/parser did not produce the select command.

Possible fix:

- improve parser variants for `select`;
- inspect Vosk partial/final text;
- add more synonyms such as `открыть`, `далее`, `подтвердить`, `выберай`, etc.

### If there is `emitting ... select`, but no `calling onSelect`

The command stream reaches the provider but the screen listener is not handling it.

Possible causes:

- current route check rejects it;
- listener widget is not mounted/current;
- provider/listener lifecycle issue.

### If there is `calling onSelect` and `NAVIGATING TO`, but no `didPush`

The screen callback runs, but `context.push(route)` does not complete or does not trigger navigation.

This supports the main hypothesis: UI navigation from screen context is not reliable while app/screen is inactive.

### If `didPush` appears but glasses do not change

Navigation happened, but glasses payload/state was not updated for the new screen.

Then the problem is not router navigation but external display/status payload synchronization.

---

## Potential solution directions

### Option A: Defer navigation until resumed

If `select` is received while lifecycle is not `resumed`, store the target route as pending.

When app returns to `resumed`, execute:

```dart
_router.push(pendingRoute);
```

Pros:

- simple;
- safe for Flutter UI;
- keeps navigation in `WearModuleApp`, where `_router` exists.

Cons:

- screen will not change immediately while the screen is off;
- glasses may need a separate payload update if user expects immediate external-display change.

### Option B: Move select/navigation to a central command router

Instead of performing `context.push()` in each screen, centralize command handling in `WearModuleApp` or a navigation service.

The central service would know:

- current logical Wear screen;
- current focused item;
- selected route/action;
- app lifecycle state;
- pending route if inactive.

Pros:

- avoids fragile screen `BuildContext` navigation;
- easier to handle background/lifecycle behavior;
- better for voice-first architecture.

Cons:

- requires refactoring command handling out of individual screens.

### Option C: Separate glasses/headless state from Flutter Navigator

If the expected behavior is that smart glasses UI changes even when the phone screen is off, then Flutter `Navigator` should not be the source of truth for the glasses UI.

Instead:

```text
voice command
  -> headless Wear state machine
  -> send glasses payload immediately
  -> Flutter Navigator catches up when app resumes
```

Pros:

- best for true background/headless smart-glasses UX;
- up/down/select all work consistently as logical commands;
- does not depend on active Flutter rendering.

Cons:

- larger architecture change;
- requires modeling logical screens/actions outside widgets.

### Option D: Wake/resume UI before navigation

Try to bring app/device to active state before route transition.

Pros:

- could preserve current screen-based architecture.

Cons:

- platform-specific;
- may require Android foreground activity / wake lock / notification action;
- may be restricted by Android background activity launch policies.

---

## Key files for investigation

```text
lib/modules/wear/presentation/widgets/wear_module_app.dart
lib/modules/wear/presentation/widgets/wear_voice_command_listener.dart
lib/modules/wear/presentation/screens/menu/wear_menu_screen.dart
lib/modules/wear/navigation/wear_routes.dart
lib/modules/wear/domain/service/voice_command/wear_voice_control_service.dart
lib/modules/wear/domain/service/voice_command/voice_command_parser_service.dart
lib/modules/wear/domain/service/voice_typing/audio_stream_service.dart
lib/modules/wear/domain/service/voice_typing/speech_recognition_service.dart
lib/modules/wear/config/wear_dependencies.dart
```

---

## Short problem statement

The Wear module uses Vosk voice recognition and screen-level `WearVoiceCommandListener` widgets. In background/screen-off mode, voice recognition and simple commands continue working. Menu movement commands `up/down` work because they update local focus and send glasses payloads. The `select` command does not open the chosen screen because it depends on `context.push(route)` from the current screen widget. This is likely unreliable or ineffective when the Flutter app lifecycle is not `resumed`.

The likely fix is to stop treating Flutter route navigation as the only command effect during background mode. Either defer route navigation until `resumed`, or introduce a central/headless Wear state machine that handles `select` logically and updates the glasses independently from Flutter Navigator.
