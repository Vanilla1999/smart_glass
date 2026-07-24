import 'dart:async';

import 'package:smart_glasses/modules/wear/config/wear_dependencies.dart';
import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';

class WearVoiceSession {
  WearVoiceSession._();

  static final WearVoiceSession I = WearVoiceSession._();
  bool _shouldListen = false;
  bool _captureSilenced = false;
  int _listeningGeneration = 0;
  Future<void> _operation = Future<void>.value();
  Future<void> _startupOperation = Future<void>.value();
  Future<void>? _restartOperation;
  final StreamController<bool> _reconnectingController =
      StreamController<bool>.broadcast();
  final StreamController<String?> _reconnectErrorController =
      StreamController<String?>.broadcast();
  int _pendingReconnects = 0;
  final VoiceCaptureRecoveryGate _zeroAudioRecovery =
      VoiceCaptureRecoveryGate();

  bool get isListening =>
      WearDependencies.I.speechRecognitionService.isListening;

  Stream<bool> get reconnectingStream => _reconnectingController.stream;
  Stream<String?> get reconnectErrorStream => _reconnectErrorController.stream;

  Future<String> diagnostics() {
    return WearDependencies.I.speechRecognitionService.diagnostics();
  }

  void setCaptureSilenced(bool silenced) {
    _captureSilenced = silenced;
  }

  Future<void> configureForScreen(WearScreenId screen) async {
    final bool freeText = _usesFreeTextRecognition(screen);
    print(
      '[WearVoiceSession] configureForScreen screen=$screen '
      'mode=${freeText ? 'freeText' : 'grammar'}',
    );
    await WearDependencies.I.speechRecognitionService
        .setFreeTextEnabled(freeText);
  }

  Future<void> start() async {
    _shouldListen = true;
    final int generation = ++_listeningGeneration;
    final Future<void> startup = _enqueue(() async {
      print('[WearVoiceSession] start requested, isListening=$isListening');
      if (!_isCurrentListeningRequest(generation)) return;
      if (isListening) {
        print('[WearVoiceSession] start skipped: ${await diagnostics()}');
        return;
      }
      try {
        _zeroAudioRecovery.reset();
        await WearDependencies.I.ensureVoiceTypingPrepared();
        if (!_isCurrentListeningRequest(generation)) return;
        final int captureStartedAtMillis =
            DateTime.now().millisecondsSinceEpoch;
        await WearDependencies.I.speechRecognitionService.startListening();
        if (!_isCurrentListeningRequest(generation)) {
          await WearDependencies.I.speechRecognitionService.stopListening();
          return;
        }
        await _waitForCaptureReady(
          generation: generation,
          captureStartedAtMillis: captureStartedAtMillis,
        );
        print('[WearVoiceSession] started: ${await diagnostics()}');
      } catch (error, stackTrace) {
        await WearDependencies.I.speechRecognitionService.stopListening();
        print('[WearVoiceSession] start failed: $error\n$stackTrace');
        rethrow;
      }
    });
    _startupOperation = startup;
    return startup;
  }

  Future<void> waitForStartup() => _startupOperation;

  Future<void> stop() async {
    _shouldListen = false;
    _captureSilenced = false;
    _zeroAudioRecovery.reset();
    _listeningGeneration++;
    return _enqueue(() async {
      print('[WearVoiceSession] stop requested, isListening=$isListening');
      try {
        await WearDependencies.I.speechRecognitionService.stopListening();
        print('[WearVoiceSession] stopped: ${await diagnostics()}');
      } catch (error, stackTrace) {
        print('[WearVoiceSession] stop failed: $error\n$stackTrace');
      }
    });
  }

  Future<void> restart({required String reason}) async {
    final Future<void>? pendingRestart = _restartOperation;
    if (pendingRestart != null) {
      print('[WearVoiceSession] restart joined reason=$reason');
      return pendingRestart;
    }
    _shouldListen = true;
    final int generation = ++_listeningGeneration;
    _setReconnectError(null);
    _setReconnecting(true);
    late final Future<void> restartOperation;
    try {
      restartOperation = _enqueue(() async {
        print('[WearVoiceSession] restart requested reason=$reason');
        if (!_isCurrentListeningRequest(generation)) return;
        try {
          _zeroAudioRecovery.reset();
          await WearDependencies.I.ensureVoiceTypingPrepared();
          if (!_isCurrentListeningRequest(generation)) return;
          final int captureStartedAtMillis =
              DateTime.now().millisecondsSinceEpoch;
          await WearDependencies.I.speechRecognitionService
              .restartListening(reason: reason);
          if (!_isCurrentListeningRequest(generation)) {
            await WearDependencies.I.speechRecognitionService.stopListening();
            return;
          }
          await _waitForCaptureReady(
            generation: generation,
            captureStartedAtMillis: captureStartedAtMillis,
          );
          print('[WearVoiceSession] restarted: ${await diagnostics()}');
        } catch (error, stackTrace) {
          print('[WearVoiceSession] restart failed: $error\n$stackTrace');
          _zeroAudioRecovery.reset();
          _setReconnectError('Голосовое управление недоступно');
        }
      });
      _restartOperation = restartOperation;
      await restartOperation;
    } finally {
      if (identical(_restartOperation, restartOperation)) {
        _restartOperation = null;
      }
      _setReconnecting(false);
    }
  }

  void _setReconnecting(bool reconnecting) {
    if (reconnecting) {
      _pendingReconnects++;
      if (_pendingReconnects == 1) {
        _reconnectingController.add(true);
      }
      return;
    }
    if (_pendingReconnects == 0) return;
    _pendingReconnects--;
    if (_pendingReconnects == 0) {
      _reconnectingController.add(false);
    }
  }

  void _setReconnectError(String? message) {
    _reconnectErrorController.add(message);
  }

  bool _isCurrentListeningRequest(int generation) {
    return _shouldListen && generation == _listeningGeneration;
  }

  Future<void> _waitForCaptureReady({
    required int generation,
    required int captureStartedAtMillis,
  }) async {
    final VoiceCaptureStartupGate gate = VoiceCaptureStartupGate();
    final service = WearDependencies.I.speechRecognitionService;

    while (_isCurrentListeningRequest(generation)) {
      final int now = DateTime.now().millisecondsSinceEpoch;
      final int? lastNonSilentAt = service.lastNonSilentAudioChunkAtMillis;
      if (gate.isReady(
        captureStartedAtMillis: captureStartedAtMillis,
        lastNonSilentAudioAtMillis: lastNonSilentAt,
        nowMillis: now,
      )) {
        print(
          '[WearVoiceSession] capture ready '
          'lastNonSilentAudioAtMillis=$lastNonSilentAt '
          'stabilizedForMs=${now - captureStartedAtMillis}',
        );
        return;
      }
      if (gate.isTimedOut(
        captureStartedAtMillis: captureStartedAtMillis,
        nowMillis: now,
      )) {
        throw StateError(
          'Микрофон не передал аудио за '
          '${VoiceCaptureStartupGate.timeoutMs} мс.',
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  Future<void> _enqueue(Future<void> Function() operation) {
    final Future<void> next = _operation.then((_) => operation());
    _operation = next.catchError((Object error, StackTrace stackTrace) {
      print('[WearVoiceSession] queued operation failed: $error\n$stackTrace');
    });
    return next;
  }

  Future<void> ensureHealthy({required String reason}) async {
    if (!_shouldListen) return;
    final int generation = _listeningGeneration;
    final service = WearDependencies.I.speechRecognitionService;
    final int now = DateTime.now().millisecondsSinceEpoch;
    final int? lastAudioAt = service.lastAudioChunkAtMillis;
    final int? lastAudioAgeMs = lastAudioAt == null ? null : now - lastAudioAt;
    final int? lastNonSilentAudioAt = service.lastNonSilentAudioChunkAtMillis;
    final int? lastNonSilentAudioAgeMs =
        lastNonSilentAudioAt == null ? null : now - lastNonSilentAudioAt;
    final int? zeroAudioStartedAt = service.continuousZeroAudioStartedAtMillis;
    final int? continuousZeroAudioAgeMs =
        zeroAudioStartedAt == null ? null : now - zeroAudioStartedAt;
    print(
      '[WearVoiceSession] health-check reason=$reason '
      'isListening=${service.isListening} lastAudioAgeMs=$lastAudioAgeMs '
      'lastNonSilentAudioAgeMs=$lastNonSilentAudioAgeMs '
      'continuousZeroAudioAgeMs=$continuousZeroAudioAgeMs '
      'diagnostics=${await diagnostics()}',
    );
    if (!_isCurrentListeningRequest(generation)) return;

    if (_captureSilenced) {
      print(
        '[WearVoiceSession] health-check deferred: Android is silencing capture',
      );
      return;
    }

    if (!service.isListening) {
      await start();
      return;
    }

    if (lastAudioAgeMs == null || lastAudioAgeMs > 3000) {
      await restart(reason: '$reason staleAudioAgeMs=$lastAudioAgeMs');
      return;
    }

    final bool hasCurrentNonSilentAudio =
        lastAudioAt != null && lastNonSilentAudioAt == lastAudioAt;
    if (_zeroAudioRecovery.shouldRestart(
      continuousZeroAudioAgeMs: continuousZeroAudioAgeMs,
      captureSilenced: _captureSilenced,
      hasCurrentNonSilentAudio: hasCurrentNonSilentAudio,
    )) {
      await restart(
        reason: '$reason continuousZeroAudioAgeMs=$continuousZeroAudioAgeMs',
      );
      return;
    }
  }

  bool _usesFreeTextRecognition(WearScreenId screen) {
    return switch (screen) {
      WearScreenId.printerSelect ||
      WearScreenId.productSelect ||
      WearScreenId.availabilityGroup ||
      WearScreenId.availabilityProduct ||
      WearScreenId.availabilityFill ||
      WearScreenId.printCodeInput =>
        true,
      _ => false,
    };
  }
}

class VoiceCaptureRecoveryGate {
  static const int zeroAudioThresholdMs = 5000;

  bool _armed = true;

  bool shouldRestart({
    required int? continuousZeroAudioAgeMs,
    required bool captureSilenced,
    required bool hasCurrentNonSilentAudio,
  }) {
    if (hasCurrentNonSilentAudio) {
      _armed = true;
      return false;
    }
    if (captureSilenced ||
        continuousZeroAudioAgeMs == null ||
        continuousZeroAudioAgeMs < zeroAudioThresholdMs ||
        !_armed) {
      return false;
    }
    _armed = false;
    return true;
  }

  void reset() {
    _armed = true;
  }
}

class VoiceCaptureStartupGate {
  static const int stabilizationMs = 7000;
  static const int timeoutMs = 10000;

  bool isReady({
    required int captureStartedAtMillis,
    required int? lastNonSilentAudioAtMillis,
    required int nowMillis,
  }) {
    return lastNonSilentAudioAtMillis != null &&
        lastNonSilentAudioAtMillis >= captureStartedAtMillis &&
        nowMillis - captureStartedAtMillis >= stabilizationMs;
  }

  bool isTimedOut({
    required int captureStartedAtMillis,
    required int nowMillis,
  }) {
    return nowMillis - captureStartedAtMillis >= timeoutMs;
  }
}
