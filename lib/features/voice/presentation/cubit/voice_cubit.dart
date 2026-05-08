import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:record/record.dart' as rec;
import 'package:vosk_flutter_service/vosk_flutter.dart' as vosk;
import 'package:smart_glasses/core/constants/app_constants.dart';
import 'package:smart_glasses/core/services/method_channel_service.dart';
import 'package:smart_glasses/features/voice/presentation/cubit/voice_state.dart';

/// Cubit for managing voice recognition
class VoiceCubit extends Cubit<VoiceState> {
  VoiceCubit(this._methodChannelService) : super(const VoiceIdle());

  final MethodChannelService _methodChannelService;
  final _vosk = vosk.VoskFlutterPlugin.instance();
  final _record = rec.AudioRecorder();
  vosk.Recognizer? _recognizer;
  vosk.Model? _model;
  StreamSubscription<Uint8List>? _audioSubscription;

  DateTime _lastUiUpdate = DateTime.now();
  DateTime _lastSentTime = DateTime.now();
  DateTime _lastPartialRequest = DateTime.now();
  String _lastSentText = '';
  String _lastUiText = '';
  bool _isProcessingAudioChunk = false;

  /// Initialize voice recognition
  Future<void> init() async {
    emit(const VoiceInitializing());
    try {
      print('Initializing Vosk...');
      final modelPath = await vosk.ModelLoader().loadFromAssets(
        'assets/vosk-model-small-ru-0.22.zip',
      );
      print('Vosk model loaded: $modelPath');
      _model = await _vosk.createModel(modelPath);
      _recognizer = await _vosk.createRecognizer(
        model: _model!,
        sampleRate: 16000,
      );
      print('Vosk recognizer created');
      emit(const VoiceReady());
    } catch (e) {
      print('Vosk init error: $e');
      emit(VoiceError(e.toString()));
    }
  }

  /// Start listening for voice input
  Future<void> startListening() async {
    if (_recognizer == null) {
      print('Recognizer not ready');
      return;
    }

    final hasPermission = await _record.hasPermission();
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
    _isProcessingAudioChunk = false;
    emit(const VoiceListening());

    try {
      final audioStream = await _record.startStream(
        const rec.RecordConfig(
          encoder: rec.AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
        ),
      );
      print('Recording started');

      _audioSubscription = audioStream.listen((chunk) async {
        // Backpressure: skip chunk if still processing previous one
        if (_isProcessingAudioChunk) {
          return;
        }

        _isProcessingAudioChunk = true;
        try {
          final accepted = await _recognizer!.acceptWaveformBytes(chunk);

          String text = '';
          if (accepted) {
            // Final result - always fetch
            final result = await _recognizer!.getResult();
            text = _extractRecognitionText(result);
          } else {
            // Partial result - throttle requests
            final now = DateTime.now();
            if (now.difference(_lastPartialRequest).inMilliseconds > AppConstants.voicePartialResultPollingMs) {
              _lastPartialRequest = now;
              final partial = await _recognizer!.getPartialResult();
              text = _extractRecognitionText(partial);
            }
          }

          if (text.isEmpty) return;

          final now = DateTime.now();

          // Update UI with deduplication
          if (text != _lastUiText &&
              now.difference(_lastUiUpdate).inMilliseconds > AppConstants.voiceUiUpdateDelayMs) {
            _lastUiUpdate = now;
            _lastUiText = text;
            emit(VoiceRecognized(text));
          }

          // Send to glasses with deduplication
          if (text != _lastSentText &&
              now.difference(_lastSentTime).inMilliseconds > AppConstants.voiceSendDelayMs) {
            _lastSentTime = now;
            _lastSentText = text;
            _methodChannelService.updateRecognizedText(text);
          }
        } finally {
          _isProcessingAudioChunk = false;
        }
      });
    } catch (e) {
      print('Error starting Vosk: $e');
      emit(VoiceError(e.toString()));
    }
  }

  /// Stop listening for voice input
  Future<void> stopListening() async {
    print('Stopping Vosk...');
    await _audioSubscription?.cancel();
    _audioSubscription = null;
    await _record.stop();

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

  /// Extract text from recognition result
  String _extractRecognitionText(String rawResult) {
    // Fast path: RegExp
    final match = RegExp(r'"(?:text|partial)"\s*:\s*"([^"]*)"')
        .firstMatch(rawResult);
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
  Future<void> close() {
    _audioSubscription?.cancel();
    return super.close();
  }
}
