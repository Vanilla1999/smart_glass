import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:smart_glasses/modules/wear/domain/service/voice_typing/audio_stream_service.dart';
import 'package:vosk_flutter_service/vosk_flutter.dart' as vosk;

class SpeechRecognitionService {
  static const int _sampleRate = 16000;
  static const String _modelAssetPath = 'assets/vosk-model-small-ru-0.22.zip';
  static const int _slowRecognizerLatencyMs = 150;
  static const int _slowAudioQueueDelayMs = 200;

  SpeechRecognitionService({
    AudioStreamService? audioStreamService,
    List<String> commandGrammar = const <String>[],
  })  : _audioStream = audioStreamService ?? AudioStreamService(),
        _commandGrammar = List<String>.unmodifiable(
          commandGrammar
              .map((String item) => item.trim())
              .where((String item) => item.isNotEmpty),
        ),
        _freeTextEnabled = commandGrammar.isEmpty;

  final vosk.VoskFlutterPlugin _vosk = vosk.VoskFlutterPlugin.instance();
  final vosk.ModelLoader _modelLoader = vosk.ModelLoader();
  final AudioStreamService _audioStream;
  final List<String> _commandGrammar;

  final StreamController<String> _commandResultsController =
      StreamController<String>.broadcast();
  final StreamController<String> _commandPartialResultsController =
      StreamController<String>.broadcast();
  final StreamController<String> _freeTextResultsController =
      StreamController<String>.broadcast();
  final StreamController<String> _freeTextPartialResultsController =
      StreamController<String>.broadcast();

  String _commandPartialText = '';
  String _freeTextPartialText = '';
  bool _freeTextEnabled;
  bool _isSessionActive = false;
  bool _isListening = false;
  Future<void> _commandAudioProcessing = Future<void>.value();
  Future<void> _freeTextAudioProcessing = Future<void>.value();
  Future<void> _lifecycleOperation = Future<void>.value();
  int _freeTextEpoch = 0;
  int? _lastProcessedChunkAtMillis;
  final _RecognitionMetrics _commandMetrics = _RecognitionMetrics();
  final _RecognitionMetrics _freeTextMetrics = _RecognitionMetrics();

  vosk.Model? _model;
  vosk.Recognizer? _commandRecognizer;
  vosk.Recognizer? _freeTextRecognizer;

  Stream<String> get commandResultsStream => _commandResultsController.stream;
  Stream<String> get commandPartialResultsStream =>
      _commandPartialResultsController.stream;
  Stream<String> get freeTextResultsStream => _freeTextResultsController.stream;
  Stream<String> get freeTextPartialResultsStream =>
      _freeTextPartialResultsController.stream;
  bool get isPrepared =>
      _model != null &&
      _freeTextRecognizer != null &&
      (_commandGrammar.isEmpty || _commandRecognizer != null);
  bool get isSessionActive => _isSessionActive;
  bool get isListening => _isListening;
  bool get usesFreeTextRecognition => _freeTextEnabled;
  int? get lastAudioChunkAtMillis => _audioStream.lastChunkAtMillis;
  int? get lastNonSilentAudioChunkAtMillis =>
      _audioStream.lastNonSilentChunkAtMillis;
  int? get continuousZeroAudioStartedAtMillis =>
      _audioStream.continuousZeroAudioStartedAtMillis;
  AudioStreamService get audioStreamService => _audioStream;

  Future<void> setFreeTextEnabled(bool enabled) {
    if (_freeTextEnabled == enabled) {
      print(
        '[SpeechRecognitionService] setFreeTextEnabled skipped '
        'enabled=$enabled',
      );
      return Future<void>.value();
    }

    _freeTextEnabled = enabled;
    final int epoch = ++_freeTextEpoch;
    _freeTextPartialText = '';
    print(
      '[SpeechRecognitionService] freeText enabled=$enabled epoch=$epoch',
    );
    if (!enabled || _freeTextRecognizer == null) {
      return Future<void>.value();
    }

    final Future<void> next = _freeTextAudioProcessing.then((_) async {
      if (!_freeTextEnabled || epoch != _freeTextEpoch) return;
      await _freeTextRecognizer?.reset();
    });
    _freeTextAudioProcessing = next.catchError(
      (Object error, StackTrace stackTrace) {
        print(
          '[SpeechRecognitionService] freeText reset error: '
          '$error\n$stackTrace',
        );
      },
    );
    return next;
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
    if (!isPrepared) {
      print('[SpeechRecognitionService] prepare create recognizers begin');
      await _createRecognizers();
      print('[SpeechRecognitionService] prepare create recognizers done');
    } else {
      print('[SpeechRecognitionService] prepare recognizers reset begin');
      await _resetRecognizers();
      print('[SpeechRecognitionService] prepare recognizers reset done');
    }

    _isSessionActive = false;
    _commandPartialText = '';
    _freeTextPartialText = '';
    print('[SpeechRecognitionService] prepare done');
  }

  Future<void> startSession() async {
    if (!isPrepared || _model == null) {
      throw StateError(
        'Сначала подготовьте модель вызовом prepare() перед стартом сессии.',
      );
    }

    await _resetRecognizers();
    _commandPartialText = '';
    _freeTextPartialText = '';
    _isSessionActive = true;
  }

  Future<void> stopSession() async {
    _isSessionActive = false;
    _commandPartialText = '';
    _freeTextPartialText = '';
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
    _lifecycleOperation = next.catchError(
      (Object error, StackTrace stackTrace) {
        print(
          '[SpeechRecognitionService] lifecycle operation failed: '
          '$label error=$error\n$stackTrace',
        );
      },
    );
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
    final bool hasPermission = await requestMicrophonePermission();
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
      _lastProcessedChunkAtMillis = null;
      _commandMetrics.reset();
      _freeTextMetrics.reset();

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
    final int processingStartedAt = DateTime.now().millisecondsSinceEpoch;
    await Future.wait<void>(<Future<void>>[
      _commandAudioProcessing,
      _freeTextAudioProcessing,
    ]);
    final int processingFinishedAt = DateTime.now().millisecondsSinceEpoch;
    print(
      '[SpeechRecognitionService] wait audio processing durationMs='
      '${processingFinishedAt - processingStartedAt}',
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
    return 'SpeechRecognitionService{isListening=$_isListening, '
        'isSessionActive=$_isSessionActive, isPrepared=$isPrepared, '
        'freeTextEnabled=$_freeTextEnabled, '
        'commandRecognizer=${_commandRecognizer != null}, '
        'freeTextRecognizer=${_freeTextRecognizer != null}, '
        'command=${_commandMetrics.describe()}, '
        'freeText=${_freeTextMetrics.describe()}, '
        'lastProcessedAgeMs=$lastProcessedAgeMs, audio=$audio}';
  }

  void _onAudioChunk(Uint8List bytes) {
    _enqueueCommandChunk(bytes);
    if (_freeTextEnabled) {
      _enqueueFreeTextChunk(bytes, _freeTextEpoch);
    }
  }

  Future<void> processAudioChunk(Uint8List bytes) async {
    final List<Future<void>> processing = <Future<void>>[];
    if (_commandRecognizer != null) {
      processing.add(_enqueueCommandChunk(bytes));
    }
    if (_freeTextEnabled) {
      processing.add(_enqueueFreeTextChunk(bytes, _freeTextEpoch));
    }
    await Future.wait<void>(processing);
  }

  Future<void> _enqueueCommandChunk(Uint8List bytes) {
    if (_commandRecognizer == null) return Future<void>.value();
    final int queuedAt = DateTime.now().millisecondsSinceEpoch;
    final Future<void> next = _commandAudioProcessing.then(
      (_) => _processRecognizerChunk(
        source: _RecognitionSource.command,
        recognizer: _commandRecognizer!,
        bytes: bytes,
        queuedAt: queuedAt,
        epoch: null,
      ),
    );
    _commandAudioProcessing = next.catchError(
      (Object error, StackTrace stackTrace) {
        print('[SpeechRecognitionService] command chunk error: $error');
      },
    );
    return next;
  }

  Future<void> _enqueueFreeTextChunk(Uint8List bytes, int epoch) {
    if (_freeTextRecognizer == null) return Future<void>.value();
    final int queuedAt = DateTime.now().millisecondsSinceEpoch;
    final Future<void> next = _freeTextAudioProcessing.then(
      (_) => _processRecognizerChunk(
        source: _RecognitionSource.freeText,
        recognizer: _freeTextRecognizer!,
        bytes: bytes,
        queuedAt: queuedAt,
        epoch: epoch,
      ),
    );
    _freeTextAudioProcessing = next.catchError(
      (Object error, StackTrace stackTrace) {
        print('[SpeechRecognitionService] freeText chunk error: $error');
      },
    );
    return next;
  }

  Future<void> _processRecognizerChunk({
    required _RecognitionSource source,
    required vosk.Recognizer recognizer,
    required Uint8List bytes,
    required int queuedAt,
    required int? epoch,
  }) async {
    if (!_isSessionActive) {
      throw StateError(
        'Сессия распознавания не запущена. Вызовите startSession() перед обработкой аудио.',
      );
    }
    if (bytes.lengthInBytes < 2 || !_canProcess(source, epoch)) return;

    final _RecognitionMetrics metrics = _metrics(source);
    metrics.processedChunks++;
    final int processingStartedAt = DateTime.now().millisecondsSinceEpoch;
    final int queueDelayMs = processingStartedAt - queuedAt;
    metrics.recordQueueDelay(queueDelayMs, _slowAudioQueueDelayMs);
    _lastProcessedChunkAtMillis = processingStartedAt;
    if (metrics.processedChunks == 1 || metrics.processedChunks % 200 == 0) {
      print(
        '[SpeechRecognitionService] processing source=${source.label} '
        'chunk#${metrics.processedChunks} bytes=${bytes.lengthInBytes} '
        'queueDelayMs=$queueDelayMs epoch=$epoch',
      );
    } else if (queueDelayMs > _slowAudioQueueDelayMs) {
      print(
        '[SpeechRecognitionService] slow audio queue source=${source.label} '
        'chunk#${metrics.processedChunks} queueDelayMs=$queueDelayMs '
        'epoch=$epoch currentEpoch=$_freeTextEpoch',
      );
    }

    final int startedAt = DateTime.now().millisecondsSinceEpoch;
    final bool isResultReady = await recognizer.acceptWaveformBytes(bytes);
    final int acceptedAt = DateTime.now().millisecondsSinceEpoch;
    final int latencyMs = acceptedAt - startedAt;
    metrics.recordRecognizerLatency(latencyMs, _slowRecognizerLatencyMs);
    if (latencyMs > _slowRecognizerLatencyMs) {
      print(
        '[SpeechRecognitionService] slow recognizer source=${source.label} '
        'latencyMs=$latencyMs queueDelayMs=$queueDelayMs '
        'chunk#${metrics.processedChunks}',
      );
    }

    if (isResultReady) {
      final int resultStartedAt = DateTime.now().millisecondsSinceEpoch;
      final String resultJson = await recognizer.getResult();
      final int resultFinishedAt = DateTime.now().millisecondsSinceEpoch;
      final String resultText = _extractText(
        resultJson,
        preferredKeys: const <String>['text'],
      );
      if (resultText.isNotEmpty) {
        final int finishedAt = DateTime.now().millisecondsSinceEpoch;
        print(
          '[VOSK][FINAL][${source.label}] $resultText at $finishedAt '
          '(queueDelayMs=$queueDelayMs, acceptMs=$latencyMs, '
          'resultMs=${resultFinishedAt - resultStartedAt}, '
          'chunkTotalMs=${finishedAt - startedAt})',
        );
        _emitResult(source, resultText, epoch: epoch, partial: false);
      }
      _setPartialText(source, '');
      return;
    }

    final int partialStartedAt = DateTime.now().millisecondsSinceEpoch;
    final String partialJson = await recognizer.getPartialResult();
    final int partialFinishedAt = DateTime.now().millisecondsSinceEpoch;
    final String partialText = _extractText(
      partialJson,
      preferredKeys: const <String>['partial'],
    );
    if (partialText.isNotEmpty && partialText != _partialText(source)) {
      final int finishedAt = DateTime.now().millisecondsSinceEpoch;
      print(
        '[VOSK][PARTIAL][${source.label}] $partialText at $finishedAt '
        '(queueDelayMs=$queueDelayMs, acceptMs=$latencyMs, '
        'partialMs=${partialFinishedAt - partialStartedAt}, '
        'chunkTotalMs=${finishedAt - startedAt})',
      );
      _emitResult(source, partialText, epoch: epoch, partial: true);
    }
    _setPartialText(source, partialText);
  }

  bool _canProcess(_RecognitionSource source, int? epoch) {
    return switch (source) {
      _RecognitionSource.command => _commandRecognizer != null,
      _RecognitionSource.freeText =>
        _freeTextEnabled && epoch == _freeTextEpoch,
    };
  }

  void _emitResult(
    _RecognitionSource source,
    String text, {
    required int? epoch,
    required bool partial,
  }) {
    if (!_canProcess(source, epoch)) {
      print(
        '[SpeechRecognitionService] suppress stale result '
        'source=${source.label} epoch=$epoch currentEpoch=$_freeTextEpoch',
      );
      return;
    }
    final StreamController<String> controller = switch ((source, partial)) {
      (_RecognitionSource.command, false) => _commandResultsController,
      (_RecognitionSource.command, true) => _commandPartialResultsController,
      (_RecognitionSource.freeText, false) => _freeTextResultsController,
      (_RecognitionSource.freeText, true) => _freeTextPartialResultsController,
    };
    if (!controller.isClosed) controller.add(text);
  }

  Future<void> _ensureModelInitialized() async {
    if (_model != null) {
      print('[SpeechRecognitionService] model already initialized');
      return;
    }
    print(
      '[SpeechRecognitionService] load model asset begin path=$_modelAssetPath',
    );
    final String modelPath = await _modelLoader.loadFromAssets(_modelAssetPath);
    print('[SpeechRecognitionService] load model asset done path=$modelPath');
    print('[SpeechRecognitionService] create model begin');
    _model = await _vosk.createModel(modelPath);
    print('[SpeechRecognitionService] create model done');
  }

  Future<void> _createRecognizers() async {
    final vosk.Model? model = _model;
    if (model == null) throw StateError('Vosk модель не инициализирована.');

    _freeTextRecognizer ??= await _vosk.createRecognizer(
      model: model,
      sampleRate: _sampleRate,
    );
    if (_commandGrammar.isEmpty || _commandRecognizer != null) return;

    final int startedAt = DateTime.now().millisecondsSinceEpoch;
    final vosk.Recognizer recognizer = await _vosk.createRecognizer(
      model: model,
      sampleRate: _sampleRate,
    );
    try {
      print(
        '[SpeechRecognitionService] applying command grammar '
        'size=${_commandGrammar.length}',
      );
      await recognizer.setGrammar(_commandGrammar);
    } catch (_) {
      await recognizer.dispose();
      rethrow;
    }
    _commandRecognizer = recognizer;
    final int finishedAt = DateTime.now().millisecondsSinceEpoch;
    print(
      '[SpeechRecognitionService] command recognizer ready '
      'durationMs=${finishedAt - startedAt}',
    );
  }

  Future<void> _resetRecognizers() async {
    await Future.wait<void>(<Future<void>>[
      if (_commandRecognizer != null) _commandRecognizer!.reset(),
      if (_freeTextRecognizer != null) _freeTextRecognizer!.reset(),
    ]);
  }

  Future<void> dispose() async {
    _isListening = false;
    _isSessionActive = false;
    await Future.wait<void>(<Future<void>>[
      _commandAudioProcessing.catchError(
        (Object error, StackTrace stackTrace) {},
      ),
      _freeTextAudioProcessing.catchError(
        (Object error, StackTrace stackTrace) {},
      ),
    ]);
    await _audioStream.dispose();
    await _commandRecognizer?.dispose();
    await _freeTextRecognizer?.dispose();
    _commandRecognizer = null;
    _freeTextRecognizer = null;
    _model?.dispose();
    _model = null;
    await _commandResultsController.close();
    await _commandPartialResultsController.close();
    await _freeTextResultsController.close();
    await _freeTextPartialResultsController.close();
  }

  _RecognitionMetrics _metrics(_RecognitionSource source) {
    return switch (source) {
      _RecognitionSource.command => _commandMetrics,
      _RecognitionSource.freeText => _freeTextMetrics,
    };
  }

  String _partialText(_RecognitionSource source) {
    return switch (source) {
      _RecognitionSource.command => _commandPartialText,
      _RecognitionSource.freeText => _freeTextPartialText,
    };
  }

  void _setPartialText(_RecognitionSource source, String value) {
    switch (source) {
      case _RecognitionSource.command:
        _commandPartialText = value;
      case _RecognitionSource.freeText:
        _freeTextPartialText = value;
    }
  }

  String _extractText(String json, {required List<String> preferredKeys}) {
    final dynamic decoded;
    try {
      decoded = jsonDecode(json);
    } catch (_) {
      throw FormatException('Vosk вернул невалидный JSON: $json');
    }
    if (decoded is! Map<dynamic, dynamic>) {
      throw const FormatException('Vosk вернул неожиданный формат результата.');
    }
    for (final String key in preferredKeys) {
      final dynamic value = decoded[key];
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }
    for (final String key in const <String>['text', 'partial']) {
      final dynamic value = decoded[key];
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }
    return '';
  }
}

enum _RecognitionSource {
  command('command'),
  freeText('freeText');

  const _RecognitionSource(this.label);

  final String label;
}

class _RecognitionMetrics {
  int processedChunks = 0;
  int queueTotalMs = 0;
  int queueMaxMs = 0;
  int slowQueueChunks = 0;
  int recognizerChunks = 0;
  int recognizerTotalMs = 0;
  int recognizerMaxMs = 0;
  int slowRecognizerChunks = 0;

  void recordQueueDelay(int value, int slowThreshold) {
    queueTotalMs += value;
    if (value > queueMaxMs) queueMaxMs = value;
    if (value > slowThreshold) slowQueueChunks++;
  }

  void recordRecognizerLatency(int value, int slowThreshold) {
    recognizerChunks++;
    recognizerTotalMs += value;
    if (value > recognizerMaxMs) recognizerMaxMs = value;
    if (value > slowThreshold) slowRecognizerChunks++;
  }

  String describe() {
    final int queueAverage =
        processedChunks == 0 ? 0 : queueTotalMs ~/ processedChunks;
    final int recognizerAverage =
        recognizerChunks == 0 ? 0 : recognizerTotalMs ~/ recognizerChunks;
    return '{processedChunks=$processedChunks, queueAvgMs=$queueAverage, '
        'queueMaxMs=$queueMaxMs, slowQueueChunks=$slowQueueChunks, '
        'recognizerAvgMs=$recognizerAverage, '
        'recognizerMaxMs=$recognizerMaxMs, '
        'slowRecognizerChunks=$slowRecognizerChunks}';
  }

  void reset() {
    processedChunks = 0;
    queueTotalMs = 0;
    queueMaxMs = 0;
    slowQueueChunks = 0;
    recognizerChunks = 0;
    recognizerTotalMs = 0;
    recognizerMaxMs = 0;
    slowRecognizerChunks = 0;
  }
}
