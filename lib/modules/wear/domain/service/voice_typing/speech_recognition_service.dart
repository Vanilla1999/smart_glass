import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_typing/audio_stream_service.dart';
import 'package:vosk_flutter_service/vosk_flutter.dart' as vosk;

class SpeechRecognitionService {
  static const int _sampleRate = 16000;
  static const String _modelAssetPath =
      'assets/vosk-model-small-ru-0.22.zip';

  final vosk.VoskFlutterPlugin _vosk = vosk.VoskFlutterPlugin.instance();
  final vosk.ModelLoader _modelLoader = vosk.ModelLoader();
  final StreamController<String> _resultsController =
      StreamController<String>.broadcast();
  final AudioStreamService _audioStream;

  String _partialText = '';
  bool _isSessionActive = false;
  bool _isListening = false;

  vosk.Model? _model;
  vosk.Recognizer? _recognizer;

  SpeechRecognitionService({AudioStreamService? audioStreamService})
      : _audioStream = audioStreamService ?? AudioStreamService();

  Stream<String> get resultsStream => _resultsController.stream;
  bool get isPrepared => _model != null && _recognizer != null;
  bool get isSessionActive => _isSessionActive;
  bool get isListening => _isListening;

  Future<bool> requestMicrophonePermission() {
    return _audioStream.requestPermission();
  }

  Future<void> prepare() async {
    await _ensureModelInitialized();
    if (_recognizer == null) {
      await _createRecognizer();
    } else {
      await _recognizer!.reset();
    }

    _isSessionActive = false;
    _partialText = '';
  }

  Future<void> startSession() async {
    final recognizer = _recognizer;
    if (recognizer == null || _model == null) {
      throw StateError(
        'Сначала подготовьте модель вызовом prepare() перед стартом сессии.',
      );
    }

    await recognizer.reset();
    _partialText = '';
    _isSessionActive = true;
  }

  Future<void> stopSession() async {
    _isSessionActive = false;
    _partialText = '';
  }

  Future<void> startListening() async {
    print('[SpeechRecognitionService] startListening called, _isListening=$_isListening');
    if (_isListening) {
      print('[SpeechRecognitionService] already listening, skipping');
      return;
    }
    print('[SpeechRecognitionService] requesting microphone permission...');
    final hasPermission = await requestMicrophonePermission();
    print('[SpeechRecognitionService] permission result: $hasPermission');
    if (!hasPermission) {
      throw StateError('Microphone permission denied');
    }
    print('[SpeechRecognitionService] preparing model...');
    if (!isPrepared) {
      await prepare();
    }
    print('[SpeechRecognitionService] starting session...');
    await startSession();

    print('[SpeechRecognitionService] adding audio callback...');
    _audioStream.addDataCallback(_onAudioChunk);
    print('[SpeechRecognitionService] starting audio stream...');
    await _audioStream.start(
      onError: (Object error, StackTrace stackTrace) {
        print('[AudioStream] error: $error');
      },
    );
    _isListening = true;
    print('[SpeechRecognitionService] now listening!');
  }

  Future<void> stopListening() async {
    print('[SpeechRecognitionService] stopListening called, _isListening=$_isListening');
    if (!_isListening) return;
    print('[SpeechRecognitionService] removing audio callback...');
    _audioStream.removeDataCallback(_onAudioChunk);
    await _audioStream.stop();
    await stopSession();
    _isListening = false;
    print('[SpeechRecognitionService] stopped listening');
  }

  void _onAudioChunk(Uint8List bytes) {
    try {
      processAudioChunk(bytes);
    } catch (error) {
      print('[SpeechRecognitionService] processAudioChunk error: $error');
    }
  }

  Future<void> dispose() async {
    _isListening = false;
    _isSessionActive = false;
    await _audioStream.dispose();
    await _disposeRecognizer();
    _model?.dispose();
    _model = null;
    await _resultsController.close();
  }

  Future<void> processAudioChunk(Uint8List bytes) async {
    if (!_isSessionActive) {
      throw StateError(
        'Сессия распознавания не запущена. Вызовите startSession() перед обработкой аудио.',
      );
    }

    if (bytes.lengthInBytes < 2) {
      return;
    }
    final recognizer = _recognizer;
    if (recognizer == null) {
      throw StateError(
        'Распознаватель не инициализирован. Вызовите prepare() перед использованием.',
      );
    }

    final t0 = DateTime.now().millisecondsSinceEpoch;
    final isResultReady = await recognizer.acceptWaveformBytes(bytes);
    if (isResultReady) {
      final resultJson = await recognizer.getResult();
      final resultText = _extractText(resultJson, preferredKeys: const [
        'text',
      ]);
      if (resultText.isNotEmpty) {
        final t1 = DateTime.now().millisecondsSinceEpoch;
        print('[VOSK][FINAL] $resultText at $t1 (vosk_latency: ${t1-t0}ms)');
        if (!_resultsController.isClosed) {
          _resultsController.add(resultText);
        }
      }
      _partialText = '';
      return;
    }

    final partialResultJson = await recognizer.getPartialResult();
    final partialText = _extractText(partialResultJson, preferredKeys: const [
      'partial',
    ]);
    if (partialText.isNotEmpty && partialText != _partialText) {
      final t1 = DateTime.now().millisecondsSinceEpoch;
      print('[VOSK][PARTIAL] $partialText at $t1');
    }
    _partialText = partialText;
  }

  Future<void> _ensureModelInitialized() async {
    if (_model != null) {
      return;
    }

    final modelPath = await _modelLoader.loadFromAssets(_modelAssetPath);
    _model = await _vosk.createModel(modelPath);
  }

  Future<void> _createRecognizer() async {
    final model = _model;
    if (model == null) {
      throw StateError('Vosk модель не инициализирована.');
    }

    _recognizer = await _vosk.createRecognizer(
      model: model,
      sampleRate: _sampleRate,
    );
  }

  Future<void> _disposeRecognizer() async {
    final recognizer = _recognizer;
    _recognizer = null;
    if (recognizer != null) {
      await recognizer.dispose();
    }
  }

  String _extractText(String json, {required List<String> preferredKeys}) {
    final dynamic decoded;
    try {
      decoded = jsonDecode(json);
    } catch (error) {
      throw FormatException('Vosk вернул невалидный JSON: $json');
    }
    // print('[GOT TEXT TO EXTRACT]: $decoded');
    if (decoded is! Map<dynamic, dynamic>) {
      throw const FormatException('Vosk вернул неожиданный формат результата.');
    }

    for (final key in preferredKeys) {
      final value = decoded[key];
      if (value is String && value.trim().isNotEmpty) {
        return value.trim();
      }
    }

    for (final key in const ['text', 'partial']) {
      final value = decoded[key];
      if (value is String && value.trim().isNotEmpty) {
        return value.trim();
      }
    }

    return '';
  }
}
