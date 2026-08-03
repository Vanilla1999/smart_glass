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
      _subscriptions.add(runtime.updates.listen(_updates.add));
    }
  }

  final List<WearBackgroundRuntime> _runtimes;
  final StreamController<WearBackgroundScreenUpdate> _updates =
      StreamController<WearBackgroundScreenUpdate>.broadcast();
  final List<StreamSubscription<WearBackgroundScreenUpdate>> _subscriptions =
      <StreamSubscription<WearBackgroundScreenUpdate>>[];

  WearBackgroundRuntime? _for(WearScreenId screen) {
    for (final WearBackgroundRuntime runtime in _runtimes) {
      if (runtime.handles(screen)) return runtime;
    }
    return null;
  }

  @override
  Stream<WearBackgroundScreenUpdate> get updates => _updates.stream;

  @override
  bool handles(WearScreenId screen) => _for(screen) != null;

  @override
  bool supportsCommand(WearScreenId screen, WearVoiceCommand command) {
    return _for(screen)?.supportsCommand(screen, command) ?? false;
  }

  @override
  Future<void> enterScreen(WearScreenId screen, {Object? extra}) async {
    await _for(screen)?.enterScreen(screen, extra: extra);
  }

  @override
  Future<bool> handleCommand(
    WearScreenId screen,
    WearVoiceCommand command,
  ) async {
    return await _for(screen)?.handleCommand(screen, command) ?? false;
  }

  @override
  Future<bool> handlePhrase(WearScreenId screen, String phrase) async {
    return await _for(screen)?.handlePhrase(screen, phrase) ?? false;
  }

  @override
  Future<bool> handleDynamicItem(WearScreenId screen, String itemId) async {
    return await _for(screen)?.handleDynamicItem(screen, itemId) ?? false;
  }

  @override
  Future<bool> handleBarcode(WearScreenId screen, String barcode) async {
    return await _for(screen)?.handleBarcode(screen, barcode) ?? false;
  }

  @override
  VoiceDynamicItemsSnapshot dynamicVoiceItemsFor(WearScreenId screen) {
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
    for (final WearBackgroundRuntime runtime in _runtimes) {
      await runtime.reset();
    }
  }

  @override
  Future<void> dispose() async {
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
