import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_typing/audio_stream_service.dart';
import 'package:vosk_flutter_service/vosk_flutter.dart' as vosk;

class SpeechRecognitionService {
  static const int _sampleRate = 16000;
  static const String _modelAssetPath = 'assets/vosk-model-small-ru-0.22.zip';
  static const int _slowRecognizerLatencyMs = 150;
  static const int _slowAudioQueueDelayMs = 200;

  final vosk.VoskFlutterPlugin _vosk = vosk.VoskFlutterPlugin.instance();
  final vosk.ModelLoader _modelLoader = vosk.ModelLoader();
  final StreamController<String> _resultsController =
      StreamController<String>.broadcast();
  final StreamController<String> _partialResultsController =
      StreamController<String>.broadcast();
  final AudioStreamService _audioStream;

  String _freePartialText = '';
  String _grammarPartialText = '';
  bool _isSessionActive = false;
  bool _isListening = false;
  Future<void> _audioProcessing = Future<void>.value();
  Future<void> _lifecycleOperation = Future<void>.value();
  int _processedChunks = 0;
  int? _lastProcessedChunkAtMillis;
  int _audioQueueTotalDelayMs = 0;
  int _audioQueueMaxDelayMs = 0;
  int _slowAudioQueueChunks = 0;
  int _recognizerChunks = 0;
  int _recognizerTotalLatencyMs = 0;
  int _recognizerMaxLatencyMs = 0;
  int _slowRecognizerChunks = 0;
  int _recognitionModeEpoch = 0;
  List<String>? _recognitionGrammar;

  vosk.Model? _model;
  vosk.Recognizer? _freeTextRecognizer;
  vosk.Recognizer? _grammarRecognizer;
  List<String>? _grammarRecognizerGrammar;

  SpeechRecognitionService({AudioStreamService? audioStreamService})
      : _audioStream = audioStreamService ?? AudioStreamService();

  Stream<String> get resultsStream => _resultsController.stream;
  Stream<String> get partialResultsStream => _partialResultsController.stream;
  bool get isPrepared => _model != null && _freeTextRecognizer != null;
  bool get isSessionActive => _isSessionActive;
  bool get isListening => _isListening;
  bool get usesFreeTextRecognition => _recognitionGrammar == null;
  int? get lastAudioChunkAtMillis => _audioStream.lastChunkAtMillis;
  int? get lastNonSilentAudioChunkAtMillis =>
      _audioStream.lastNonSilentChunkAtMillis;
  AudioStreamService get audioStreamService => _audioStream;

  Future<void> setRecognitionGrammar(List<String>? grammar) async {
    final int startedAt = DateTime.now().millisecondsSinceEpoch;
    final List<String>? filtered = grammar
        ?.map((String item) => item.trim())
        .where((String item) => item.isNotEmpty)
        .toList(growable: false);
    final List<String>? next = filtered == null || filtered.isEmpty
        ? null
        : List<String>.unmodifiable(filtered);
    final bool nextUsesFreeText = next == null;

    await _runLifecycleOperation('setRecognitionGrammar', () async {
      final bool recognizerMatches = next == null ||
          (_grammarRecognizer != null &&
              listEquals(_grammarRecognizerGrammar, next));
      if (listEquals(_recognitionGrammar, next) && recognizerMatches) {
        print(
          '[SpeechRecognitionService] setRecognitionGrammar skipped '
          'mode=${nextUsesFreeText ? 'freeText' : 'grammar'} '
          'size=${next?.length ?? 0}',
        );
        return;
      }

      if (_model == null) {
        _publishRecognitionMode(next);
        return;
      }

      await _serializeWithAudioProcessing(() async {
        if (next == null) {
          await _freeTextRecognizer?.reset();
          _freePartialText = '';
        } else {
          await _createGrammarRecognizer(next);
          await _grammarRecognizer!.reset();
          _grammarPartialText = '';
        }
        _publishRecognitionMode(next);
      });
    });
    final int finishedAt = DateTime.now().millisecondsSinceEpoch;
    print(
      '[SpeechRecognitionService] setRecognitionGrammar done '
      'mode=${nextUsesFreeText ? 'freeText' : 'grammar'} '
      'totalMs=${finishedAt - startedAt} listening=$_isListening',
    );
  }

  Future<bool> requestMicrophonePermission() {
    return _audioStream.requestPermission();
  }

  Future<void> prepare() {
    return _runLifecycleOperation('prepare', _prepareUnlocked);
  }

  Future<void> _prepareUnlocked() async {
    print('[SpeechRecognitionService] prepare begin isPrepared=$isPrepared');
    await _ensureModelInitialized();
    if (_freeTextRecognizer == null) {
      print('[SpeechRecognitionService] prepare create recognizers begin');
      await _createRecognizers();
      print('[SpeechRecognitionService] prepare create recognizers done');
    } else {
      print('[SpeechRecognitionService] prepare recognizers reset begin');
      await _resetRecognizers();
      print('[SpeechRecognitionService] prepare recognizers reset done');
    }

    _isSessionActive = false;
    _freePartialText = '';
    _grammarPartialText = '';
    print('[SpeechRecognitionService] prepare done');
  }

  Future<void> startSession() async {
    if (_freeTextRecognizer == null || _model == null) {
      throw StateError(
        'Сначала подготовьте модель вызовом prepare() перед стартом сессии.',
      );
    }

    await _resetRecognizers();
    _freePartialText = '';
    _grammarPartialText = '';
    _isSessionActive = true;
  }

  Future<void> stopSession() async {
    _isSessionActive = false;
    _freePartialText = '';
    _grammarPartialText = '';
  }

  Future<void> startListening() async {
    await _runLifecycleOperation('startListening', _startListeningUnlocked);
  }

  Future<void> stopListening() async {
    await _runLifecycleOperation('stopListening', _stopListeningUnlocked);
  }

  Future<void> restartListening({required String reason}) async {
    await _runLifecycleOperation('restartListening reason=$reason', () async {
      print('[SpeechRecognitionService] restartListening reason=$reason');
      await _stopListeningUnlocked();
      await _startListeningUnlocked();
    });
  }

  Future<void> _runLifecycleOperation(
    String label,
    Future<void> Function() operation,
  ) {
    final Future<void> next = _lifecycleOperation.then((_) async {
      print('[SpeechRecognitionService] lifecycle operation begin: $label');
      await operation();
      print('[SpeechRecognitionService] lifecycle operation done: $label');
    });
    _lifecycleOperation =
        next.catchError((Object error, StackTrace stackTrace) {
      print(
        '[SpeechRecognitionService] lifecycle operation failed: '
        '$label error=$error\n$stackTrace',
      );
    });
    return next;
  }

  Future<void> _startListeningUnlocked() async {
    print(
      '[SpeechRecognitionService] startListening called, '
      '_isListening=$_isListening, diagnostics=${await diagnostics()}',
    );
    if (_isListening) {
      print('[SpeechRecognitionService] already listening, skipping');
      return;
    }
    print('[SpeechRecognitionService] requesting microphone permission...');
    final int permissionStartedAt = DateTime.now().millisecondsSinceEpoch;
    final hasPermission = await requestMicrophonePermission();
    final int permissionFinishedAt = DateTime.now().millisecondsSinceEpoch;
    print('[SpeechRecognitionService] permission result: $hasPermission');
    print(
      '[SpeechRecognitionService] permission durationMs='
      '${permissionFinishedAt - permissionStartedAt}',
    );
    if (!hasPermission) {
      throw StateError('Microphone permission denied');
    }
    print('[SpeechRecognitionService] preparing model...');
    if (!isPrepared) {
      final int prepareStartedAt = DateTime.now().millisecondsSinceEpoch;
      await _prepareUnlocked();
      final int prepareFinishedAt = DateTime.now().millisecondsSinceEpoch;
      print(
        '[SpeechRecognitionService] prepare durationMs='
        '${prepareFinishedAt - prepareStartedAt}',
      );
    }
    try {
      print('[SpeechRecognitionService] starting session...');
      await startSession();
      _processedChunks = 0;
      _lastProcessedChunkAtMillis = null;
      _resetPerformanceMetrics();

      print('[SpeechRecognitionService] adding audio callback...');
      _audioStream.addDataCallback(_onAudioChunk);
      print('[SpeechRecognitionService] starting audio stream...');
      final int audioStartStartedAt = DateTime.now().millisecondsSinceEpoch;
      await _audioStream.start(
        onError: (Object error, StackTrace stackTrace) {
          print('[AudioStream] error: $error');
        },
      );
      final int audioStartFinishedAt = DateTime.now().millisecondsSinceEpoch;
      print(
        '[SpeechRecognitionService] audio stream start durationMs='
        '${audioStartFinishedAt - audioStartStartedAt}',
      );
      _isListening = true;
      print('[SpeechRecognitionService] now listening: ${await diagnostics()}');
    } catch (_) {
      _audioStream.removeDataCallback(_onAudioChunk);
      await _audioStream.stop();
      await stopSession();
      _isListening = false;
      rethrow;
    }
  }

  Future<void> _stopListeningUnlocked() async {
    print(
      '[SpeechRecognitionService] stopListening called, '
      '_isListening=$_isListening, diagnostics=${await diagnostics()}',
    );
    if (!_isListening && !_isSessionActive && !_audioStream.isRunning) {
      _audioStream.removeDataCallback(_onAudioChunk);
      return;
    }
    print('[SpeechRecognitionService] removing audio callback...');
    _audioStream.removeDataCallback(_onAudioChunk);
    final int audioProcessingStartedAt = DateTime.now().millisecondsSinceEpoch;
    await _audioProcessing;
    final int audioProcessingFinishedAt = DateTime.now().millisecondsSinceEpoch;
    print(
      '[SpeechRecognitionService] wait audio processing durationMs='
      '${audioProcessingFinishedAt - audioProcessingStartedAt}',
    );
    final int audioStopStartedAt = DateTime.now().millisecondsSinceEpoch;
    await _audioStream.stop();
    final int audioStopFinishedAt = DateTime.now().millisecondsSinceEpoch;
    print(
      '[SpeechRecognitionService] audio stream stop durationMs='
      '${audioStopFinishedAt - audioStopStartedAt}',
    );
    await stopSession();
    _isListening = false;
    print(
        '[SpeechRecognitionService] stopped listening: ${await diagnostics()}');
  }

  Future<String> diagnostics() async {
    final int now = DateTime.now().millisecondsSinceEpoch;
    final int? lastProcessedAgeMs = _lastProcessedChunkAtMillis == null
        ? null
        : now - _lastProcessedChunkAtMillis!;
    final String audio = await _audioStream.diagnostics();
    final bool usesFreeText = _recognitionGrammar == null;
    final int queueAverageMs =
        _processedChunks == 0 ? 0 : _audioQueueTotalDelayMs ~/ _processedChunks;
    final int recognizerAverageMs = _recognizerChunks == 0
        ? 0
        : _recognizerTotalLatencyMs ~/ _recognizerChunks;
    return 'SpeechRecognitionService{isListening=$_isListening, '
        'isSessionActive=$_isSessionActive, isPrepared=$isPrepared, '
        'mode=${usesFreeText ? 'freeText' : 'grammar'}, '
        'freeRecognizer=${_freeTextRecognizer != null}, '
        'grammarRecognizer=${_grammarRecognizer != null}, '
        'processedChunks=$_processedChunks, '
        'queueAvgMs=$queueAverageMs, queueMaxMs=$_audioQueueMaxDelayMs, '
        'slowQueueChunks=$_slowAudioQueueChunks, '
        'recognizerAvgMs=$recognizerAverageMs, '
        'recognizerMaxMs=$_recognizerMaxLatencyMs, '
        'slowRecognizerChunks=$_slowRecognizerChunks, '
        'lastProcessedAgeMs=$lastProcessedAgeMs, audio=$audio}';
  }

  void _onAudioChunk(Uint8List bytes) {
    final int modeEpoch = _recognitionModeEpoch;
    final int queuedAt = DateTime.now().millisecondsSinceEpoch;
    _audioProcessing = _audioProcessing
        .then((_) => _processAudioChunk(
              bytes,
              modeEpoch: modeEpoch,
              queuedAt: queuedAt,
            ))
        .catchError((Object error, StackTrace stackTrace) {
      print('[SpeechRecognitionService] processAudioChunk error: $error');
    });
  }

  Future<void> dispose() async {
    _isListening = false;
    _isSessionActive = false;
    await _audioProcessing.catchError((Object error, StackTrace stackTrace) {});
    await _audioStream.dispose();
    await _disposeRecognizers();
    _model?.dispose();
    _model = null;
    await _resultsController.close();
    await _partialResultsController.close();
  }

  Future<void> processAudioChunk(Uint8List bytes) {
    return _processAudioChunk(
      bytes,
      modeEpoch: _recognitionModeEpoch,
      queuedAt: DateTime.now().millisecondsSinceEpoch,
    );
  }

  Future<void> _processAudioChunk(
    Uint8List bytes, {
    required int modeEpoch,
    required int queuedAt,
  }) async {
    if (!_isSessionActive) {
      throw StateError(
        'Сессия распознавания не запущена. Вызовите startSession() перед обработкой аудио.',
      );
    }

    if (bytes.lengthInBytes < 2) {
      return;
    }
    if (modeEpoch != _recognitionModeEpoch) {
      print(
        '[SpeechRecognitionService] drop stale audio chunk '
        'epoch=$modeEpoch currentEpoch=$_recognitionModeEpoch',
      );
      return;
    }
    _processedChunks++;
    final int processingStartedAt = DateTime.now().millisecondsSinceEpoch;
    final int queueDelayMs = processingStartedAt - queuedAt;
    _audioQueueTotalDelayMs += queueDelayMs;
    if (queueDelayMs > _audioQueueMaxDelayMs) {
      _audioQueueMaxDelayMs = queueDelayMs;
    }
    if (queueDelayMs > _slowAudioQueueDelayMs) {
      _slowAudioQueueChunks++;
    }
    _lastProcessedChunkAtMillis = processingStartedAt;
    if (_processedChunks == 1 || _processedChunks % 200 == 0) {
      print(
        '[SpeechRecognitionService] processing chunk#$_processedChunks '
        'bytes=${bytes.lengthInBytes} at=$_lastProcessedChunkAtMillis '
        'queueDelayMs=$queueDelayMs epoch=$modeEpoch',
      );
    } else if (queueDelayMs > _slowAudioQueueDelayMs) {
      print(
        '[SpeechRecognitionService] slow audio queue chunk#$_processedChunks '
        'queueDelayMs=$queueDelayMs epoch=$modeEpoch currentEpoch=$_recognitionModeEpoch',
      );
    }
    final freeTextRecognizer = _freeTextRecognizer;
    if (freeTextRecognizer == null) {
      throw StateError(
        'Распознаватель не инициализирован. Вызовите prepare() перед использованием.',
      );
    }

    final bool usesFreeText = _recognitionGrammar == null;
    final grammarRecognizer = _grammarRecognizer;
    if (usesFreeText) {
      _logActiveRecognizer(
        source: _RecognitionSource.freeText,
        modeEpoch: modeEpoch,
        queueDelayMs: queueDelayMs,
      );
      await _processRecognizer(
        source: _RecognitionSource.freeText,
        recognizer: freeTextRecognizer,
        bytes: bytes,
        emitResults: true,
        modeEpoch: modeEpoch,
        queueDelayMs: queueDelayMs,
      );
      return;
    }

    if (grammarRecognizer == null ||
        !listEquals(_grammarRecognizerGrammar, _recognitionGrammar)) {
      _logActiveRecognizer(
        source: _RecognitionSource.grammar,
        modeEpoch: modeEpoch,
        queueDelayMs: queueDelayMs,
        fallback: true,
      );
      return;
    }

    _logActiveRecognizer(
      source: _RecognitionSource.grammar,
      modeEpoch: modeEpoch,
      queueDelayMs: queueDelayMs,
    );
    await _processRecognizer(
      source: _RecognitionSource.grammar,
      recognizer: grammarRecognizer,
      bytes: bytes,
      emitResults: true,
      modeEpoch: modeEpoch,
      queueDelayMs: queueDelayMs,
    );
  }

  Future<void> _processRecognizer({
    required _RecognitionSource source,
    required vosk.Recognizer recognizer,
    required Uint8List bytes,
    required bool emitResults,
    required int modeEpoch,
    required int queueDelayMs,
  }) async {
    final t0 = DateTime.now().millisecondsSinceEpoch;
    final isResultReady = await recognizer.acceptWaveformBytes(bytes);
    final int acceptedAt = DateTime.now().millisecondsSinceEpoch;
    final int latencyMs = acceptedAt - t0;
    _recognizerChunks++;
    _recognizerTotalLatencyMs += latencyMs;
    if (latencyMs > _recognizerMaxLatencyMs) {
      _recognizerMaxLatencyMs = latencyMs;
    }
    if (latencyMs > _slowRecognizerLatencyMs) {
      _slowRecognizerChunks++;
      print(
        '[SpeechRecognitionService] slow recognizer source=${source.label} '
        'latencyMs=$latencyMs queueDelayMs=$queueDelayMs '
        'chunk#$_processedChunks emitResults=$emitResults',
      );
    }
    if (isResultReady) {
      final int resultStartedAt = DateTime.now().millisecondsSinceEpoch;
      final resultJson = await recognizer.getResult();
      final int resultFinishedAt = DateTime.now().millisecondsSinceEpoch;
      final resultText = _extractText(resultJson, preferredKeys: const [
        'text',
      ]);
      if (resultText.isNotEmpty) {
        final t1 = DateTime.now().millisecondsSinceEpoch;
        print(
          '[VOSK][FINAL][${source.label}] $resultText at $t1 '
          '(queueDelayMs=$queueDelayMs, acceptMs=$latencyMs, '
          'resultMs=${resultFinishedAt - resultStartedAt}, '
          'chunkTotalMs=${t1 - t0}, emitResults=$emitResults)',
        );
        if (_canEmitRecognizerResult(source, emitResults, modeEpoch) &&
            !_resultsController.isClosed) {
          _resultsController.add(resultText);
        }
      }
      _setPartialText(source, '');
      return;
    }

    final int partialStartedAt = DateTime.now().millisecondsSinceEpoch;
    final partialResultJson = await recognizer.getPartialResult();
    final int partialFinishedAt = DateTime.now().millisecondsSinceEpoch;
    final partialText = _extractText(partialResultJson, preferredKeys: const [
      'partial',
    ]);
    if (partialText.isNotEmpty && partialText != _partialText(source)) {
      final t1 = DateTime.now().millisecondsSinceEpoch;
      print(
        '[VOSK][PARTIAL][${source.label}] $partialText at $t1 '
        '(queueDelayMs=$queueDelayMs, acceptMs=$latencyMs, '
        'partialMs=${partialFinishedAt - partialStartedAt}, '
        'chunkTotalMs=${t1 - t0}, emitResults=$emitResults)',
      );
      if (_canEmitRecognizerResult(source, emitResults, modeEpoch) &&
          !_partialResultsController.isClosed) {
        _partialResultsController.add(partialText);
      }
    }
    _setPartialText(source, partialText);
  }

  Future<void> _ensureModelInitialized() async {
    if (_model != null) {
      print('[SpeechRecognitionService] model already initialized');
      return;
    }

    print(
        '[SpeechRecognitionService] load model asset begin path=$_modelAssetPath');
    final modelPath = await _modelLoader.loadFromAssets(_modelAssetPath);
    print('[SpeechRecognitionService] load model asset done path=$modelPath');
    print('[SpeechRecognitionService] create model begin');
    _model = await _vosk.createModel(modelPath);
    print('[SpeechRecognitionService] create model done');
  }

  Future<void> _createRecognizers() async {
    await _createFreeTextRecognizer();
    final List<String>? grammar = _recognitionGrammar;
    if (grammar != null && grammar.isNotEmpty) {
      await _createGrammarRecognizer(grammar);
    }
  }

  Future<void> _createFreeTextRecognizer() async {
    final model = _model;
    if (model == null) {
      throw StateError('Vosk модель не инициализирована.');
    }

    _freeTextRecognizer ??= await _vosk.createRecognizer(
      model: model,
      sampleRate: _sampleRate,
    );
  }

  Future<void> _createGrammarRecognizer(List<String> grammar) async {
    final model = _model;
    if (model == null) {
      throw StateError('Vosk модель не инициализирована.');
    }
    if (grammar.isEmpty) {
      return;
    }
    if (_grammarRecognizer != null) {
      if (listEquals(_grammarRecognizerGrammar, grammar)) {
        return;
      }
    }

    final int startedAt = DateTime.now().millisecondsSinceEpoch;
    final recognizer = await _vosk.createRecognizer(
      model: model,
      sampleRate: _sampleRate,
    );
    try {
      print(
        '[SpeechRecognitionService] applying grammar size=${grammar.length}',
      );
      await recognizer.setGrammar(grammar);
    } catch (_) {
      await recognizer.dispose();
      rethrow;
    }
    final vosk.Recognizer? previous = _grammarRecognizer;
    _grammarRecognizer = recognizer;
    _grammarRecognizerGrammar = List<String>.unmodifiable(grammar);
    await previous?.dispose();
    final int finishedAt = DateTime.now().millisecondsSinceEpoch;
    print(
      '[SpeechRecognitionService] grammar recognizer ready '
      'durationMs=${finishedAt - startedAt}',
    );
  }

  Future<void> _disposeGrammarRecognizer() async {
    final recognizer = _grammarRecognizer;
    _grammarRecognizer = null;
    _grammarRecognizerGrammar = null;
    if (recognizer != null) {
      await recognizer.dispose();
    }
  }

  Future<void> _disposeRecognizers() async {
    final freeTextRecognizer = _freeTextRecognizer;
    _freeTextRecognizer = null;
    if (freeTextRecognizer != null) {
      await freeTextRecognizer.dispose();
    }
    await _disposeGrammarRecognizer();
  }

  Future<void> _serializeWithAudioProcessing(
    Future<void> Function() operation,
  ) async {
    final Future<void> next = _audioProcessing.then((_) => operation());
    _audioProcessing = next.catchError((Object error, StackTrace stackTrace) {
      print('[SpeechRecognitionService] serialized operation error: $error');
    });
    await next;
  }

  bool _canEmitRecognizerResult(
    _RecognitionSource source,
    bool requestedEmit,
    int modeEpoch,
  ) {
    if (!requestedEmit || modeEpoch != _recognitionModeEpoch) {
      print(
        '[SpeechRecognitionService] suppress recognizer result '
        'source=${source.label} requestedEmit=$requestedEmit '
        'resultEpoch=$modeEpoch currentEpoch=$_recognitionModeEpoch',
      );
      return false;
    }
    final bool usesFreeText = _recognitionGrammar == null;
    final bool canEmit = switch (source) {
      _RecognitionSource.freeText => usesFreeText,
      _RecognitionSource.grammar => !usesFreeText &&
          _grammarRecognizer != null &&
          listEquals(_grammarRecognizerGrammar, _recognitionGrammar),
    };
    if (!canEmit) {
      print(
        '[SpeechRecognitionService] suppress recognizer result '
        'source=${source.label} activeMode=${usesFreeText ? 'freeText' : 'grammar'} '
        'grammarRecognizer=${_grammarRecognizer != null}',
      );
    }
    return canEmit;
  }

  void _logActiveRecognizer({
    required _RecognitionSource source,
    required int modeEpoch,
    required int queueDelayMs,
    bool fallback = false,
  }) {
    if (_processedChunks != 1 && _processedChunks % 200 != 0 && !fallback) {
      return;
    }
    print(
      '[SpeechRecognitionService] active recognizer chunk#$_processedChunks '
      'source=${source.label} mode=${_recognitionGrammar == null ? 'freeText' : 'grammar'} '
      'epoch=$modeEpoch currentEpoch=$_recognitionModeEpoch '
      'queueDelayMs=$queueDelayMs fallback=$fallback',
    );
  }

  Future<void> _resetRecognizers() async {
    await Future.wait<void>([
      if (_freeTextRecognizer != null) _freeTextRecognizer!.reset(),
      if (_grammarRecognizer != null) _grammarRecognizer!.reset(),
    ]);
  }

  void _publishRecognitionMode(List<String>? grammar) {
    final bool previousUsesFreeText = _recognitionGrammar == null;
    _recognitionGrammar = grammar;
    _recognitionModeEpoch++;
    print(
      '[SpeechRecognitionService] recognition mode '
      '${previousUsesFreeText ? 'freeText' : 'grammar'} -> '
      '${grammar == null ? 'freeText' : 'grammar'} '
      'size=${grammar?.length ?? 0} epoch=$_recognitionModeEpoch',
    );
  }

  void _resetPerformanceMetrics() {
    _audioQueueTotalDelayMs = 0;
    _audioQueueMaxDelayMs = 0;
    _slowAudioQueueChunks = 0;
    _recognizerChunks = 0;
    _recognizerTotalLatencyMs = 0;
    _recognizerMaxLatencyMs = 0;
    _slowRecognizerChunks = 0;
  }

  String _partialText(_RecognitionSource source) {
    return switch (source) {
      _RecognitionSource.freeText => _freePartialText,
      _RecognitionSource.grammar => _grammarPartialText,
    };
  }

  void _setPartialText(_RecognitionSource source, String value) {
    switch (source) {
      case _RecognitionSource.freeText:
        _freePartialText = value;
      case _RecognitionSource.grammar:
        _grammarPartialText = value;
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

enum _RecognitionSource {
  freeText('freeText'),
  grammar('grammar');

  const _RecognitionSource(this.label);

  final String label;
}
