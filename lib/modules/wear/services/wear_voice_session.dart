import 'dart:async';

import 'package:smart_glasses/core/services/method_channel_service.dart';
import 'package:smart_glasses/modules/wear/config/wear_dependencies.dart';
import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_typing/speech_recognition_service.dart';
import 'package:smart_glasses/modules/wear/services/voice_state.dart';

class WearVoiceSession {
  WearVoiceSession({
    SpeechRecognitionService? speechRecognitionService,
    Future<void> Function()? ensurePrepared,
    Future<void> Function({
      required bool active,
      required String source,
      required int captureId,
    })? updateNativeCaptureMonitor,
    int Function()? nowMillis,
    Future<void> Function(Duration duration)? delay,
    Timer Function(Duration duration, void Function() callback)? scheduleRetry,
  })  : _speechRecognitionService = speechRecognitionService,
        _ensurePrepared = ensurePrepared,
        _updateNativeCaptureMonitorOverride = updateNativeCaptureMonitor,
        _nowMillis = nowMillis ?? (() => DateTime.now().millisecondsSinceEpoch),
        _delay = delay ?? Future<void>.delayed,
        _scheduleRetry = scheduleRetry ?? Timer.new;

  static final WearVoiceSession I = WearVoiceSession();
  final SpeechRecognitionService? _speechRecognitionService;
  final Future<void> Function()? _ensurePrepared;
  final Future<void> Function({
    required bool active,
    required String source,
    required int captureId,
  })? _updateNativeCaptureMonitorOverride;
  final int Function() _nowMillis;
  final Future<void> Function(Duration duration) _delay;
  final Timer Function(Duration duration, void Function() callback)
      _scheduleRetry;
  bool _shouldListen = false;
  bool _captureSilenced = false;
  int _listeningGeneration = 0;
  Future<void> _operation = Future<void>.value();
  Future<void> _startupOperation = Future<void>.value();
  final VoiceSingleFlight _restartSingleFlight = VoiceSingleFlight();
  final VoiceSingleFlight _healthSingleFlight = VoiceSingleFlight();
  Timer? _retryTimer;
  VoiceState _state = const VoiceState.disabled();
  final StreamController<VoiceState> _stateController =
      StreamController<VoiceState>.broadcast();
  final StreamController<bool> _reconnectingController =
      StreamController<bool>.broadcast();
  final StreamController<String?> _reconnectErrorController =
      StreamController<String?>.broadcast();
  int _pendingReconnects = 0;
  final VoiceCaptureRecoveryGate _zeroAudioRecovery =
      VoiceCaptureRecoveryGate();

  SpeechRecognitionService get _speech =>
      _speechRecognitionService ?? WearDependencies.I.speechRecognitionService;
  Future<void> _prepare() =>
      _ensurePrepared?.call() ?? WearDependencies.I.ensureVoiceTypingPrepared();

  bool get isListening => _speech.isListening;
  VoiceState get state => _state;
  Stream<VoiceState> get stateStream => _stateController.stream;

  Stream<bool> get reconnectingStream => _reconnectingController.stream;
  Stream<String?> get reconnectErrorStream => _reconnectErrorController.stream;
  bool get forceHardRestartOnResume =>
      _speech.deviceProfile.forceHardRestartOnResume;
  bool get forceHardRestartAfterUnsilence =>
      _speech.deviceProfile.forceHardRestartAfterUnsilence;
  Future<String> diagnostics() {
    return _speech.diagnostics();
  }

  void setCaptureSilenced(bool silenced) {
    final bool wasSilenced = _captureSilenced;
    _captureSilenced = silenced;
    if (silenced) {
      _emit(VoicePhase.suspendedBySystem, reason: 'android_capture_silenced');
      return;
    }
    if (wasSilenced && _shouldListen) {
      if (forceHardRestartAfterUnsilence) {
        unawaited(restart(reason: 'android_audio_capture_unsilenced'));
      } else {
        unawaited(ensureHealthy(reason: 'android_audio_capture_unsilenced'));
      }
    }
  }

  Future<void> configureForScreen(WearScreenId screen) async {
    final bool freeText = _usesFreeTextRecognition(screen);
    print(
      '[WearVoiceSession] configureForScreen screen=$screen '
      'mode=${freeText ? 'freeText' : 'grammar'}',
    );
    await _speech.setFreeTextEnabled(freeText);
  }

  Future<void> start() async {
    _shouldListen = true;
    _retryTimer?.cancel();
    _retryTimer = null;
    final int generation = ++_listeningGeneration;
    final Future<void> startup = _enqueue(() async {
      print('[WearVoiceSession] start requested, isListening=$isListening');
      if (!_isCurrentListeningRequest(generation)) return;
      if (isListening) {
        _emit(VoicePhase.ready,
            reason: 'already_listening', resetAttempt: true);
        print('[WearVoiceSession] start skipped: ${await diagnostics()}');
        return;
      }
      try {
        _emit(VoicePhase.preparing, reason: 'start');
        _zeroAudioRecovery.reset();
        await _prepare();
        if (!_isCurrentListeningRequest(generation)) return;
        await _speech.startListening();
        if (!_isCurrentListeningRequest(generation)) {
          await _speech.stopListening();
          await _updateNativeCaptureMonitor(active: false);
          return;
        }
        await _updateNativeCaptureMonitor(active: true);
        final bool ready = await _waitForCaptureReady(
          generation: generation,
          captureStartedAtMillis: _captureStartedAtMillis(),
        );
        if (!ready ||
            !_isCurrentListeningRequest(generation) ||
            _captureSilenced) {
          return;
        }
        _emit(VoicePhase.ready, reason: 'start_ready', resetAttempt: true);
        print('[WearVoiceSession] started: ${await diagnostics()}');
      } catch (error, stackTrace) {
        try {
          await _speech.stopListening();
          await _updateNativeCaptureMonitor(active: false);
        } catch (cleanupError, cleanupStackTrace) {
          print(
            '[WearVoiceSession] start cleanup failed: '
            '$cleanupError\n$cleanupStackTrace',
          );
        }
        print('[WearVoiceSession] start failed: $error\n$stackTrace');
        _markUnavailable(reason: 'start_failed', error: error);
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
    _retryTimer?.cancel();
    _retryTimer = null;
    _zeroAudioRecovery.reset();
    _listeningGeneration++;
    return _enqueue(() async {
      print('[WearVoiceSession] stop requested, isListening=$isListening');
      try {
        await _speech.stopListening();
        await _updateNativeCaptureMonitor(active: false);
        _emit(VoicePhase.disabled, reason: 'stop', resetAttempt: true);
        print('[WearVoiceSession] stopped: ${await diagnostics()}');
      } catch (error, stackTrace) {
        print('[WearVoiceSession] stop failed: $error\n$stackTrace');
      }
    });
  }

  Future<void> restart({required String reason}) async {
    final Future<void>? pendingRestart = _restartSingleFlight.pending;
    if (pendingRestart != null) {
      print('[WearVoiceSession] restart joined reason=$reason');
      return pendingRestart;
    }
    return _restartSingleFlight.run(() async {
      _shouldListen = true;
      _retryTimer?.cancel();
      _retryTimer = null;
      final int generation = ++_listeningGeneration;
      _setReconnectError(null);
      _setReconnecting(true);
      _emit(VoicePhase.reconnecting, reason: reason);
      try {
        await _enqueue(() async {
          print('[WearVoiceSession] restart requested reason=$reason');
          if (!_isCurrentListeningRequest(generation)) return;
          try {
            _zeroAudioRecovery.rearmAfterRestart();
            await _prepare();
            if (!_isCurrentListeningRequest(generation)) return;
            await _speech.restartListening(reason: reason);
            if (!_isCurrentListeningRequest(generation)) {
              await _speech.stopListening();
              await _updateNativeCaptureMonitor(active: false);
              return;
            }
            await _updateNativeCaptureMonitor(active: true);
            final bool ready = await _waitForCaptureReady(
              generation: generation,
              captureStartedAtMillis: _captureStartedAtMillis(),
            );
            if (!ready ||
                !_isCurrentListeningRequest(generation) ||
                _captureSilenced) {
              return;
            }
            _emit(VoicePhase.ready, reason: reason, resetAttempt: true);
            print('[WearVoiceSession] restarted: ${await diagnostics()}');
          } catch (error, stackTrace) {
            print('[WearVoiceSession] restart failed: $error\n$stackTrace');
            _zeroAudioRecovery.reset();
            try {
              await _speech.stopListening();
              await _updateNativeCaptureMonitor(active: false);
              await _speech.audioStreamService.recreateRecorder();
            } catch (cleanupError, cleanupStackTrace) {
              print(
                '[WearVoiceSession] restart cleanup failed: '
                '$cleanupError\n$cleanupStackTrace',
              );
            }
            _markUnavailable(reason: reason, error: error);
          }
        });
      } finally {
        _setReconnecting(false);
      }
    });
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

  Future<bool> _waitForCaptureReady({
    required int generation,
    required int captureStartedAtMillis,
  }) async {
    final VoiceCaptureStartupGate gate = VoiceCaptureStartupGate();
    final service = _speech;

    while (_isCurrentListeningRequest(generation)) {
      if (_captureSilenced) return false;
      final int now = _nowMillis();
      if (!service.isListening || !service.isCaptureRunning) {
        throw StateError('Захват аудио остановлен до получения PCM-чанков.');
      }
      final int? lastAudioAt = service.lastAudioChunkAtMillis;
      if (gate.isReady(
        captureStartedAtMillis: captureStartedAtMillis,
        isCaptureRunning: service.isCaptureRunning,
        chunksReceived: service.audioChunksReceived,
        lastAudioAtMillis: lastAudioAt,
        nowMillis: now,
      )) {
        print(
          '[WearVoiceSession] capture ready '
          'lastAudioAtMillis=$lastAudioAt '
          'chunks=${service.audioChunksReceived} '
          'stabilizedForMs=${now - captureStartedAtMillis}',
        );
        return true;
      }
      if (gate.isTimedOut(
        captureStartedAtMillis: captureStartedAtMillis,
        nowMillis: now,
      )) {
        throw StateError(
          'Микрофон не передал PCM-чанки за '
          '${VoiceCaptureStartupGate.timeoutMs} мс.',
        );
      }
      await _delay(const Duration(milliseconds: 100));
    }
    return false;
  }

  Future<void> _enqueue(Future<void> Function() operation) {
    final Future<void> next = _operation.then((_) => operation());
    _operation = next.catchError((Object error, StackTrace stackTrace) {
      print('[WearVoiceSession] queued operation failed: $error\n$stackTrace');
    });
    return next;
  }

  Future<void> ensureHealthy({required String reason}) async {
    final Future<void>? pendingHealthCheck = _healthSingleFlight.pending;
    if (pendingHealthCheck != null) {
      print('[WearVoiceSession] health-check joined reason=$reason');
      return pendingHealthCheck;
    }
    return _healthSingleFlight.run(() => _ensureHealthy(reason: reason));
  }

  Future<void> _ensureHealthy({required String reason}) async {
    if (!_shouldListen) return;
    if (_state.phase == VoicePhase.unavailable && _retryTimer != null) {
      print('[WearVoiceSession] health-check deferred: retry is scheduled');
      return;
    }
    final int generation = _listeningGeneration;
    final service = _speech;
    final int now = _nowMillis();
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
      await restart(reason: '$reason recorder_not_listening');
      return;
    }

    if (VoiceCaptureHealthGate.hasStaleAudio(lastAudioAgeMs)) {
      await restart(reason: '$reason staleAudioAgeMs=$lastAudioAgeMs');
      return;
    }

    final bool hasCurrentNonSilentAudio =
        lastAudioAt != null && lastNonSilentAudioAt == lastAudioAt;
    switch (_zeroAudioRecovery.nextAction(
      continuousZeroAudioAgeMs: continuousZeroAudioAgeMs,
      captureSilenced: _captureSilenced,
      hasCurrentNonSilentAudio: hasCurrentNonSilentAudio,
    )) {
      case VoiceCaptureRecoveryAction.none:
        return;
      case VoiceCaptureRecoveryAction.restart:
        await restart(
          reason: '$reason continuousZeroAudioAgeMs=$continuousZeroAudioAgeMs',
        );
        return;
      case VoiceCaptureRecoveryAction.requireMicrophoneReconnect:
        await _requireMicrophoneReconnect(
          reason: '$reason continuousZeroAudioAgeMs=$continuousZeroAudioAgeMs',
        );
        return;
    }
  }

  Future<void> _requireMicrophoneReconnect({required String reason}) async {
    print('[WearVoiceSession] microphone reconnect required reason=$reason');
    _shouldListen = false;
    _listeningGeneration++;
    _retryTimer?.cancel();
    _retryTimer = null;
    await _enqueue(() async {
      try {
        await _speech.stopListening();
        await _updateNativeCaptureMonitor(active: false);
      } catch (error, stackTrace) {
        print(
          '[WearVoiceSession] microphone reconnect cleanup failed: '
          '$error\n$stackTrace',
        );
      }
      _emit(
        VoicePhase.microphoneReconnectRequired,
        reason: reason,
        error: StateError('Микрофон не передаёт аудио после перезапуска.'),
      );
    });
  }

  void _emit(
    VoicePhase phase, {
    required String reason,
    Object? error,
    bool resetAttempt = false,
    int? nextRetryAt,
  }) {
    final int now = _nowMillis();
    _state = VoiceState(
      phase: phase,
      captureEpoch: _listeningGeneration,
      attempt: resetAttempt ? 0 : _state.attempt,
      reason: reason,
      lastTransitionAt: now,
      lastError: error?.toString(),
      nextRetryAt: nextRetryAt,
    );
    if (!_stateController.isClosed) _stateController.add(_state);
  }

  void _markUnavailable({required String reason, required Object error}) {
    final int nextAttempt = _state.attempt + 1;
    final Duration delay = _retryDelay(nextAttempt);
    final int retryAt = _nowMillis() + delay.inMilliseconds;
    _state = _state.copyWith(
      phase: VoicePhase.unavailable,
      attempt: nextAttempt,
      reason: reason,
      lastTransitionAt: _nowMillis(),
      lastError: error.toString(),
      nextRetryAt: retryAt,
    );
    if (!_stateController.isClosed) _stateController.add(_state);
    _setReconnectError('Голосовое управление недоступно');
    _retryTimer?.cancel();
    if (!_shouldListen || _captureSilenced) return;
    _retryTimer = _scheduleRetry(delay, () {
      _retryTimer = null;
      if (!_shouldListen || _captureSilenced) return;
      unawaited(restart(reason: 'retry_attempt_$nextAttempt'));
    });
  }

  int _captureStartedAtMillis() {
    return _speech.captureStartedAtMillis ?? _nowMillis();
  }

  Future<void> _updateNativeCaptureMonitor({required bool active}) {
    final service = _speech;
    final update = _updateNativeCaptureMonitorOverride;
    if (update != null) {
      return update(
        active: active,
        source: service.deviceProfile.audioSource.name,
        captureId: service.audioCaptureId,
      );
    }
    return MethodChannelService().updateVoiceCaptureMonitor(
      active: active,
      source: service.deviceProfile.audioSource.name,
      captureId: service.audioCaptureId,
    );
  }

  Duration _retryDelay(int attempt) {
    return VoiceRetryPolicy.delayFor(attempt);
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

class VoiceSingleFlight {
  Future<void>? _pending;

  Future<void>? get pending => _pending;

  Future<void> run(Future<void> Function() operation) {
    final Future<void>? pending = _pending;
    if (pending != null) return pending;

    late final Future<void> next;
    next = Future<void>.microtask(operation).whenComplete(() {
      if (identical(_pending, next)) _pending = null;
    });
    _pending = next;
    return next;
  }
}

class VoiceCaptureHealthGate {
  static const int staleAudioThresholdMs = 3000;

  static bool hasStaleAudio(int? lastAudioAgeMs) {
    return lastAudioAgeMs == null || lastAudioAgeMs > staleAudioThresholdMs;
  }
}

class VoiceRetryPolicy {
  static const List<Duration> _delays = <Duration>[
    Duration(seconds: 1),
    Duration(seconds: 1),
    Duration(seconds: 3),
    Duration(seconds: 10),
    Duration(seconds: 30),
    Duration(seconds: 60),
  ];

  static Duration delayFor(int attempt) {
    return _delays[(attempt - 1).clamp(0, _delays.length - 1)];
  }
}

class VoiceCaptureRecoveryGate {
  static const int zeroAudioThresholdMs = 5000;
  static const int maxAutomaticRestarts = 1;

  bool _armed = true;
  int _automaticRestarts = 0;

  VoiceCaptureRecoveryAction nextAction({
    required int? continuousZeroAudioAgeMs,
    required bool captureSilenced,
    required bool hasCurrentNonSilentAudio,
  }) {
    if (hasCurrentNonSilentAudio) {
      _armed = true;
      _automaticRestarts = 0;
      return VoiceCaptureRecoveryAction.none;
    }
    if (captureSilenced ||
        continuousZeroAudioAgeMs == null ||
        continuousZeroAudioAgeMs < zeroAudioThresholdMs ||
        !_armed) {
      return VoiceCaptureRecoveryAction.none;
    }
    _armed = false;
    if (_automaticRestarts >= maxAutomaticRestarts) {
      return VoiceCaptureRecoveryAction.requireMicrophoneReconnect;
    }
    _automaticRestarts++;
    return VoiceCaptureRecoveryAction.restart;
  }

  void rearmAfterRestart() {
    _armed = true;
  }

  void reset() {
    _armed = true;
    _automaticRestarts = 0;
  }
}

enum VoiceCaptureRecoveryAction {
  none,
  restart,
  requireMicrophoneReconnect,
}

class VoiceCaptureStartupGate {
  static const int requiredChunks = 3;
  static const int timeoutMs = 2000;

  bool isReady({
    required int captureStartedAtMillis,
    required bool isCaptureRunning,
    required int chunksReceived,
    required int? lastAudioAtMillis,
    required int nowMillis,
  }) {
    return isCaptureRunning &&
        chunksReceived >= requiredChunks &&
        lastAudioAtMillis != null &&
        lastAudioAtMillis >= captureStartedAtMillis;
  }

  bool isTimedOut({
    required int captureStartedAtMillis,
    required int nowMillis,
  }) {
    return nowMillis - captureStartedAtMillis >= timeoutMs;
  }
}
