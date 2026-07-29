import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:smart_glasses/modules/wear/config/wear_dependencies.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_typing/voice_typing_service.dart';

enum WearCodeInputMode { digits, voice }

enum WearVoicePhase { idle, starting, listening, restarting, error }

@immutable
class WearPrintCodeInputState {
  const WearPrintCodeInputState({
    required this.mode,
    required this.value,
    required this.cursor,
    required this.recognizedWords,
    required this.voicePhase,
    required this.voiceError,
  });

  factory WearPrintCodeInputState.initial() {
    return const WearPrintCodeInputState(
      mode: WearCodeInputMode.digits,
      value: '',
      cursor: 0,
      recognizedWords: '',
      voicePhase: WearVoicePhase.idle,
      voiceError: null,
    );
  }

  final WearCodeInputMode mode;
  final String value;
  final int cursor;
  final String recognizedWords;
  final WearVoicePhase voicePhase;
  final String? voiceError;

  bool get hasValue => value.trim().isNotEmpty;

  WearPrintCodeInputState copyWith({
    WearCodeInputMode? mode,
    String? value,
    int? cursor,
    String? recognizedWords,
    WearVoicePhase? voicePhase,
    String? voiceError,
    bool clearVoiceError = false,
    bool clearRecognizedWords = false,
  }) {
    return WearPrintCodeInputState(
      mode: mode ?? this.mode,
      value: value ?? this.value,
      cursor: cursor ?? this.cursor,
      recognizedWords:
          clearRecognizedWords ? '' : (recognizedWords ?? this.recognizedWords),
      voicePhase: voicePhase ?? this.voicePhase,
      voiceError: clearVoiceError ? null : (voiceError ?? this.voiceError),
    );
  }
}

class WearPrintCodeInputCubit extends Cubit<WearPrintCodeInputState> {
  WearPrintCodeInputCubit({
    VoiceTypingService? voiceTypingService,
    Future<void> Function()? ensureVoicePrepared,
  })  : _voiceTypingService =
            voiceTypingService ?? WearDependencies.I.voiceTypingService,
        _ensureVoicePrepared =
            ensureVoicePrepared ?? WearDependencies.I.ensureVoiceTypingPrepared,
        super(WearPrintCodeInputState.initial()) {
    _resultSubscription = _voiceTypingService.resultsStream.listen(
      _onVoiceResult,
      onError: _onVoiceError,
    );
    _audioLevelSubscription = _voiceTypingService.audioLevelStream.listen(
      _onAudioLevel,
      onError: _onVoiceError,
    );
  }

  static const int _maxCodeLength = 32;

  final VoiceTypingService _voiceTypingService;
  final Future<void> Function() _ensureVoicePrepared;
  final ValueNotifier<double> _voiceLevel01 = ValueNotifier<double>(0);

  StreamSubscription<String>? _resultSubscription;
  StreamSubscription<double>? _audioLevelSubscription;

  bool _wantVoice = false;
  int _session = 0;

  ValueNotifier<double> get voiceLevel01 => _voiceLevel01;

  Future<void> setMode(WearCodeInputMode mode) async {
    if (mode == state.mode) {
      return;
    }

    if (mode == WearCodeInputMode.voice) {
      emit(state.copyWith(mode: mode));
      await startVoice();
      return;
    }

    await stopVoice();
    emit(state.copyWith(mode: mode));
  }

  void pressDigit(int digit) {
    if (state.mode != WearCodeInputMode.digits) return;
    if (state.value.length >= _maxCodeLength) return;
    final int cursor = _resolveInsertCursor();
    final String before = state.value.substring(0, cursor);
    final String after = state.value.substring(cursor);
    final String next = '$before$digit$after';
    final int nextCursor = cursor + 1;
    emit(state.copyWith(value: next, cursor: nextCursor));
    unawaited(HapticFeedback.selectionClick());
  }

  void backspace() {
    if (state.value.isEmpty) return;
    final int cursor = _clampCursor(state.cursor, state.value.length);
    if (cursor == 0) return;
    final String before = state.value.substring(0, cursor - 1);
    final String after = state.value.substring(cursor);
    final String next = '$before$after';
    final int nextCursor = (cursor - 1).clamp(0, next.length);
    emit(state.copyWith(value: next, cursor: nextCursor));
    unawaited(HapticFeedback.selectionClick());
  }

  void clearAll() {
    if (state.value.isEmpty) {
      return;
    }

    emit(state.copyWith(value: '', cursor: 0));
    unawaited(HapticFeedback.selectionClick());
  }

  void setCursor(int cursor) {
    final int next = _clampCursor(cursor, state.value.length);
    if (next == state.cursor) return;
    print('setCursor from=${state.cursor} to=$next');
    emit(state.copyWith(cursor: next));
  }

  Future<void> startVoice() async {
    if (state.mode != WearCodeInputMode.voice) return;

    _wantVoice = true;
    voiceLevel01.value = 0;
    final int session = ++_session;
    print('voice session started session=$session');

    emit(
      state.copyWith(
        voicePhase: WearVoicePhase.starting,
        clearVoiceError: true,
        clearRecognizedWords: true,
      ),
    );
    print('state -> starting');

    final bool hasPermission;
    try {
      hasPermission = await _voiceTypingService.requestPermission();
    } catch (error) {
      if (!_isCurrentSession(session)) {
        return;
      }
      _setErrorAndStop(
        _asUiError(error),
        reason: 'microphone_permission',
      );
      return;
    }

    if (!_isCurrentSession(session)) {
      return;
    }

    if (!hasPermission) {
      _setErrorAndStop(
        'Нет доступа к микрофону',
        reason: 'microphone_permission_denied',
      );
      return;
    }

    try {
      await _ensureVoicePrepared();
      if (!_isCurrentSession(session)) {
        return;
      }

      await _voiceTypingService.startSession();
      if (!_isCurrentSession(session)) {
        await _safeStopSession();
        return;
      }

      emit(state.copyWith(
        voicePhase: WearVoicePhase.listening,
        clearVoiceError: true,
      ));
    } catch (error) {
      if (!_isCurrentSession(session)) {
        return;
      }
      _setErrorAndStop(
        _asUiError(error),
        reason: 'start_session_failed',
      );
    }
  }

  Future<void> retryVoice() async {
    emit(state.copyWith(value: '', cursor: 0, clearVoiceError: true));
    await stopVoice();

    if (state.mode != WearCodeInputMode.voice) {
      return;
    }

    await startVoice();
  }

  Future<void> stopVoice() async {
    print('stopVoice() called');

    _wantVoice = false;
    _session++;

    _voiceLevel01.value = 0;

    await _safeStopSession();

    emit(state.copyWith(
      voicePhase: WearVoicePhase.idle,
      clearVoiceError: true,
    ));
  }

  bool _isCurrentSession(int session) {
    return _wantVoice && session == _session;
  }

  void _onVoiceResult(String recognizedText) {
    if (!_wantVoice || state.mode != WearCodeInputMode.voice) {
      return;
    }

    final String digits = _extractDigits(recognizedText);
    if (digits.isEmpty) {
      return;
    }

    final String next = _clipCode('${state.value}$digits');
    if (next == state.value) {
      return;
    }

    HapticFeedback.lightImpact();
    emit(state.copyWith(
      value: next,
      cursor: next.length,
      voicePhase: WearVoicePhase.listening,
      clearVoiceError: true,
    ));
  }

  void _onAudioLevel(double level01) {
    if (!_wantVoice || state.mode != WearCodeInputMode.voice) {
      return;
    }

    _voiceLevel01.value = level01.clamp(0.0, 1.0);
  }

  void _onVoiceError(Object error, StackTrace stackTrace) {
    if (!_wantVoice || state.mode != WearCodeInputMode.voice) {
      return;
    }

    _setErrorAndStop(
      _asUiError(error),
      reason: 'voice_stream_error',
    );
  }

  void _setErrorAndStop(
    String message, {
    required String reason,
  }) {
    _wantVoice = false;
    _session++;

    _voiceLevel01.value = 0;

    _safeStopSession();

    print('WearPrintCodeInputCubit: voice error ($reason): $message');

    emit(state.copyWith(
      voicePhase: WearVoicePhase.error,
      voiceError: message,
    ));
  }

  Future<void> _safeStopSession() async {
    try {
      await _voiceTypingService.stopSession();
    } catch (error) {
      print('WearPrintCodeInputCubit: stopVoice failed: $error');
    }
  }

  String _extractDigits(String value) {
    return value.replaceAll(RegExp(r'[^0-9]'), '');
  }

  String _clipCode(String value) {
    if (value.length <= _maxCodeLength) {
      return value;
    }
    return value.substring(0, _maxCodeLength);
  }

  String _asUiError(Object error) {
    final String raw = error.toString().trim();
    if (raw.isEmpty) {
      return 'Распознавание недоступно';
    }

    if (raw.startsWith('Exception: ')) {
      return raw.substring('Exception: '.length);
    }

    if (raw.startsWith('Bad state: ')) {
      return raw.substring('Bad state: '.length);
    }

    return raw;
  }

  int _resolveInsertCursor() {
    return _clampCursor(state.cursor, state.value.length);
  }

  int _clampCursor(int cursor, int max) {
    if (cursor < 0) return 0;
    if (cursor > max) return max;
    return cursor;
  }

  @override
  Future<void> close() async {
    await _resultSubscription?.cancel();
    await _audioLevelSubscription?.cancel();
    await stopVoice();
    _voiceLevel01.dispose();
    return super.close();
  }
}

class _ParsedNumber {
  const _ParsedNumber({
    required this.digits,
    required this.consumed,
  });

  final String digits;
  final int consumed;
}
