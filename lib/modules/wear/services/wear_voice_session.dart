import 'dart:async';

import 'package:smart_glasses/core/voice/native_voice_capture.dart';
import 'package:smart_glasses/modules/wear/config/wear_dependencies.dart';
import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_typing/speech_recognition_service.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_typing/voice_device_profile.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/voice_action_catalog.dart';
import 'package:smart_glasses/modules/wear/services/voice_state.dart';

class WearVoiceSession {
  WearVoiceSession({
    SpeechRecognitionService? speechRecognitionService,
    Future<void> Function()? ensurePrepared,
    int Function()? nowMillis,
    Future<void> Function(Duration duration)? delay,
    Timer Function(Duration duration, void Function() callback)? scheduleRetry,
    VoiceActionCatalog? actionCatalog,
  })  : _speechRecognitionService = speechRecognitionService,
        _ensurePrepared = ensurePrepared,
        _nowMillis = nowMillis ?? (() => DateTime.now().millisecondsSinceEpoch),
        _delay = delay ?? Future<void>.delayed,
        _scheduleRetry = scheduleRetry ?? Timer.new,
        _actionCatalog = actionCatalog;

  static final WearVoiceSession I = WearVoiceSession();
  final SpeechRecognitionService? _speechRecognitionService;
  final Future<void> Function()? _ensurePrepared;
  final int Function() _nowMillis;
  final Future<void> Function(Duration duration) _delay;
  final Timer Function(Duration duration, void Function() callback)
      _scheduleRetry;
  final VoiceActionCatalog? _actionCatalog;
  bool _shouldListen = false;
  int _listeningGeneration = 0;
  Future<void> _operation = Future<void>.value();
  Future<void> _startupOperation = Future<void>.value();
  final VoiceSingleFlight _restartSingleFlight = VoiceSingleFlight();
  final VoiceSingleFlight _healthSingleFlight = VoiceSingleFlight();
  Timer? _retryTimer;
  Timer? _healthyRetryResetTimer;
  bool _nativeRecoveryRetryUsed = false;
  VoiceState _state = const VoiceState.disabled();
  final StreamController<VoiceState> _stateController =
      StreamController<VoiceState>.broadcast();
  final StreamController<bool> _reconnectingController =
      StreamController<bool>.broadcast();
  final StreamController<String?> _reconnectErrorController =
      StreamController<String?>.broadcast();
  int _pendingReconnects = 0;
  int? _handledNativeTerminationRevision;
  VoiceDeviceProfile? _requestedStartupProfile;
  WearScreenId? _configuredScreen;
  int _configurationGeneration = 0;
  Future<void> _configurationOperation = Future<void>.value();
  String? _requestedProfileId;
  String? _fallbackReason;
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

  void handleNativeVoiceState(NativeVoiceStateEvent event) {
    final bool fatalState = event.state == NativeVoiceCaptureState.error ||
        event.state == NativeVoiceCaptureState.unsupportedFirmware ||
        event.state == NativeVoiceCaptureState.terminalAbandoned ||
        event.state == NativeVoiceCaptureState.disposed ||
        event.state == NativeVoiceCaptureState.unknown;
    if (!fatalState || !_shouldListen) return;
    if (event.owner != null &&
        event.owner != NativeVoiceOwner.wearRecognition) {
      return;
    }
    if (event.leaseId == null &&
        !NativeVoiceCapture.instance
            .isOwnedBy(NativeVoiceOwner.wearRecognition)) {
      return;
    }
    if (!NativeVoiceCapture.instance.isRelevantStateEvent(event)) {
      return;
    }
    if (_handledNativeTerminationRevision == event.revision) return;
    _handledNativeTerminationRevision = event.revision;
    final String code = event.errorCode ?? 'NATIVE_CAPTURE_FAILED';
    final bool terminal = code == 'UNSUPPORTED_FIRMWARE' ||
        code == 'ACTIVATION_FAILED' ||
        code == 'ACTIVATION_TIMEOUT' ||
        code == 'SSP_INIT_FAILED' ||
        code == 'SSP_RELEASE_FAILED' ||
        code == 'TERMINAL_ABANDONED' ||
        code == 'PCM_ACK_TIMEOUT' ||
        code == 'INVALID_SSP_OUTPUT' ||
        code == 'SSP_PROCESS_FAILED' ||
        code == 'PCM_CONSUMER_BACKPRESSURE' ||
        code == 'UAC4_INIT_TIMEOUT' ||
        code == 'UAC4_START_TIMEOUT' ||
        code == 'UAC4_STOP_FAILED' ||
        code == 'UAC4_STOP_TIMEOUT' ||
        code == 'UAC4_DEINIT_FAILED' ||
        code == 'UAC4_DEINIT_TIMEOUT';
    final bool retry = !terminal && !_nativeRecoveryRetryUsed;
    if (retry) _nativeRecoveryRetryUsed = true;
    _markUnavailable(
      reason: 'native_$code',
      error: StateError(code),
      scheduleRetry: retry,
    );
  }

  Future<void> configureForScreen(
    WearScreenId screen, {
    bool force = false,
  }) {
    final int generation = ++_configurationGeneration;
    final Future<void> next = _configurationOperation.then((_) async {
      if (generation != _configurationGeneration) return;
      if (!force && _configuredScreen == screen) return;
      final VoiceActionCatalog catalog =
          _actionCatalog ?? WearDependencies.I.voiceActionCatalog;
      final bool freeText = _usesFreeTextRecognition(screen);
      print(
        '[WearVoiceSession] configureForScreen screen=$screen '
        'mode=${freeText ? 'freeText' : 'grammar'}',
      );
      try {
        await _speech.switchCommandGrammar(
          screen: screen,
          grammar: catalog.grammarFor(screen),
        );
      } catch (_) {
        if (generation != _configurationGeneration) rethrow;
        if (_shouldListen) {
          _emit(VoicePhase.reconnecting, reason: 'grammar_switch_retry');
        }
        await _delay(const Duration(milliseconds: 100));
        try {
          await _speech.switchCommandGrammar(
            screen: screen,
            grammar: catalog.grammarFor(screen),
          );
        } catch (error) {
          if (_shouldListen) {
            _markUnavailable(
              reason: 'grammar_switch_failed',
              error: error,
            );
          }
          rethrow;
        }
      }
      if (generation != _configurationGeneration) return;
      await _speech.setFreeTextEnabled(freeText);
      if (generation == _configurationGeneration) _configuredScreen = screen;
    });
    _configurationOperation = next.catchError(
      (Object error, StackTrace stackTrace) {
        print('[WearVoiceSession] screen configuration failed: '
            '$error\n$stackTrace');
      },
    );
    return next;
  }

  Future<void> start() async {
    if (!_shouldListen) _nativeRecoveryRetryUsed = false;
    _shouldListen = true;
    _requestedStartupProfile ??= _speech.deviceProfile;
    _requestedProfileId = _speech.deviceProfile.id;
    _fallbackReason = null;
    _retryTimer?.cancel();
    _retryTimer = null;
    _healthyRetryResetTimer?.cancel();
    _healthyRetryResetTimer = null;
    final int generation = ++_listeningGeneration;
    final Future<void> startup = _enqueue(() async {
      print('[WearVoiceSession] start requested, isListening=$isListening');
      if (!_isCurrentListeningRequest(generation)) return;
      if (_hasHealthyCapture()) {
        _emit(VoicePhase.ready,
            reason: 'already_listening', resetAttempt: true);
        print('[WearVoiceSession] start skipped: ${await diagnostics()}');
        return;
      }
      if (isListening || _speech.isCaptureRunning) {
        await _speech.stopListening();
      }
      try {
        _emit(VoicePhase.loadingModel, reason: 'start');
        _zeroAudioRecovery.reset();
        await _prepare();
        if (!_isCurrentListeningRequest(generation)) return;
        var startupRecreates = 0;
        while (_isCurrentListeningRequest(generation)) {
          _emit(
            startupRecreates == 0
                ? VoicePhase.startingRecorder
                : VoicePhase.reconnecting,
            reason: startupRecreates == 0
                ? 'start_recorder'
                : 'startup_exact_zero_recreate_$startupRecreates',
          );
          if (startupRecreates == 0) {
            await _speech.startListening();
          } else {
            await _delay(const Duration(milliseconds: 300));
            await _speech.restartListening(
              reason: 'startup_exact_zero_recreate_$startupRecreates',
            );
          }
          if (!_isCurrentListeningRequest(generation)) {
            await _speech.stopListening();
            return;
          }
          try {
            final bool ready = await _waitForCaptureReady(
              generation: generation,
              captureStartedAtMillis: _captureStartedAtMillis(),
              exactZeroGrace: startupRecreates == 0
                  ? _speech.deviceProfile.exactZeroStartupGrace
                  : _speech.deviceProfile.postRecreateExactZeroStartupGrace,
              captureTimeout: startupRecreates == 0
                  ? _speech.deviceProfile.recoveryCaptureTimeout
                  : _speech.deviceProfile.postRecreateCaptureTimeout,
            );
            if (!ready || !_isCurrentListeningRequest(generation)) {
              await _speech.stopListening();
              return;
            }
            _emit(VoicePhase.ready, reason: 'start_ready', resetAttempt: true);
            print('[WearVoiceSession] started: ${await diagnostics()}');
            return;
          } on VoiceExactZeroStartupFailure {
            if (startupRecreates >=
                _speech.deviceProfile.maxStartupRecorderRecreates) {
              rethrow;
            }
            startupRecreates++;
          }
        }
      } catch (error, stackTrace) {
        try {
          await _speech.stopListening();
        } catch (cleanupError, cleanupStackTrace) {
          print(
            '[WearVoiceSession] start cleanup failed: '
            '$cleanupError\n$cleanupStackTrace',
          );
        }
        print('[WearVoiceSession] start failed: $error\n$stackTrace');
        if (error is VoiceExactZeroStartupFailure) {
          _markUnavailable(
            reason: 'startup_exact_zero_terminal',
            error: error,
            scheduleRetry: false,
          );
          return;
        }
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
    _retryTimer?.cancel();
    _retryTimer = null;
    _healthyRetryResetTimer?.cancel();
    _healthyRetryResetTimer = null;
    _nativeRecoveryRetryUsed = false;
    _zeroAudioRecovery.reset();
    _listeningGeneration++;
    return _enqueue(() async {
      print('[WearVoiceSession] stop requested, isListening=$isListening');
      try {
        await _speech.stopListening();
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
      _setReconnectError(null);
      _setReconnecting(true);
      _emit(VoicePhase.reconnecting, reason: reason);
      try {
        await _enqueue(() async {
          print('[WearVoiceSession] restart requested reason=$reason');
          try {
            _zeroAudioRecovery.rearmAfterRestart();
            await _speech.stopListening();
          } catch (error, stackTrace) {
            print(
                '[WearVoiceSession] restart cleanup failed: $error\n$stackTrace');
          }
        });
        await start();
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
    required Duration exactZeroGrace,
    required Duration captureTimeout,
  }) async {
    final VoiceCaptureStartupGate gate = VoiceCaptureStartupGate();
    final service = _speech;

    while (_isCurrentListeningRequest(generation)) {
      final int now = _nowMillis();
      if (!service.isListening || !service.isCaptureRunning) {
        throw StateError('Захват аудио остановлен до получения PCM-чанков.');
      }
      final int? lastAudioAt = service.lastAudioChunkAtMillis;
      final bool nativeInputActive = await service.refreshNativeInputActivity();
      final int? lastNonSilentAudioAt =
          nativeInputActive ? now : service.lastNonSilentAudioChunkAtMillis;
      final int? zeroAudioStartedAt =
          nativeInputActive ? null : service.continuousZeroAudioStartedAtMillis;
      if (gate.isReady(
            captureStartedAtMillis: captureStartedAtMillis,
            isCaptureRunning: service.isCaptureRunning,
            chunksReceived: service.audioChunksReceived,
            lastAudioAtMillis: lastAudioAt,
            lastNonSilentAudioAtMillis: lastNonSilentAudioAt,
            continuousZeroAudioStartedAtMillis: zeroAudioStartedAt,
            requireNonZeroPcm:
                service.deviceProfile.requireNonZeroPcmForStartup,
            hasExpectedInputDevice: service.hasExpectedInputDevice,
            nativeRouteMatchesExpected: true,
            nowMillis: now,
          ) &&
          service.isVadCalibrated) {
        print(
          '[WearVoiceSession] capture ready '
          'lastAudioAtMillis=$lastAudioAt '
          'chunks=${service.audioChunksReceived} '
          'stabilizedForMs=${now - captureStartedAtMillis}',
        );
        return true;
      }
      if (service.deviceProfile.requireNonZeroPcmForStartup &&
          gate.isWaitingForNonZeroPcm(
            chunksReceived: service.audioChunksReceived,
            continuousZeroAudioStartedAtMillis: zeroAudioStartedAt,
          )) {
        _emit(
          VoicePhase.waitingForAudioRoute,
          reason: 'startup_exact_zero_pcm',
        );
      }
      if (service.deviceProfile.requireNonZeroPcmForStartup &&
          gate.hasExceededExactZeroGrace(
            continuousZeroAudioStartedAtMillis: zeroAudioStartedAt,
            nowMillis: now,
            grace: exactZeroGrace,
          )) {
        throw const VoiceExactZeroStartupFailure();
      }
      final Duration effectiveTimeout = lastNonSilentAudioAt == null
          ? captureTimeout
          : captureTimeout + const Duration(seconds: 1);
      if (gate.isTimedOut(
        captureStartedAtMillis: captureStartedAtMillis,
        nowMillis: now,
        timeout: effectiveTimeout,
      )) {
        if (service.deviceProfile.requireNonZeroPcmForStartup &&
            gate.isWaitingForNonZeroPcm(
              chunksReceived: service.audioChunksReceived,
              continuousZeroAudioStartedAtMillis: zeroAudioStartedAt,
            )) {
          throw const VoiceExactZeroStartupFailure();
        }
        throw StateError(
          'Микрофон не передал PCM-чанки за '
          '${captureTimeout.inMilliseconds} мс.',
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
    final bool nativeInputActive = await service.refreshNativeInputActivity();
    final int? lastNonSilentAudioAt =
        nativeInputActive ? now : service.lastNonSilentAudioChunkAtMillis;
    final int? lastNonSilentAudioAgeMs =
        lastNonSilentAudioAt == null ? null : now - lastNonSilentAudioAt;
    final int? zeroAudioStartedAt =
        nativeInputActive ? null : service.continuousZeroAudioStartedAtMillis;
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
      captureSilenced: false,
      hasCurrentNonSilentAudio: hasCurrentNonSilentAudio,
    )) {
      case VoiceCaptureRecoveryAction.none:
        return;
      case VoiceCaptureRecoveryAction.restart:
        await restart(
          reason: '$reason continuousZeroAudioAgeMs=$continuousZeroAudioAgeMs',
        );
        return;
      case VoiceCaptureRecoveryAction.unavailable:
        _markUnavailable(
          reason: '$reason continuous_zero_audio',
          error: StateError('UAC4 capture has no non-zero PCM after restart.'),
          scheduleRetry: false,
        );
        return;
    }
  }

  void _emit(
    VoicePhase phase, {
    required String reason,
    Object? error,
    bool resetAttempt = false,
    int? nextRetryAt,
  }) {
    final int now = _nowMillis();
    final VoiceState next = VoiceState(
      phase: phase,
      captureEpoch: _listeningGeneration,
      attempt: resetAttempt ? 0 : _state.attempt,
      reason: reason,
      lastTransitionAt: now,
      lastError: error?.toString(),
      nextRetryAt: nextRetryAt,
      requestedProfile: _requestedProfileId,
      activeProfile: _speech.deviceProfile.id,
      fallbackReason: _fallbackReason,
    );
    if (_state.phase == next.phase &&
        _state.reason == next.reason &&
        _state.attempt == next.attempt &&
        _state.captureEpoch == next.captureEpoch &&
        _state.lastError == next.lastError) {
      return;
    }
    _state = next;
    if (!_stateController.isClosed) _stateController.add(_state);
    if (phase == VoicePhase.ready) _armHealthyRetryReset();
  }

  void _markUnavailable({
    required String reason,
    required Object error,
    bool scheduleRetry = true,
  }) {
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
    _healthyRetryResetTimer?.cancel();
    _healthyRetryResetTimer = null;
    _retryTimer?.cancel();
    if (!scheduleRetry || !_shouldListen) return;
    _retryTimer = _scheduleRetry(delay, () {
      _retryTimer = null;
      if (!_shouldListen) return;
      unawaited(restart(reason: 'retry_attempt_$nextAttempt'));
    });
  }

  int _captureStartedAtMillis() {
    return _speech.captureStartedAtMillis ?? _nowMillis();
  }

  bool _hasHealthyCapture() {
    final int now = _nowMillis();
    final int? lastAudio = _speech.lastAudioChunkAtMillis;
    final int? lastNonSilent = _speech.lastNonSilentAudioChunkAtMillis;
    final int? lastNativeInput = _speech.lastNonZeroNativeInputAtMillis;
    final bool hasRecentNativeInput = lastNativeInput != null &&
        now - lastNativeInput <= VoiceCaptureHealthGate.staleAudioThresholdMs;
    return _speech.isListening &&
        _speech.isCaptureRunning &&
        _speech.isVadCalibrated &&
        _speech.audioChunksReceived >= VoiceCaptureStartupGate.requiredChunks &&
        _speech.hasExpectedInputDevice &&
        lastAudio != null &&
        now - lastAudio <= VoiceCaptureHealthGate.staleAudioThresholdMs &&
        (hasRecentNativeInput ||
            (lastNonSilent != null &&
                _speech.continuousZeroAudioStartedAtMillis == null));
  }

  Duration _retryDelay(int attempt) {
    return VoiceRetryPolicy.delayFor(attempt);
  }

  void _armHealthyRetryReset() {
    _healthyRetryResetTimer?.cancel();
    _healthyRetryResetTimer = _scheduleRetry(const Duration(seconds: 60), () {
      _healthyRetryResetTimer = null;
      if (_shouldListen && _hasHealthyCapture()) {
        _nativeRecoveryRetryUsed = false;
      }
    });
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
      return VoiceCaptureRecoveryAction.unavailable;
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
  unavailable,
}

class VoiceCaptureStartupGate {
  static const int requiredChunks = 3;
  static const int timeoutMs = 15000;

  bool isReady({
    required int captureStartedAtMillis,
    required bool isCaptureRunning,
    required int chunksReceived,
    required int? lastAudioAtMillis,
    required int? lastNonSilentAudioAtMillis,
    required int? continuousZeroAudioStartedAtMillis,
    required bool requireNonZeroPcm,
    required bool hasExpectedInputDevice,
    required bool nativeRouteMatchesExpected,
    required int nowMillis,
  }) {
    return isCaptureRunning &&
        hasExpectedInputDevice &&
        nativeRouteMatchesExpected &&
        chunksReceived >= requiredChunks &&
        lastAudioAtMillis != null &&
        lastAudioAtMillis >= captureStartedAtMillis &&
        (!requireNonZeroPcm ||
            (lastNonSilentAudioAtMillis != null &&
                lastNonSilentAudioAtMillis >= captureStartedAtMillis &&
                continuousZeroAudioStartedAtMillis == null));
  }

  bool isWaitingForNonZeroPcm({
    required int chunksReceived,
    required int? continuousZeroAudioStartedAtMillis,
  }) {
    return chunksReceived >= requiredChunks &&
        continuousZeroAudioStartedAtMillis != null;
  }

  bool hasExceededExactZeroGrace({
    required int? continuousZeroAudioStartedAtMillis,
    required int nowMillis,
    required Duration grace,
  }) {
    return continuousZeroAudioStartedAtMillis != null &&
        nowMillis - continuousZeroAudioStartedAtMillis >= grace.inMilliseconds;
  }

  bool isTimedOut({
    required int captureStartedAtMillis,
    required int nowMillis,
    required Duration timeout,
  }) {
    return nowMillis - captureStartedAtMillis >= timeout.inMilliseconds;
  }
}

class VoiceExactZeroStartupFailure implements Exception {
  const VoiceExactZeroStartupFailure();

  @override
  String toString() => 'VoiceExactZeroStartupFailure';
}
