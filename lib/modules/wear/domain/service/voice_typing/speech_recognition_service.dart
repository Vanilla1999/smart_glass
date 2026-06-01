import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:vosk_flutter_service/vosk_flutter.dart' as vosk;

class SpeechRecognitionService {
  static const int _sampleRate = 16000;
  static const String _modelAssetPath =
      'assets/vosk-model-small-ru-0.22.zip';

  final vosk.VoskFlutterPlugin _vosk = vosk.VoskFlutterPlugin.instance();
  final vosk.ModelLoader _modelLoader = vosk.ModelLoader();
  final StreamController<String> _resultsController =
      StreamController<String>.broadcast();

  String _partialText = '';
  bool _isSessionActive = false;

  vosk.Model? _model;
  vosk.Recognizer? _recognizer;

  Stream<String> get resultsStream => _resultsController.stream;
  bool get isPrepared => _model != null && _recognizer != null;
  bool get isSessionActive => _isSessionActive;

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

  Future<void> dispose() async {
    _isSessionActive = false;
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
    // print('[PROCESSING CHUNK]');
    final recognizer = _recognizer;
    if (recognizer == null) {
      throw StateError(
        'Распознаватель не инициализирован. Вызовите prepare() перед использованием.',
      );
    }

    final isResultReady = await recognizer.acceptWaveformBytes(bytes);
    if (isResultReady) {
      final resultJson = await recognizer.getResult();
      final resultText = _extractText(resultJson, preferredKeys: const [
        'text',
      ]);
      if (resultText.isNotEmpty) {
        print('[VOSK][FINAL] $resultText');
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
      print('[VOSK][PARTIAL] $partialText');
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
