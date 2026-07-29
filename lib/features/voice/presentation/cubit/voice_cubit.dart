import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:vosk_flutter_service/vosk_flutter.dart' as vosk;
import 'package:smart_glasses/core/constants/app_constants.dart';
import 'package:smart_glasses/core/services/method_channel_service.dart';
import 'package:smart_glasses/core/voice/native_voice_capture.dart';
import 'package:smart_glasses/features/voice/presentation/cubit/voice_state.dart';

/// Cubit for managing voice recognition
class VoiceCubit extends Cubit<VoiceState> {
  VoiceCubit(this._methodChannelService, this._nativeCapture)
      : super(const VoiceIdle());

  final MethodChannelService _methodChannelService;
  final _vosk = vosk.VoskFlutterPlugin.instance();
  final NativeVoiceCapture _nativeCapture;
  vosk.Recognizer? _recognizer;
  vosk.Model? _model;
  int? _leaseId;
  static const int _maxPendingPcmBytes = 64000;

  DateTime _lastUiUpdate = DateTime.now();
  DateTime _lastSentTime = DateTime.now();
  DateTime _lastPartialRequest = DateTime.now();
  String _lastSentText = '';
  String _lastUiText = '';
  int _pendingPcmBytes = 0;
  Future<void> _audioProcessing = Future<void>.value();
  Future<void> _lifecycleOperation = Future<void>.value();
  int _lifecycleGeneration = 0;
  int _captureGeneration = 0;

  /// Initialize voice recognition
  Future<void> init() async {
    emit(const VoiceInitializing());
    try {
      final modelPath = await vosk.ModelLoader().loadFromAssets(
        'assets/vosk-model-small-ru-0.22.zip',
      );
      _model = await _vosk.createModel(modelPath);
      _recognizer = await _vosk.createRecognizer(
        model: _model!,
        sampleRate: 16000,
      );
      emit(const VoiceReady());
    } catch (e) {
      emit(VoiceError(e.toString()));
    }
  }

  /// Start listening for voice input
  Future<void> startListening() {
    final int generation = ++_lifecycleGeneration;
    return _serializeLifecycle(() => _startListening(generation));
  }

  Future<void> _startListening(int generation) async {
    if (_leaseId != null) return;
    if (_recognizer == null) {
      print('Recognizer not ready');
      return;
    }

    final hasPermission = await _nativeCapture.requestPermission();
    if (generation != _lifecycleGeneration) return;
    if (!hasPermission) {
      print('No microphone permission');
      emit(const VoiceError('No microphone permission'));
      return;
    }

    print('Starting Vosk offline recognition...');
    _lastSentText = '';
    _lastSentTime = DateTime.now();
    _lastUiUpdate = DateTime.now();
    _lastPartialRequest = DateTime.now();
    _pendingPcmBytes = 0;
    emit(const VoiceListening());

    try {
      print('Recording started');

      final int captureGeneration = ++_captureGeneration;
      final int leaseId = await _nativeCapture.start(
        owner: NativeVoiceOwner.legacyRecognition,
        onPcm: (NativePcmPacket packet) =>
            _admitAudio(packet.bytes, captureGeneration),
      );
      if (generation != _lifecycleGeneration) {
        await _nativeCapture.stop(
          owner: NativeVoiceOwner.legacyRecognition,
          leaseId: leaseId,
        );
        return;
      }
      _leaseId = leaseId;
    } catch (e) {
      print('Error starting Vosk: $e');
      emit(VoiceError(e.toString()));
    }
  }

  bool _admitAudio(Uint8List chunk, int captureGeneration) {
    if (captureGeneration != _captureGeneration) return false;
    if (_pendingPcmBytes + chunk.lengthInBytes > _maxPendingPcmBytes) {
      emit(const VoiceError('RECOGNITION_BACKLOG'));
      unawaited(stopListening());
      return false;
    }
    _pendingPcmBytes += chunk.lengthInBytes;
    _audioProcessing = _audioProcessing.then((_) async {
      try {
        if (captureGeneration != _captureGeneration) return;
        final accepted = await _recognizer!.acceptWaveformBytes(chunk);

        String text = '';
        if (accepted) {
          // Final result - always fetch
          final result = await _recognizer!.getResult();
          text = _extractRecognitionText(result);
        } else {
          // Partial result - throttle requests
          final now = DateTime.now();
          if (now.difference(_lastPartialRequest).inMilliseconds >
              AppConstants.voicePartialResultPollingMs) {
            _lastPartialRequest = now;
            final partial = await _recognizer!.getPartialResult();
            text = _extractRecognitionText(partial);
          }
        }

        if (text.isEmpty || captureGeneration != _captureGeneration) return;

        final now = DateTime.now();

        // Update UI with deduplication
        if (text != _lastUiText &&
            now.difference(_lastUiUpdate).inMilliseconds >
                AppConstants.voiceUiUpdateDelayMs) {
          _lastUiUpdate = now;
          _lastUiText = text;
          emit(VoiceRecognized(text));
        }

        // Send to glasses with deduplication
        if (text != _lastSentText &&
            now.difference(_lastSentTime).inMilliseconds >
                AppConstants.voiceSendDelayMs) {
          _lastSentTime = now;
          _lastSentText = text;
          _methodChannelService.updateRecognizedText(text);
        }
      } finally {
        _pendingPcmBytes -= chunk.lengthInBytes;
      }
    }).catchError((Object error, StackTrace stackTrace) {
      print('Vosk chunk processing failed: $error\n$stackTrace');
      emit(VoiceError(error.toString()));
    });
    return true;
  }

  void handleNativeVoiceState(NativeVoiceStateEvent event) {
    if (event.owner != NativeVoiceOwner.legacyRecognition ||
        event.leaseId != _leaseId ||
        (event.state != NativeVoiceCaptureState.error &&
            event.state != NativeVoiceCaptureState.terminalAbandoned &&
            event.state != NativeVoiceCaptureState.disposed)) {
      return;
    }
    _leaseId = null;
    _captureGeneration++;
    emit(VoiceError(event.errorCode ?? 'NATIVE_CAPTURE_FAILED'));
  }

  /// Stop listening for voice input
  Future<void> stopListening() {
    _lifecycleGeneration++;
    _captureGeneration++;
    return _serializeLifecycle(_stopListening);
  }

  Future<void> _stopListening() async {
    print('Stopping Vosk...');
    final int? leaseId = _leaseId;
    if (leaseId != null) {
      await _nativeCapture.stop(
        owner: NativeVoiceOwner.legacyRecognition,
        leaseId: leaseId,
      );
    }
    _leaseId = null;
    await _audioProcessing;

    if (_recognizer != null) {
      final result = await _recognizer!.getFinalResult();
      final text = _extractRecognitionText(result);
      print('Vosk final result: $text');

      if (text.isNotEmpty) {
        emit(VoiceRecognized(text));
        _methodChannelService.updateRecognizedText(text);
      } else {
        emit(const VoiceReady());
      }
    }
  }

  Future<void> _serializeLifecycle(Future<void> Function() operation) {
    final Future<void> next = _lifecycleOperation.then((_) => operation());
    _lifecycleOperation = next.catchError((Object _, StackTrace __) {});
    return next;
  }

  /// Extract text from recognition result
  String _extractRecognitionText(String rawResult) {
    // Fast path: RegExp
    final match =
        RegExp(r'"(?:text|partial)"\s*:\s*"([^"]*)"').firstMatch(rawResult);
    if (match != null) {
      final text = match.group(1);
      if (text != null && text.isNotEmpty) return text;
    }

    // Fallback: jsonDecode
    try {
      final decoded = jsonDecode(rawResult);
      if (decoded is Map<String, dynamic>) {
        final text = decoded['text'];
        if (text is String && text.isNotEmpty) {
          return text;
        }

        final partial = decoded['partial'];
        if (partial is String) {
          return partial;
        }
      }
    } catch (_) {
      return rawResult;
    }

    return '';
  }

  @override
  Future<void> close() async {
    await stopListening();
    await super.close();
  }
}
