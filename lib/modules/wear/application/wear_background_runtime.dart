import 'dart:async';

import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/voice_utterance_coordinator.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/wear_voice_command.dart';
import 'package:smart_glasses/modules/wear/presentation/glasses/wear_glasses_payload.dart';

class WearBackgroundScreenUpdate {
  const WearBackgroundScreenUpdate({
    required this.screen,
    required this.payload,
  });

  final WearScreenId screen;
  final WearGlassesPayload payload;
}

abstract interface class WearBackgroundRuntime {
  Stream<WearBackgroundScreenUpdate> get updates;

  bool handles(WearScreenId screen);

  bool acceptsBarcode(WearScreenId screen);

  bool supportsCommand(WearScreenId screen, WearVoiceCommand command);

  Future<void> enterScreen(WearScreenId screen, {Object? extra});

  Future<bool> handleCommand(
    WearScreenId screen,
    WearVoiceCommand command,
  );

  Future<bool> handlePhrase(WearScreenId screen, String phrase);

  Future<bool> handleDynamicItem(WearScreenId screen, String itemId);

  Future<bool> handleBarcode(WearScreenId screen, String barcode);

  VoiceDynamicItemsSnapshot dynamicVoiceItemsFor(WearScreenId screen);

  void restorePresentationState(WearScreenId screen, Object state);

  Object? presentationStateFor(WearScreenId screen);

  Future<void> reset();

  Future<void> dispose();
}

class CompositeWearBackgroundRuntime implements WearBackgroundRuntime {
  CompositeWearBackgroundRuntime(this._runtimes) {
    for (final WearBackgroundRuntime runtime in _runtimes) {
      _subscriptions.add(runtime.updates.listen(_forwardUpdate));
    }
  }

  static const Set<WearVoiceCommand> _runtimeOwnedCommands =
      <WearVoiceCommand>{
    WearVoiceCommand.up,
    WearVoiceCommand.down,
    WearVoiceCommand.select,
    WearVoiceCommand.yes,
    WearVoiceCommand.no,
    WearVoiceCommand.print,
    WearVoiceCommand.takePhoto,
    WearVoiceCommand.backToList,
    WearVoiceCommand.clear,
    WearVoiceCommand.finish,
    WearVoiceCommand.nextPage,
    WearVoiceCommand.previousPage,
  };

  final List<WearBackgroundRuntime> _runtimes;
  final StreamController<WearBackgroundScreenUpdate> _updates =
      StreamController<WearBackgroundScreenUpdate>.broadcast();
  final List<StreamSubscription<WearBackgroundScreenUpdate>> _subscriptions =
      <StreamSubscription<WearBackgroundScreenUpdate>>[];
  final Map<WearScreenId, WearBackgroundScreenUpdate> _lastUpdates =
      <WearScreenId, WearBackgroundScreenUpdate>{};

  Future<void> _entryOperation = Future<void>.value();
  WearScreenId? _readyScreen;
  int _entryGeneration = 0;

  WearBackgroundRuntime? _for(WearScreenId screen) {
    for (final WearBackgroundRuntime runtime in _runtimes) {
      if (runtime.handles(screen)) return runtime;
    }
    return null;
  }

  void _forwardUpdate(WearBackgroundScreenUpdate update) {
    _lastUpdates[update.screen] = update;
    if (!_updates.isClosed) _updates.add(update);
  }

  bool _isReadyFor(WearScreenId screen) => _readyScreen == screen;

  Future<bool> _waitUntilReady(WearScreenId screen) async {
    while (true) {
      if (_isReadyFor(screen)) return true;
      final Future<void> operation = _entryOperation;
      try {
        await operation;
      } catch (_) {
        return false;
      }
      if (!identical(operation, _entryOperation)) continue;
      return _isReadyFor(screen);
    }
  }

  @override
  Stream<WearBackgroundScreenUpdate> get updates => _updates.stream;

  @override
  bool handles(WearScreenId screen) => _for(screen) != null;

  @override
  bool acceptsBarcode(WearScreenId screen) {
    if (!_isReadyFor(screen)) return false;
    return _for(screen)?.acceptsBarcode(screen) ?? false;
  }

  @override
  bool supportsCommand(WearScreenId screen, WearVoiceCommand command) {
    if (!_isReadyFor(screen)) return false;
    return _for(screen)?.supportsCommand(screen, command) ?? false;
  }

  @override
  Future<void> enterScreen(WearScreenId screen, {Object? extra}) async {
    final int generation = ++_entryGeneration;
    final WearBackgroundRuntime? runtime = _for(screen);
    if (runtime == null) {
      // Non-runtime overlays (for example voice clarification) must supersede
      // an older pending entry without discarding the last ready source state.
      _entryOperation = Future<void>.value();
      return;
    }

    _readyScreen = null;
    final Future<void> operation = _enterRuntime(
      runtime,
      screen,
      extra: extra,
      generation: generation,
    );
    _entryOperation = operation;
    await operation;
  }

  Future<void> _enterRuntime(
    WearBackgroundRuntime runtime,
    WearScreenId screen, {
    required Object? extra,
    required int generation,
  }) async {
    await runtime.enterScreen(screen, extra: extra);
    if (generation != _entryGeneration) return;

    _readyScreen = screen;
    final WearBackgroundScreenUpdate? lastUpdate = _lastUpdates[screen];
    if (lastUpdate != null && !_updates.isClosed) {
      // Child streams are asynchronous. If their final update was delivered
      // before enterScreen completed, resend it after readiness changes so
      // scanner admission and voice grammar are recomputed from ready state.
      _updates.add(lastUpdate);
    }
  }

  @override
  Future<bool> handleCommand(
    WearScreenId screen,
    WearVoiceCommand command,
  ) async {
    final WearBackgroundRuntime? runtime = _for(screen);
    if (runtime == null || !_runtimeOwnedCommands.contains(command)) {
      return false;
    }
    if (!await _waitUntilReady(screen)) return false;
    return runtime.handleCommand(screen, command);
  }

  @override
  Future<bool> handlePhrase(WearScreenId screen, String phrase) async {
    final WearBackgroundRuntime? runtime = _for(screen);
    if (runtime == null || !await _waitUntilReady(screen)) return false;
    return runtime.handlePhrase(screen, phrase);
  }

  @override
  Future<bool> handleDynamicItem(WearScreenId screen, String itemId) async {
    final WearBackgroundRuntime? runtime = _for(screen);
    if (runtime == null || !await _waitUntilReady(screen)) return false;
    return runtime.handleDynamicItem(screen, itemId);
  }

  @override
  Future<bool> handleBarcode(WearScreenId screen, String barcode) async {
    final WearBackgroundRuntime? runtime = _for(screen);
    if (runtime == null || !await _waitUntilReady(screen)) return false;
    if (!runtime.acceptsBarcode(screen)) return false;
    return runtime.handleBarcode(screen, barcode);
  }

  @override
  VoiceDynamicItemsSnapshot dynamicVoiceItemsFor(WearScreenId screen) {
    if (!_isReadyFor(screen)) return VoiceDynamicItemsSnapshot.empty;
    return _for(screen)?.dynamicVoiceItemsFor(screen) ??
        VoiceDynamicItemsSnapshot.empty;
  }

  @override
  void restorePresentationState(WearScreenId screen, Object state) {
    _for(screen)?.restorePresentationState(screen, state);
  }

  @override
  Object? presentationStateFor(WearScreenId screen) {
    return _for(screen)?.presentationStateFor(screen);
  }

  @override
  Future<void> reset() async {
    _entryGeneration += 1;
    _readyScreen = null;
    _lastUpdates.clear();
    final Future<void> operation = _resetRuntimes();
    _entryOperation = operation;
    await operation;
  }

  Future<void> _resetRuntimes() async {
    for (final WearBackgroundRuntime runtime in _runtimes) {
      await runtime.reset();
    }
  }

  @override
  Future<void> dispose() async {
    _entryGeneration += 1;
    _readyScreen = null;
    _lastUpdates.clear();
    _entryOperation = Future<void>.value();
    for (final StreamSubscription<WearBackgroundScreenUpdate> subscription
        in _subscriptions) {
      await subscription.cancel();
    }
    for (final WearBackgroundRuntime runtime in _runtimes) {
      await runtime.dispose();
    }
    await _updates.close();
  }
}
