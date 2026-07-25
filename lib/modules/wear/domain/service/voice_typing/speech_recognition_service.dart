import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:smart_glasses/modules/wear/domain/service/voice_command/voice_command_parser_service.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_typing/audio_stream_service.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_typing/segmented_recognition_result.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_typing/speech_segmenter.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_typing/voice_device_profile.dart';
import 'package:vosk_flutter_service/vosk_flutter.dart' as vosk;

class VoiceRecognitionCaptureEpoch {
  int _current = 0;

  int get current => _current;

  int begin() => ++_current;

  void invalidate() => _current++;

  bool isCurrent(int value) => value == _current;
}

class VoiceRecognitionProcessingQueue {
  const VoiceRecognitionProcessingQueue({
    this.stopTimeout = const Duration(seconds: 2),
  });

  final Duration stopTimeout;

  Future<bool> waitForIdle({
    required Future<void> command,
    required Future<void> freeText,
  }) {
    return Future.any<bool>(<Future<bool>>[
      Future.wait<void>(<Future<void>>[command, freeText]).then((_) => true),
      Future<bool>.delayed(stopTimeout, () => false),
    ]);
  }
}

class SpeechRecognitionService {
  static const int _sampleRate = 16000;
  static const String _modelAssetPath = 'assets/vosk-model-small-ru-0.22.zip';
  static const int _slowRecognizerLatencyMs = 150;
  static const int _slowAudioQueueDelayMs = 200;

  SpeechRecognitionService({
    AudioStreamService? audioStreamService,
    List<String> commandGrammar = const <String>[],
    SpeechSegmenter? speechSegmenter,
  })  : _audioStreamOverride = audioStreamService,
        _speechSegmenter = speechSegmenter ?? SpeechSegmenter(),
        _commandGrammar = List<String>.unmodifiable(
          commandGrammar
              .map((String item) => item.trim())
              .where((String item) => item.isNotEmpty),
        ),
        _freeTextEnabled = commandGrammar.isEmpty;

  late final vosk.VoskFlutterPlugin _vosk = vosk.VoskFlutterPlugin.instance();
  final vosk.ModelLoader _modelLoader = vosk.ModelLoader();
  final AudioStreamService? _audioStreamOverride;
  late final AudioStreamService _audioStream =
      _audioStreamOverride ?? AudioStreamService();
  final List<String> _commandGrammar;
  final SpeechSegmenter _speechSegmenter;
  final VoiceCommandParserService _commandParser = VoiceCommandParserService();

  final StreamController<SegmentedRecognitionResult>
      _segmentedResultsController =
      StreamController<SegmentedRecognitionResult>.broadcast(sync: true);
  final StreamController<SpeechSegmentEnded> _segmentEndedController =
      StreamController<SpeechSegmentEnded>.broadcast(sync: true);
  final StreamController<SpeechSegmentStarted> _segmentStartedController =
      StreamController<SpeechSegmentStarted>.broadcast(sync: true);

  String _commandPartialText = '';
  String _freeTextPartialText = '';
  bool _freeTextEnabled;
  bool _isSessionActive = false;
  bool _isListening = false;
  Future<void> _commandAudioProcessing = Future<void>.value();
  Future<void> _freeTextAudioProcessing = Future<void>.value();
  Future<void> _lifecycleOperation = Future<void>.value();
  int _freeTextEpoch = 0;
  final VoiceRecognitionCaptureEpoch _captureEpoch =
      VoiceRecognitionCaptureEpoch();
  void Function(Uint8List raw, Uint8List boosted)? _audioCallback;
  int? _lastProcessedChunkAtMillis;
  final List<_PcmFrame> _preRollFrames = <_PcmFrame>[];
  static const int _preRollFrameCount = 10; // 200 ms at 20 ms VAD frames.
  final _RecognitionMetrics _commandMetrics = _RecognitionMetrics();
  final _RecognitionMetrics _freeTextMetrics = _RecognitionMetrics();

  vosk.Model? _model;
  vosk.Recognizer? _commandRecognizer;
  vosk.Recognizer? _freeTextRecognizer;

  Stream<SegmentedRecognitionResult> get segmentedResultsStream =>
      _segmentedResultsController.stream;
  Stream<SpeechSegmentEnded> get segmentEndedStream =>
      _segmentEndedController.stream;
  Stream<SpeechSegmentStarted> get segmentStartedStream =>
      _segmentStartedController.stream;
  bool get isPrepared =>
      _model != null &&
      _freeTextRecognizer != null &&
      (_commandGrammar.isEmpty || _commandRecognizer != null);
  bool get isSessionActive => _isSessionActive;
  bool get isListening => _isListening;
  bool get isCaptureRunning => _audioStream.isRunning;
  bool get usesFreeTextRecognition => _freeTextEnabled;
  int? get lastAudioChunkAtMillis => _audioStream.lastChunkAtMillis;
  int? get lastNonSilentAudioChunkAtMillis =>
      _audioStream.lastNonSilentChunkAtMillis;
  int? get continuousZeroAudioStartedAtMillis =>
      _audioStream.continuousZeroAudioStartedAtMillis;
  int get audioChunksReceived => _audioStream.chunksReceived;
  int get audioCaptureId => _audioStream.captureId;
  int? get captureStartedAtMillis => _audioStream.captureStartedAtMillis;
  AudioStreamService get audioStreamService => _audioStream;
  VoiceDeviceProfile get deviceProfile => _audioStream.deviceProfile;

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
      await _audioStream.recreateRecorder();
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
      final int captureEpoch = _captureEpoch.begin();
      _speechSegmenter.configure(
        speechOnRms: _audioStream.deviceProfile.vadSpeechOnRms,
        speechOffRms: _audioStream.deviceProfile.vadSpeechOffRms,
      );
      _speechSegmenter.begin(captureEpoch);
      _preRollFrames.clear();
      _lastProcessedChunkAtMillis = null;
      _commandMetrics.reset();
      _freeTextMetrics.reset();

      print('[SpeechRecognitionService] adding audio callback...');
      _audioCallback = (Uint8List raw, Uint8List boosted) =>
          _onAudioChunk(raw, boosted, captureEpoch);
      _audioStream.addPcmCallback(_audioCallback!);
      print('[SpeechRecognitionService] starting audio stream...');
      final int audioStartStartedAt = DateTime.now().millisecondsSinceEpoch;
      await _audioStream.start(
        onError: (Object error, StackTrace stackTrace) {
          print('[AudioStream] error: $error');
          _isListening = false;
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
      _removeAudioCallback();
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
      _removeAudioCallback();
      return;
    }
    print('[SpeechRecognitionService] removing audio callback...');
    _captureEpoch.invalidate();
    _speechSegmenter.end(_captureEpoch.current - 1);
    _preRollFrames.clear();
    _removeAudioCallback();
    final int processingStartedAt = DateTime.now().millisecondsSinceEpoch;
    final bool processingFinished =
        await const VoiceRecognitionProcessingQueue().waitForIdle(
      command: _commandAudioProcessing,
      freeText: _freeTextAudioProcessing,
    );
    if (!processingFinished) {
      // The old epoch cannot emit results after this point. Drop its blocked
      // serial queues and recognizers so a new capture never shares native
      // recognizers with a blocked operation from the old capture.
      final Future<void> commandProcessing = _commandAudioProcessing;
      final Future<void> freeTextProcessing = _freeTextAudioProcessing;
      _commandAudioProcessing = Future<void>.value();
      _freeTextAudioProcessing = Future<void>.value();
      await _replaceRecognizersAfterTimedOutProcessing(
        commandProcessing: commandProcessing,
        freeTextProcessing: freeTextProcessing,
      );
      print('[SpeechRecognitionService] audio processing stop timed out');
    }
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

  void _onAudioChunk(
    Uint8List rawBytes,
    Uint8List boostedBytes,
    int captureEpoch,
  ) {
    if (!_isSessionActive || !_captureEpoch.isCurrent(captureEpoch)) return;
    for (int offset = 0;
        offset < rawBytes.lengthInBytes;
        offset += _vadFrameBytes) {
      final int end =
          (offset + _vadFrameBytes).clamp(0, rawBytes.lengthInBytes).toInt();
      _processAudioFrame(
        Uint8List.sublistView(rawBytes, offset, end),
        Uint8List.sublistView(boostedBytes, offset, end),
        captureEpoch,
      );
    }
  }

  static const int _vadFrameBytes = 640; // 20 ms at 16 kHz mono PCM16.

  void _processAudioFrame(
    Uint8List rawBytes,
    Uint8List boostedBytes,
    int captureEpoch,
  ) {
    final SpeechSegment? segment = _speechSegmenter.add(rawBytes, captureEpoch);
    if (segment == null) {
      _preRollFrames.add(_PcmFrame(boostedBytes));
      if (_preRollFrames.length > _preRollFrameCount) {
        _preRollFrames.removeAt(0);
      }
      return;
    }
    if (segment.started) {
      _emitSegmentStarted(segment);
      for (final _PcmFrame frame in _preRollFrames) {
        _enqueueSegmentFrame(frame.boosted, captureEpoch, segment);
      }
      _preRollFrames.clear();
    }
    _enqueueSegmentFrame(boostedBytes, captureEpoch, segment);
    if (segment.isEndpoint) {
      unawaited(_finishSegment(segment, captureEpoch).catchError(
        (Object error, StackTrace stackTrace) {
          print('[SpeechRecognitionService] segment finish error: $error');
        },
      ));
    }
  }

  void _enqueueSegmentFrame(
    Uint8List boostedBytes,
    int captureEpoch,
    SpeechSegment segment,
  ) {
    _enqueueCommandChunk(boostedBytes, captureEpoch, segment);
    if (_freeTextEnabled) {
      _enqueueFreeTextChunk(
        boostedBytes,
        _freeTextEpoch,
        captureEpoch,
        segment,
      );
    }
  }

  Future<void> processAudioChunk(Uint8List bytes) async {
    final int captureEpoch = _captureEpoch.current;
    final SpeechSegment? segment = _speechSegmenter.add(bytes, captureEpoch);
    if (segment == null) return;
    if (segment.started) _emitSegmentStarted(segment);
    final List<Future<void>> processing = <Future<void>>[];
    if (_commandRecognizer != null) {
      processing.add(_enqueueCommandChunk(bytes, captureEpoch, segment));
    }
    if (_freeTextEnabled) {
      processing.add(
        _enqueueFreeTextChunk(bytes, _freeTextEpoch, captureEpoch, segment),
      );
    }
    await Future.wait<void>(processing);
    if (segment.isEndpoint) await _finishSegment(segment, captureEpoch);
  }

  Future<void> _enqueueCommandChunk(
    Uint8List bytes,
    int captureEpoch,
    SpeechSegment segment,
  ) {
    if (_commandRecognizer == null) return Future<void>.value();
    final int queuedAt = DateTime.now().millisecondsSinceEpoch;
    final Future<void> next = _commandAudioProcessing.then(
      (_) => _processRecognizerChunk(
        source: _RecognitionSource.command,
        recognizer: _commandRecognizer!,
        bytes: bytes,
        queuedAt: queuedAt,
        epoch: null,
        captureEpoch: captureEpoch,
        segment: segment,
      ),
    );
    _commandAudioProcessing = next.catchError(
      (Object error, StackTrace stackTrace) {
        print('[SpeechRecognitionService] command chunk error: $error');
      },
    );
    return next;
  }

  Future<void> _enqueueFreeTextChunk(
    Uint8List bytes,
    int epoch,
    int captureEpoch,
    SpeechSegment segment,
  ) {
    if (_freeTextRecognizer == null) return Future<void>.value();
    final int queuedAt = DateTime.now().millisecondsSinceEpoch;
    final Future<void> next = _freeTextAudioProcessing.then(
      (_) => _processRecognizerChunk(
        source: _RecognitionSource.freeText,
        recognizer: _freeTextRecognizer!,
        bytes: bytes,
        queuedAt: queuedAt,
        epoch: epoch,
        captureEpoch: captureEpoch,
        segment: segment,
      ),
    );
    _freeTextAudioProcessing = next.catchError(
      (Object error, StackTrace stackTrace) {
        print('[SpeechRecognitionService] freeText chunk error: $error');
      },
    );
    return next;
  }

  Future<void> _finishSegment(SpeechSegment segment, int captureEpoch) async {
    final List<Future<void>> lanes = <Future<void>>[];
    if (_commandRecognizer != null) {
      final Future<void> next = _commandAudioProcessing.then(
        (_) => _closeRecognizerSegment(
          source: _RecognitionSource.command,
          recognizer: _commandRecognizer!,
          epoch: null,
          captureEpoch: captureEpoch,
          segment: segment,
        ),
      );
      _commandAudioProcessing = next.catchError(
        (Object error, StackTrace stackTrace) {
          print(
              '[SpeechRecognitionService] command segment close error: $error');
        },
      );
      lanes.add(next);
    }
    if (_freeTextEnabled && _freeTextRecognizer != null) {
      final int epoch = _freeTextEpoch;
      final Future<void> next = _freeTextAudioProcessing.then(
        (_) => _closeRecognizerSegment(
          source: _RecognitionSource.freeText,
          recognizer: _freeTextRecognizer!,
          epoch: epoch,
          captureEpoch: captureEpoch,
          segment: segment,
        ),
      );
      _freeTextAudioProcessing = next.catchError(
        (Object error, StackTrace stackTrace) {
          print(
              '[SpeechRecognitionService] freeText segment close error: $error');
        },
      );
      lanes.add(next);
    }
    Object? commandLaneError;
    Object? freeTextLaneError;
    if (lanes.isNotEmpty) {
      final List<Object?> errors = await Future.wait<Object?>(
        lanes.map((Future<void> lane) async {
          try {
            await lane;
            return null;
          } catch (error, stackTrace) {
            print('[SpeechRecognitionService] segment lane close error: '
                '$error\n$stackTrace');
            return error;
          }
        }),
      );
      if (_commandRecognizer != null && errors.isNotEmpty) {
        commandLaneError = errors.first;
      }
      if (_freeTextEnabled && _freeTextRecognizer != null) {
        freeTextLaneError = errors.last;
      }
    }
    if (_captureEpoch.isCurrent(captureEpoch) &&
        !_segmentEndedController.isClosed) {
      _segmentEndedController.add(SpeechSegmentEnded(
        captureEpoch: captureEpoch,
        segmentId: segment.segmentId,
        endChunkId: segment.lastChunkId,
        commandLaneCompleted: commandLaneError == null,
        freeTextLaneCompleted: freeTextLaneError == null,
        commandLaneError: commandLaneError,
        freeTextLaneError: freeTextLaneError,
      ));
    }
  }

  void _emitSegmentStarted(SpeechSegment segment) {
    if (_segmentStartedController.isClosed) return;
    _segmentStartedController.add(SpeechSegmentStarted(
      captureEpoch: segment.captureEpoch,
      segmentId: segment.segmentId,
      startChunkId: segment.lastChunkId,
    ));
  }

  Future<void> _closeRecognizerSegment({
    required _RecognitionSource source,
    required vosk.Recognizer recognizer,
    required int? epoch,
    required int captureEpoch,
    required SpeechSegment segment,
  }) async {
    if (!_canProcess(source, epoch, captureEpoch)) return;
    final String resultJson = await recognizer.getFinalResult();
    final String text = _extractText(
      resultJson,
      preferredKeys: const <String>['text'],
    );
    if (text.isNotEmpty) {
      _emitResult(
        source,
        text,
        epoch: epoch,
        captureEpoch: captureEpoch,
        partial: false,
        segment: segment,
      );
    }
    if (_canProcess(source, epoch, captureEpoch)) {
      await recognizer.reset();
      _setPartialText(source, '');
    }
  }

  Future<void> _processRecognizerChunk({
    required _RecognitionSource source,
    required vosk.Recognizer recognizer,
    required Uint8List bytes,
    required int queuedAt,
    required int? epoch,
    int? captureEpoch,
    required SpeechSegment segment,
  }) async {
    if (!_isSessionActive) {
      throw StateError(
        'Сессия распознавания не запущена. Вызовите startSession() перед обработкой аудио.',
      );
    }
    if (bytes.lengthInBytes < 2 || !_canProcess(source, epoch, captureEpoch)) {
      return;
    }

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
        _emitResult(
          source,
          resultText,
          epoch: epoch,
          captureEpoch: captureEpoch,
          partial: false,
          segment: segment,
        );
      }
      if (_canProcess(source, epoch, captureEpoch)) {
        _setPartialText(source, '');
      }
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
      _emitResult(
        source,
        partialText,
        epoch: epoch,
        captureEpoch: captureEpoch,
        partial: true,
        segment: segment,
      );
    }
    if (_canProcess(source, epoch, captureEpoch)) {
      _setPartialText(source, partialText);
    }
  }

  bool _canProcess(
    _RecognitionSource source,
    int? epoch,
    int? captureEpoch,
  ) {
    if (!_isSessionActive ||
        captureEpoch == null ||
        !_captureEpoch.isCurrent(captureEpoch)) {
      return false;
    }
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
    required int? captureEpoch,
    required bool partial,
    required SpeechSegment segment,
  }) {
    if (!_canProcess(source, epoch, captureEpoch)) {
      print(
        '[SpeechRecognitionService] suppress stale result '
        'source=${source.label} epoch=$epoch currentEpoch=$_freeTextEpoch',
      );
      return;
    }
    if (!_segmentedResultsController.isClosed) {
      _segmentedResultsController.add(SegmentedRecognitionResult(
        captureEpoch: segment.captureEpoch,
        segmentId: segment.segmentId,
        lane: source == _RecognitionSource.command
            ? RecognitionLane.command
            : RecognitionLane.freeText,
        kind: partial ? RecognitionKind.partial : RecognitionKind.finalResult,
        text: text,
        lastChunkId: segment.lastChunkId,
        parsedCommand: source == _RecognitionSource.command
            ? _commandParser.parseExact(text)
            : null,
      ));
    }
  }

  void _removeAudioCallback() {
    final void Function(Uint8List raw, Uint8List boosted)? callback =
        _audioCallback;
    if (callback != null) _audioStream.removePcmCallback(callback);
    _audioCallback = null;
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

  Future<void> _replaceRecognizersAfterTimedOutProcessing({
    required Future<void> commandProcessing,
    required Future<void> freeTextProcessing,
  }) async {
    final vosk.Recognizer? oldCommand = _commandRecognizer;
    final vosk.Recognizer? oldFreeText = _freeTextRecognizer;
    _commandRecognizer = null;
    _freeTextRecognizer = null;
    await _createRecognizers();

    unawaited(Future.wait<void>(<Future<void>>[
      commandProcessing.catchError((Object _, StackTrace __) {}),
      freeTextProcessing.catchError((Object _, StackTrace __) {}),
    ]).then((_) async {
      await oldCommand?.dispose();
      await oldFreeText?.dispose();
    }).catchError((Object error, StackTrace stackTrace) {
      print(
        '[SpeechRecognitionService] timed-out recognizer cleanup failed: '
        '$error\n$stackTrace',
      );
    }));
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
    await _segmentedResultsController.close();
    await _segmentEndedController.close();
    await _segmentStartedController.close();
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

class _PcmFrame {
  const _PcmFrame(this.boosted);

  final Uint8List boosted;
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
