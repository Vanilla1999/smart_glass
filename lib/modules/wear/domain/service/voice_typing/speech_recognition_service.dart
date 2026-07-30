import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import 'package:smart_glasses/modules/wear/domain/service/voice_command/voice_command_parser_service.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/voice_action_catalog.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/command_recognition_event.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/wear_voice_command.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/voice_list_matcher.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/voice_utterance_coordinator.dart';
import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_typing/audio_stream_service.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_typing/free_text_pipeline_mode.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_typing/segmented_recognition_result.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_typing/speech_segmenter.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_typing/voice_device_profile.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_typing/voice_recognition_metrics.dart';
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

class VoiceRecognitionSegmentCloseGuard {
  const VoiceRecognitionSegmentCloseGuard({
    this.timeout = const Duration(seconds: 2),
  });

  final Duration timeout;

  Future<T> run<T>(Future<T> operation) => operation.timeout(timeout);
}

class VoicePcmBacklog {
  VoicePcmBacklog({this.maxBytes = 64000});

  final int maxBytes;
  int _pendingBytes = 0;

  int get pendingBytes => _pendingBytes;

  bool canAdmit(int bytes) => bytes >= 0 && _pendingBytes + bytes <= maxBytes;

  bool admit(int bytes) {
    if (!canAdmit(bytes)) return false;
    _pendingBytes += bytes;
    return true;
  }

  void complete(int bytes) {
    _pendingBytes = (_pendingBytes - bytes).clamp(0, maxBytes);
  }

  void reset() => _pendingBytes = 0;
}

abstract interface class VoiceRecognizer {
  Future<bool> acceptWaveformBytes(Uint8List bytes);
  Future<String> getPartialResult();
  Future<String> getResult();
  Future<String> getFinalResult();
  Future<void> reset();
  Future<void> setGrammar(List<String> grammar);
  Future<void> dispose();
}

typedef VoiceDynamicItemsProvider = VoiceDynamicItemsSnapshot Function(
  WearScreenId screen,
);

typedef VoiceRecognizerFactory = Future<VoiceRecognizer> Function(
  RecognitionLane lane,
  List<String> grammar,
);

class VoskVoiceRecognizer implements VoiceRecognizer {
  VoskVoiceRecognizer(this._recognizer);

  final vosk.Recognizer _recognizer;

  @override
  Future<bool> acceptWaveformBytes(Uint8List bytes) =>
      _recognizer.acceptWaveformBytes(bytes);
  @override
  Future<void> dispose() => _recognizer.dispose();
  @override
  Future<String> getFinalResult() => _recognizer.getFinalResult();
  @override
  Future<String> getPartialResult() => _recognizer.getPartialResult();
  @override
  Future<String> getResult() => _recognizer.getResult();
  @override
  Future<void> reset() => _recognizer.reset();
  @override
  Future<void> setGrammar(List<String> grammar) =>
      _recognizer.setGrammar(grammar);
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
    VoiceActionCatalog? actionCatalog,
    VoiceRecognizerFactory? recognizerFactory,
    Duration recognizerOperationTimeout = const Duration(seconds: 2),
    this.freeTextPipelineMode = FreeTextPipelineMode.replayOnly,
    int freeTextBacklogLimitBytes = 64000,
    VoiceDynamicItemsProvider? dynamicItemsProvider,
  })  : _audioStreamOverride = audioStreamService,
        _speechSegmenter = speechSegmenter ?? SpeechSegmenter(),
        _commandGrammar = List<String>.unmodifiable(
          commandGrammar
              .map((String item) => item.trim())
              .where((String item) => item.isNotEmpty),
        ),
        _freeTextEnabled = commandGrammar.isEmpty,
        _commandParser = VoiceCommandParserService(catalog: actionCatalog),
        _recognizerFactory = recognizerFactory,
        _segmentCloseGuard = VoiceRecognitionSegmentCloseGuard(
          timeout: recognizerOperationTimeout,
        ),
        _freeTextBacklog = VoicePcmBacklog(maxBytes: freeTextBacklogLimitBytes),
        _dynamicItemsProvider = dynamicItemsProvider ??
            ((WearScreenId _) => VoiceDynamicItemsSnapshot.empty);

  final FreeTextPipelineMode freeTextPipelineMode;

  late final vosk.VoskFlutterPlugin _vosk = vosk.VoskFlutterPlugin.instance();
  final vosk.ModelLoader _modelLoader = vosk.ModelLoader();
  final AudioStreamService? _audioStreamOverride;
  late final AudioStreamService _audioStream =
      _audioStreamOverride ?? AudioStreamService();
  List<String> _commandGrammar;
  final SpeechSegmenter _speechSegmenter;
  final VoiceCommandParserService _commandParser;
  final VoiceRecognizerFactory? _recognizerFactory;
  final VoiceRecognitionSegmentCloseGuard _segmentCloseGuard;
  final VoiceDynamicItemsProvider _dynamicItemsProvider;
  final VoiceUtteranceCoordinator _utteranceCoordinator =
      VoiceUtteranceCoordinator();

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
  int _commandUtteranceId = 1;
  int _commandPartialRevision = 0;
  int? _commandUtteranceStartedAtMillis;
  int _routeRevision = 1;
  int _grammarRevision = 1;
  WearScreenId _sourceScreen = WearScreenId.menu;
  final VoiceRecognitionCaptureEpoch _captureEpoch =
      VoiceRecognitionCaptureEpoch();
  final PcmFrameAccumulator _vadFrames = PcmFrameAccumulator(
    frameBytes: _vadFrameBytes,
  );
  bool Function(Uint8List raw, Uint8List boosted)? _audioCallback;
  int? _lastProcessedChunkAtMillis;
  final List<_PcmFrame> _preRollFrames = <_PcmFrame>[];
  static const int _preRollFrameCount = 10; // 200 ms at 20 ms VAD frames.
  final _RecognitionMetrics _commandMetrics = _RecognitionMetrics();
  final _RecognitionMetrics _freeTextMetrics = _RecognitionMetrics();
  final VoicePcmBacklog _commandBacklog = VoicePcmBacklog();
  final VoicePcmBacklog _freeTextBacklog;
  final VoiceRecognitionMetrics _voiceMetrics = VoiceRecognitionMetrics();
  final Map<int, List<String>> _liveFreeTextResults = <int, List<String>>{};
  final Map<int, String> _naturalCommandFinals = <int, String>{};
  final Map<int, _VoiceResultContext> _utteranceContexts =
      <int, _VoiceResultContext>{};
  final Set<int> _invalidLiveFreeTextUtterances = <int>{};
  final Map<int, String> _liveFreeTextInvalidReasons = <int, String>{};
  int _replayFallbackCount = 0;
  int _conflictCount = 0;
  final BoundedPcmBuffer _utterancePcm = BoundedPcmBuffer(
    maxBytes: 160000, // Five seconds of 16 kHz mono PCM16.
  );
  Future<void> _freeTextRecognizerReady = Future<void>.value();

  vosk.Model? _model;
  VoiceRecognizer? _commandRecognizer;
  VoiceRecognizer? _freeTextRecognizer;

  Stream<SegmentedRecognitionResult> get segmentedResultsStream =>
      _segmentedResultsController.stream;
  Stream<SpeechSegmentEnded> get segmentEndedStream =>
      _segmentEndedController.stream;
  Stream<SpeechSegmentStarted> get segmentStartedStream =>
      _segmentStartedController.stream;
  bool get isPrepared =>
      (_model != null || _recognizerFactory != null) &&
      (_commandGrammar.isEmpty || _commandRecognizer != null);
  bool get isSessionActive => _isSessionActive;
  bool get isListening => _isListening;
  bool get isCaptureRunning => _audioStream.isRunning;
  bool get usesFreeTextRecognition => _freeTextEnabled;
  int? get lastAudioChunkAtMillis => _audioStream.lastChunkAtMillis;
  int? get lastNonSilentAudioChunkAtMillis =>
      _audioStream.lastNonSilentChunkAtMillis;
  int? get lastNonZeroNativeInputAtMillis =>
      _audioStream.lastNonZeroNativeInputAtMillis;
  int? get continuousZeroAudioStartedAtMillis =>
      _audioStream.continuousZeroAudioStartedAtMillis;
  int get audioChunksReceived => _audioStream.chunksReceived;
  int get audioCaptureId => _audioStream.captureId;
  int? get captureStartedAtMillis => _audioStream.captureStartedAtMillis;
  bool get hasExpectedInputDevice => _audioStream.hasExpectedInputDevice;
  String? get preferredInputDeviceId => _audioStream.preferredInputDeviceId;
  String? get preferredInputDeviceLabel =>
      _audioStream.preferredInputDeviceLabel;
  AudioStreamService get audioStreamService => _audioStream;
  VoiceDeviceProfile get deviceProfile => _audioStream.deviceProfile;
  bool get isVadCalibrated => _speechSegmenter.isCalibrated;
  int get routeRevision => _routeRevision;
  int get freeTextEpoch => _freeTextEpoch;
  int get grammarRevision => _grammarRevision;
  WearScreenId get sourceScreen => _sourceScreen;
  int get commandUtteranceId => _commandUtteranceId;
  int get bufferedUtteranceBytes => _utterancePcm.length;
  int get replayFallbackCount => _replayFallbackCount;
  int get conflictCount => _conflictCount;
  VoiceRecognitionMetricsSnapshot get metricsSnapshot =>
      _voiceMetrics.snapshot();

  Future<void> waitForProcessing() async {
    while (true) {
      final Future<void> command = _commandAudioProcessing;
      final Future<void> freeText = _freeTextAudioProcessing;
      await command;
      await freeText;
      if (identical(command, _commandAudioProcessing) &&
          identical(freeText, _freeTextAudioProcessing)) {
        return;
      }
    }
  }

  void beginProcessingCapture() {
    final int captureEpoch = _captureEpoch.begin();
    _speechSegmenter.begin(captureEpoch);
    _utterancePcm.clear();
    _commandUtteranceStartedAtMillis = null;
    _liveFreeTextResults.clear();
    _invalidLiveFreeTextUtterances.clear();
    _liveFreeTextInvalidReasons.clear();
    _freeTextBacklog.reset();
  }

  Future<void> switchCommandGrammar({
    required WearScreenId screen,
    required List<String> grammar,
  }) {
    final List<String> normalized = List<String>.unmodifiable(
      grammar.map((item) => item.trim()).where((item) => item.isNotEmpty),
    );
    final int startedAt = DateTime.now().millisecondsSinceEpoch;
    final Future<void> next = _commandAudioProcessing.then((_) async {
      if (_sourceScreen == screen &&
          _sameGrammar(_commandGrammar, normalized)) {
        return;
      }
      VoiceRecognizer? recognizer = _commandRecognizer;
      try {
        if (recognizer != null) {
          await _configureCommandRecognizer(recognizer, normalized);
        }
      } catch (_) {
        if (recognizer != null && identical(_commandRecognizer, recognizer)) {
          _commandRecognizer = null;
          recognizer = await _recoverCommandRecognizer(recognizer);
          try {
            await _configureCommandRecognizer(recognizer, normalized);
          } catch (_) {
            if (identical(_commandRecognizer, recognizer)) {
              _commandRecognizer = null;
            }
            rethrow;
          }
        } else {
          rethrow;
        }
      }
      _freeTextEpoch++;
      _freeTextPartialText = '';
      _sourceScreen = screen;
      _commandGrammar = normalized;
      final int routeRevision = ++_routeRevision;
      final int grammarRevision = ++_grammarRevision;
      _finalizeCommandUtterance();
      print(
        '[VOICE_GRAMMAR] screen=$screen routeRevision=$routeRevision '
        'grammarRevision=$grammarRevision phrases=${normalized.length} '
        'switchMs=${DateTime.now().millisecondsSinceEpoch - startedAt}',
      );
    });
    _commandAudioProcessing = next.catchError((Object error, StackTrace stack) {
      print('[VOICE_GRAMMAR] switch failed: $error\n$stack');
    });
    return next;
  }

  Future<bool> refreshNativeInputActivity() {
    return _audioStream.refreshNativeInputActivity();
  }

  void useDeviceProfile(VoiceDeviceProfile profile) {
    _audioStream.useDeviceProfile(profile);
  }

  Future<void> setFreeTextEnabled(bool enabled) {
    if (_freeTextEnabled == enabled &&
        (!enabled || _freeTextRecognizer != null)) {
      print(
        '[SpeechRecognitionService] setFreeTextEnabled skipped '
        'enabled=$enabled',
      );
      return Future<void>.value();
    }

    final int epoch = ++_freeTextEpoch;
    _freeTextPartialText = '';
    print(
      '[SpeechRecognitionService] freeText enabled=$enabled epoch=$epoch',
    );
    if (!enabled) {
      _freeTextEnabled = false;
      return Future<void>.value();
    }

    _freeTextEnabled = true;
    if (_freeTextRecognizer == null) {
      final Future<void> ready =
          _runLifecycleOperation('createFreeTextRecognizer', () async {
        if (epoch == _freeTextEpoch && _freeTextRecognizer == null) {
          final VoiceRecognizer recognizer =
              await _createRecognizer(_RecognitionSource.freeText);
          if (epoch != _freeTextEpoch) {
            unawaited(recognizer.dispose());
            return;
          }
          _freeTextRecognizer = recognizer;
          _freeTextEnabled = true;
        }
      });
      _freeTextRecognizerReady = ready.whenComplete(() {
        if (_freeTextRecognizer == null) {
          _freeTextEnabled = false;
          _freeTextRecognizerReady = Future<void>.value();
        }
      });
      return _freeTextRecognizerReady;
    }

    _freeTextEnabled = true;
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
    if (!isPrepared) {
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
      _vadFrames.reset();
      _utterancePcm.clear();
      _commandUtteranceStartedAtMillis = null;
      _preRollFrames.clear();
      _lastProcessedChunkAtMillis = null;
      _commandMetrics.reset();
      _freeTextMetrics.reset();
      _commandBacklog.reset();

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
    _vadFrames.reset();
    _utterancePcm.clear();
    _commandUtteranceStartedAtMillis = null;
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
        'freeTextPipelineMode=${freeTextPipelineMode.name}, '
        'command=${_commandMetrics.describe()}, '
        'freeText=${_freeTextMetrics.describe()}, '
        'lastProcessedAgeMs=$lastProcessedAgeMs, audio=$audio}';
  }

  bool _onAudioChunk(
    Uint8List rawBytes,
    Uint8List boostedBytes,
    int captureEpoch,
  ) {
    if (!_isSessionActive || !_captureEpoch.isCurrent(captureEpoch)) {
      return false;
    }
    for (final PcmFramePair frame in _vadFrames.add(rawBytes, boostedBytes)) {
      if (!_processAudioFrame(
        frame.raw,
        frame.boosted,
        captureEpoch,
      )) {
        return false;
      }
    }
    return true;
  }

  static const int _vadFrameBytes = 640; // 20 ms at 16 kHz mono PCM16.

  bool _processAudioFrame(
    Uint8List rawBytes,
    Uint8List boostedBytes,
    int captureEpoch,
  ) {
    final bool wasCalibrated = _speechSegmenter.isCalibrated;
    final SpeechSegment? segment = _speechSegmenter.add(rawBytes, captureEpoch);
    if (!wasCalibrated && _speechSegmenter.isCalibrated) {
      final SpeechSegmentDiagnostics diagnostics =
          _speechSegmenter.lastDiagnostics;
      print(
        '[SpeechRecognitionService] VAD_CALIBRATED '
        'captureEpoch=$captureEpoch '
        'noiseFloorRms=${diagnostics.noiseFloorRms.toStringAsFixed(5)} '
        'p10=${diagnostics.calibrationP10Rms.toStringAsFixed(5)} '
        'p50=${diagnostics.calibrationP50Rms.toStringAsFixed(5)} '
        'p90=${diagnostics.calibrationP90Rms.toStringAsFixed(5)} '
        'adaptiveOnRms=${diagnostics.adaptiveOnRms.toStringAsFixed(5)} '
        'adaptiveOffRms=${diagnostics.adaptiveOffRms.toStringAsFixed(5)}',
      );
    }
    if (segment == null) {
      _preRollFrames.add(_PcmFrame(boostedBytes));
      if (_preRollFrames.length > _preRollFrameCount) {
        _preRollFrames.removeAt(0);
      }
      return true;
    }
    if (segment.started) {
      _logVadEvent('VAD_START', segment);
      _emitSegmentStarted(segment);
      for (final _PcmFrame frame in _preRollFrames) {
        if (!_enqueueSegmentFrame(frame.boosted, captureEpoch, segment)) {
          return false;
        }
      }
      _preRollFrames.clear();
    }
    if (!_enqueueSegmentFrame(boostedBytes, captureEpoch, segment)) {
      return false;
    }
    if (segment.isEndpoint) {
      _logVadEvent('VAD_ENDPOINT', segment);
      if (segment.endpointReason == AcousticEndpointReason.silence) {
        _enqueueSilenceBoundary(segment, captureEpoch);
      }
      unawaited(_finishSegment(segment, captureEpoch).catchError(
        (Object error, StackTrace stackTrace) {
          print('[SpeechRecognitionService] segment finish error: $error');
        },
      ));
    }
    return true;
  }

  void _logVadEvent(String event, SpeechSegment segment) {
    final SpeechSegmentDiagnostics diagnostics =
        _speechSegmenter.lastDiagnostics;
    final int now = DateTime.now().millisecondsSinceEpoch;
    final int? captureStartedAt = _audioStream.captureStartedAtMillis;
    final int? captureAgeMs =
        captureStartedAt == null ? null : now - captureStartedAt;
    print(
      '[SpeechRecognitionService] $event '
      'captureEpoch=${segment.captureEpoch} segmentId=${segment.segmentId} '
      'chunkId=${segment.lastChunkId} captureAgeMs=$captureAgeMs '
      'rawRms=${diagnostics.rms.toStringAsFixed(5)} '
      'noiseFloorRms=${diagnostics.noiseFloorRms.toStringAsFixed(5)} '
      'adaptiveOnRms=${diagnostics.adaptiveOnRms.toStringAsFixed(5)} '
      'adaptiveOffRms=${diagnostics.adaptiveOffRms.toStringAsFixed(5)}',
    );
  }

  bool _enqueueSegmentFrame(
    Uint8List boostedBytes,
    int captureEpoch,
    SpeechSegment segment,
  ) {
    final Uint8List immutableBytes = Uint8List.fromList(boostedBytes);
    final bool hasCommand = _commandRecognizer != null;
    if (hasCommand && !_commandBacklog.canAdmit(immutableBytes.lengthInBytes)) {
      return false;
    }
    if (hasCommand) _commandBacklog.admit(immutableBytes.lengthInBytes);
    final int utteranceId = _commandUtteranceId;
    _enqueueCommandChunk(immutableBytes, captureEpoch, segment,
        admitted: hasCommand);
    if (_usesLiveFreeText) {
      _enqueueFreeTextLiveChunk(
        immutableBytes,
        captureEpoch,
        segment,
        utteranceId,
      );
    }
    return true;
  }

  bool get _usesLiveFreeText =>
      freeTextPipelineMode.usesLiveLane &&
      _freeTextEnabled &&
      _freeTextRecognizer != null;

  Future<void> processAudioChunk(Uint8List bytes) async {
    final int captureEpoch = _captureEpoch.current;
    final SpeechSegment? segment = _speechSegmenter.add(bytes, captureEpoch);
    if (segment == null) return;
    if (segment.started) _emitSegmentStarted(segment);
    final List<Future<void>> processing = <Future<void>>[];
    if (_commandRecognizer != null) {
      if (!_commandBacklog.admit(bytes.lengthInBytes)) {
        throw StateError('RECOGNITION_BACKLOG');
      }
      processing.add(
          _enqueueCommandChunk(bytes, captureEpoch, segment, admitted: true));
    }
    if (_usesLiveFreeText) {
      processing.add(_enqueueFreeTextLiveChunk(
        Uint8List.fromList(bytes),
        captureEpoch,
        segment,
        _commandUtteranceId,
      ));
    }
    await Future.wait<void>(processing);
    if (segment.endpointReason == AcousticEndpointReason.silence) {
      _enqueueSilenceBoundary(segment, captureEpoch);
    }
    if (segment.isEndpoint) await _finishSegment(segment, captureEpoch);
  }

  void _enqueueSilenceBoundary(SpeechSegment segment, int captureEpoch) {
    final int expectedUtteranceId = _commandUtteranceId;
    final VoiceRecognizer? expectedRecognizer = _commandRecognizer;
    if (expectedRecognizer == null) return;

    final Future<void> boundary = _commandAudioProcessing.then((_) async {
      if (!_captureEpoch.isCurrent(captureEpoch) ||
          _commandUtteranceId != expectedUtteranceId ||
          !identical(_commandRecognizer, expectedRecognizer)) {
        return;
      }
      if (_utterancePcm.length == 0 && _commandPartialText.trim().isEmpty) {
        return;
      }
      await _forceCloseCommandUtterance(
        recognizer: expectedRecognizer,
        segment: segment,
        captureEpoch: captureEpoch,
        expectedUtteranceId: expectedUtteranceId,
      );
    });
    _commandAudioProcessing = boundary.catchError(
      (Object error, StackTrace stackTrace) {
        print(
          '[SpeechRecognitionService] silence boundary failed: '
          '$error\n$stackTrace',
        );
      },
    );
  }

  Future<void> _forceCloseCommandUtterance({
    required VoiceRecognizer recognizer,
    required SpeechSegment segment,
    required int captureEpoch,
    required int expectedUtteranceId,
  }) async {
    final int startedAt = DateTime.now().millisecondsSinceEpoch;
    Future<void>? pendingOperation;
    try {
      final String? naturalText =
          _naturalCommandFinals.remove(expectedUtteranceId);
      String json = '{}';
      if (naturalText == null) {
        final Future<String> finalOperation = recognizer.getFinalResult();
        pendingOperation = finalOperation.then<void>((_) {});
        json = await _segmentCloseGuard.run(finalOperation);
      }
      if (!_isCurrentCommandUtterance(
        recognizer,
        captureEpoch,
        expectedUtteranceId,
      )) {
        return;
      }

      final String text = naturalText ??
          _extractText(
            json,
            preferredKeys: const <String>['text'],
          );
      if (text.isNotEmpty && !_usesLiveFreeText) {
        _emitResult(
          _RecognitionSource.command,
          text,
          epoch: null,
          captureEpoch: captureEpoch,
          kind: RecognitionKind.streamFinal,
          segment: segment,
          commandUtteranceId: expectedUtteranceId,
        );
      }
      _completeCommandUtterance(
        resultText: text,
        captureEpoch: captureEpoch,
        segment: segment,
        commandUtteranceId: expectedUtteranceId,
      );

      final Future<void> resetOperation = recognizer.reset();
      pendingOperation = resetOperation;
      await _segmentCloseGuard.run(resetOperation);
      print(
        '[VOICE_BOUNDARY] utteranceEndOwner=vad_silence '
        'commandUtteranceId=$expectedUtteranceId text="$text" '
        'forcedCloseMs=${DateTime.now().millisecondsSinceEpoch - startedAt} '
        'naturalEndpointWon=false recognizerReplaced=false',
      );
    } catch (error) {
      await _replaceUncertainCommandRecognizer(
        failedRecognizer: recognizer,
        pendingOperation: pendingOperation,
        expectedUtteranceId: expectedUtteranceId,
      );
      rethrow;
    }
  }

  bool _isCurrentCommandUtterance(
    VoiceRecognizer recognizer,
    int captureEpoch,
    int expectedUtteranceId,
  ) {
    return _captureEpoch.isCurrent(captureEpoch) &&
        _commandUtteranceId == expectedUtteranceId &&
        identical(_commandRecognizer, recognizer);
  }

  Future<void> _enqueueCommandChunk(
    Uint8List bytes,
    int captureEpoch,
    SpeechSegment segment, {
    bool admitted = false,
  }) {
    if (_commandRecognizer == null) return Future<void>.value();
    final int queuedAt = DateTime.now().millisecondsSinceEpoch;
    final Future<void> next = _commandAudioProcessing
        .then(
      (_) => _processRecognizerChunk(
        source: _RecognitionSource.command,
        recognizer: _commandRecognizer!,
        bytes: bytes,
        queuedAt: queuedAt,
        epoch: null,
        captureEpoch: captureEpoch,
        segment: segment,
      ),
    )
        .whenComplete(() {
      if (admitted) _commandBacklog.complete(bytes.lengthInBytes);
    });
    _commandAudioProcessing = next.catchError(
      (Object error, StackTrace stackTrace) {
        print('[SpeechRecognitionService] command chunk error: $error');
      },
    );
    return next;
  }

  Future<void> _enqueueFreeTextLiveChunk(
    Uint8List bytes,
    int captureEpoch,
    SpeechSegment segment,
    int commandUtteranceId,
  ) {
    final VoiceRecognizer? recognizer = _freeTextRecognizer;
    final int epoch = _freeTextEpoch;
    if (recognizer == null || !_freeTextBacklog.admit(bytes.lengthInBytes)) {
      _invalidLiveFreeTextUtterances.add(commandUtteranceId);
      _liveFreeTextInvalidReasons[commandUtteranceId] = recognizer == null
          ? 'live_lane_not_ready'
          : 'live_lane_backlog_exceeded';
      _voiceMetrics.recordDroppedFrame();
      print(
        '[VOICE_LIVE_FREE_TEXT] mode=${freeTextPipelineMode.name} '
        'captureEpoch=$captureEpoch segmentId=${segment.segmentId} '
        'utteranceId=$commandUtteranceId chunkId=${segment.lastChunkId} '
        'decision=backlog_exceeded '
        'backlogBytes=${_freeTextBacklog.pendingBytes}',
      );
      return Future<void>.value();
    }
    final int queuedAt = DateTime.now().millisecondsSinceEpoch;
    final Future<void> next = _freeTextAudioProcessing.then((_) async {
      if (!_canProcess(
            _RecognitionSource.freeText,
            epoch,
            captureEpoch,
          ) ||
          !identical(_freeTextRecognizer, recognizer)) {
        _invalidLiveFreeTextUtterances.add(commandUtteranceId);
        _liveFreeTextInvalidReasons[commandUtteranceId] =
            'live_lane_epoch_mismatch';
        return;
      }
      final int startedAt = DateTime.now().millisecondsSinceEpoch;
      final bool endpoint = await recognizer.acceptWaveformBytes(bytes);
      _freeTextMetrics.processedChunks++;
      final int finishedAt = DateTime.now().millisecondsSinceEpoch;
      final int queueDelayMs = startedAt - queuedAt;
      final int recognizerMs = finishedAt - startedAt;
      _freeTextMetrics.recordQueueDelay(
        queueDelayMs,
        _slowAudioQueueDelayMs,
      );
      _freeTextMetrics.recordRecognizerLatency(
        recognizerMs,
        _slowRecognizerLatencyMs,
      );
      _voiceMetrics.recordFreeTextChunk(
        queueDelayMs: queueDelayMs,
        audioLagMs: finishedAt - queuedAt,
        recognizerMs: recognizerMs,
        audioMs: bytes.lengthInBytes * 1000 ~/ (_sampleRate * 2),
      );
      if (endpoint) {
        final String json = await recognizer.getResult();
        final String text = _extractText(
          json,
          preferredKeys: const <String>['text'],
        );
        if (text.isNotEmpty) {
          _liveFreeTextResults
              .putIfAbsent(commandUtteranceId, () => <String>[])
              .add(text);
        }
      }
      print(
        '[VOICE_LIVE_FREE_TEXT] mode=${freeTextPipelineMode.name} '
        'captureEpoch=$captureEpoch segmentId=${segment.segmentId} '
        'utteranceId=$commandUtteranceId chunkId=${segment.lastChunkId} '
        'processedThroughChunkId=${segment.lastChunkId} '
        'queueDelayMs=$queueDelayMs recognizerMs=$recognizerMs '
        'audioLagMs=${finishedAt - queuedAt}',
      );
    }).whenComplete(
      () => _freeTextBacklog.complete(bytes.lengthInBytes),
    );
    _freeTextAudioProcessing = next.catchError(
      (Object error, StackTrace stackTrace) {
        _invalidLiveFreeTextUtterances.add(commandUtteranceId);
        _liveFreeTextInvalidReasons[commandUtteranceId] =
            'live_lane_internal_error';
        print('[VOICE_LIVE_FREE_TEXT] chunk failed: $error\n$stackTrace');
      },
    );
    return next;
  }

  Future<void> _finishSegment(SpeechSegment segment, int captureEpoch) async {
    // Acoustic VAD boundaries are diagnostics only. Vosk owns command
    // utterance boundaries through acceptWaveformBytes() == true.
    Object? commandLaneError;
    Object? freeTextLaneError;
    try {
      await _commandAudioProcessing;
    } catch (error) {
      commandLaneError = error;
    }
    try {
      // Command endpoint processing may enqueue replay, so snapshot this lane
      // only after all command frames for the acoustic segment are handled.
      await _freeTextAudioProcessing;
    } catch (error) {
      freeTextLaneError = error;
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

  Future<void> _processRecognizerChunk({
    required _RecognitionSource source,
    required VoiceRecognizer recognizer,
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
    if (bytes.lengthInBytes < 2 ||
        !_canProcess(source, epoch, captureEpoch) ||
        !_isCurrentRecognizer(source, recognizer)) {
      return;
    }

    final _RecognitionMetrics metrics = _metrics(source);
    metrics.processedChunks++;
    final int processingStartedAt = DateTime.now().millisecondsSinceEpoch;
    final int queueDelayMs = processingStartedAt - queuedAt;
    metrics.recordQueueDelay(queueDelayMs, _slowAudioQueueDelayMs);
    if (source == _RecognitionSource.command) {
      _voiceMetrics.recordCommandQueueDelay(queueDelayMs);
    }
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
    final Uint8List processingBytes = bytes;
    if (source == _RecognitionSource.command) {
      _commandUtteranceStartedAtMillis ??= processingStartedAt;
      _utteranceContexts.putIfAbsent(
        _commandUtteranceId,
        () => _currentResultContext(_commandUtteranceId),
      );
      _utterancePcm.add(processingBytes);
    }
    final bool isResultReady =
        await recognizer.acceptWaveformBytes(processingBytes);
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
          '[VOSK][ENDPOINT_RESULT][${source.label}] $resultText at $finishedAt '
          '(queueDelayMs=$queueDelayMs, acceptMs=$latencyMs, '
          'resultMs=${resultFinishedAt - resultStartedAt}, '
          'chunkTotalMs=${finishedAt - startedAt})',
        );
        if (source != _RecognitionSource.command || !_usesLiveFreeText) {
          _emitResult(
            source,
            resultText,
            epoch: epoch,
            captureEpoch: captureEpoch,
            kind: RecognitionKind.endpointResult,
            segment: segment,
          );
        }
      }
      if (source == _RecognitionSource.command) {
        final int completedUtteranceId = _commandUtteranceId;
        if (_usesLiveFreeText && _freeTextEnabled) {
          _naturalCommandFinals[completedUtteranceId] = resultText;
          print(
            '[VOICE_BOUNDARY] natural endpoint candidate '
            'commandUtteranceId=$completedUtteranceId text="$resultText" '
            'waitingFor=vad_silence',
          );
        } else {
          _completeCommandUtterance(
            resultText: resultText,
            captureEpoch: captureEpoch!,
            segment: segment,
            commandUtteranceId: completedUtteranceId,
          );
          print(
            '[VOICE_BOUNDARY] utteranceEndOwner=vosk '
            'commandUtteranceId=$completedUtteranceId text="$resultText" '
            'naturalEndpointWon=true recognizerReplaced=false',
          );
        }
      } else if (_canProcess(source, epoch, captureEpoch)) {
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
    if (partialText != _partialText(source)) {
      final int finishedAt = DateTime.now().millisecondsSinceEpoch;
      print(
        '[VOSK][PARTIAL][${source.label}] $partialText at $finishedAt '
        '(queueDelayMs=$queueDelayMs, acceptMs=$latencyMs, '
        'partialMs=${partialFinishedAt - partialStartedAt}, '
        'chunkTotalMs=${finishedAt - startedAt})',
      );
      _publishPartialChange(
        source: source,
        text: partialText,
        epoch: epoch,
        captureEpoch: captureEpoch,
        segment: segment,
      );
    }
    if (_canProcess(source, epoch, captureEpoch)) {
      _setPartialText(source, partialText);
    }
  }

  void _completeCommandUtterance({
    required String resultText,
    required int captureEpoch,
    required SpeechSegment segment,
    required int commandUtteranceId,
  }) {
    final _VoiceResultContext resultContext =
        _utteranceContexts[commandUtteranceId] ??
            _currentResultContext(commandUtteranceId);
    final Uint8List replay = _utterancePcm.take();
    final bool commandFound = _commandParser.parseExactForScreen(
                resultContext.sourceScreen, resultText) !=
            null ||
        _commandParser.parseExactForScreen(
              _sourceScreen,
              _commandPartialText,
            ) !=
            null;
    if (_freeTextEnabled && replay.isNotEmpty) {
      if (_usesLiveFreeText) {
        _enqueueLiveFreeTextFinalization(
          replay,
          commandText: resultText.isNotEmpty ? resultText : _commandPartialText,
          commandFound: commandFound,
          epoch: _freeTextEpoch,
          captureEpoch: captureEpoch,
          segment: segment,
          commandUtteranceId: commandUtteranceId,
          resultContext: resultContext,
        );
      } else if (!commandFound) {
        _enqueueFreeTextReplay(
          replay,
          epoch: _freeTextEpoch,
          captureEpoch: captureEpoch,
          segment: segment,
          commandUtteranceId: commandUtteranceId,
          resultContext: resultContext,
        );
      }
    }
    if (!_canProcess(_RecognitionSource.command, null, captureEpoch) ||
        _commandUtteranceId != commandUtteranceId) {
      return;
    }
    _publishPartialChange(
      source: _RecognitionSource.command,
      text: '',
      epoch: null,
      captureEpoch: captureEpoch,
      segment: segment,
    );
    _finalizeCommandUtterance();
  }

  void _enqueueLiveFreeTextFinalization(
    Uint8List replay, {
    required String commandText,
    required bool commandFound,
    required int epoch,
    required int captureEpoch,
    required SpeechSegment segment,
    required int commandUtteranceId,
    _VoiceResultContext? resultContext,
  }) {
    final Future<void> next = _freeTextAudioProcessing.then((_) async {
      final int endpointAt = DateTime.now().millisecondsSinceEpoch;
      final VoiceRecognizer? recognizer = _freeTextRecognizer;
      bool valid = recognizer != null &&
          !_invalidLiveFreeTextUtterances.contains(commandUtteranceId) &&
          _canProcess(_RecognitionSource.freeText, epoch, captureEpoch);
      String liveText = '';
      if (valid) {
        Future<String>? pendingFinal;
        try {
          pendingFinal = recognizer.getFinalResult();
          final String json = await _segmentCloseGuard.run(pendingFinal);
          final List<String> parts =
              _liveFreeTextResults.remove(commandUtteranceId) ?? <String>[];
          final String tail =
              _extractText(json, preferredKeys: const <String>['text']);
          if (tail.isNotEmpty) parts.add(tail);
          liveText = parts.join(' ').trim();
          await _segmentCloseGuard.run(recognizer.reset());
        } catch (error) {
          valid = false;
          _invalidLiveFreeTextUtterances.add(commandUtteranceId);
          _liveFreeTextInvalidReasons[commandUtteranceId] =
              error is TimeoutException
                  ? 'live_lane_timeout'
                  : 'live_lane_internal_error';
          await _replaceUncertainFreeTextRecognizer(
            failedRecognizer: recognizer,
            pendingOperation: pendingFinal,
            recognizerEpoch: epoch,
          );
          print('[VOICE_LIVE_FREE_TEXT] finalization failed: $error');
        }
      }
      final int decisionMs = DateTime.now().millisecondsSinceEpoch - endpointAt;
      print(
        '[VOICE_DUAL_FINAL] commandText="$commandText" '
        'freeText="$liveText" endpointToFreeTextFinalMs=$decisionMs',
      );
      if (freeTextPipelineMode == FreeTextPipelineMode.shadowLive) {
        print(
          '[VOICE_SHADOW_COMPARISON] liveText="$liveText" '
          'liveValid=$valid production=replay',
        );
        if (commandFound) {
          _emitResult(
            _RecognitionSource.command,
            commandText,
            epoch: null,
            captureEpoch: captureEpoch,
            kind: RecognitionKind.streamFinal,
            segment: segment,
            commandUtteranceId: commandUtteranceId,
            resultContext: resultContext,
          );
        } else {
          _enqueueFreeTextReplay(
            replay,
            epoch: epoch,
            captureEpoch: captureEpoch,
            segment: segment,
            commandUtteranceId: commandUtteranceId,
            resultContext: resultContext,
            onCompleted: (String replayText, int replayMs) {
              _logShadowComparison(
                liveText: liveText,
                replayText: replayText,
                liveLatencyMs: decisionMs,
                replayLatencyMs: replayMs,
                resultContext: resultContext,
              );
            },
          );
        }
        return;
      }
      if (!valid) {
        final String fallbackReason =
            _liveFreeTextInvalidReasons.remove(commandUtteranceId) ??
                'live_lane_internal_error';
        _replayFallbackCount++;
        _voiceMetrics.recordFallback(fallbackReason);
        print(
          '[VOICE_FREE_TEXT_FALLBACK] reason=$fallbackReason '
          'captureEpoch=$captureEpoch utteranceId=$commandUtteranceId '
          'replayBytes=${replay.lengthInBytes}',
        );
        if (!commandFound) {
          _enqueueFreeTextReplay(
            replay,
            epoch: epoch,
            captureEpoch: captureEpoch,
            segment: segment,
            commandUtteranceId: commandUtteranceId,
            resultContext: resultContext,
          );
        } else {
          _emitResult(
            _RecognitionSource.command,
            commandText,
            epoch: null,
            captureEpoch: captureEpoch,
            kind: RecognitionKind.streamFinal,
            segment: segment,
            commandUtteranceId: commandUtteranceId,
            resultContext: resultContext,
          );
        }
        return;
      }
      _publishCoordinatedDecision(
        commandText: commandText,
        freeText: liveText,
        captureEpoch: captureEpoch,
        epoch: epoch,
        segment: segment,
        commandUtteranceId: commandUtteranceId,
        resultContext: resultContext,
      );
    });
    _freeTextAudioProcessing = next.catchError(
      (Object error, StackTrace stackTrace) {
        print('[VOICE_DUAL_FINAL] failed: $error\n$stackTrace');
      },
    );
  }

  void _logShadowComparison({
    required String liveText,
    required String replayText,
    required int liveLatencyMs,
    required int replayLatencyMs,
    _VoiceResultContext? resultContext,
  }) {
    final WearScreenId screen = resultContext?.sourceScreen ?? _sourceScreen;
    final VoiceDynamicItemsSnapshot items = _dynamicItemsProvider(screen);
    final VoiceListMatch<VoiceDynamicItem> liveMatch = VoiceListMatcher.match(
      liveText,
      items.items,
      (VoiceDynamicItem item) => item.label,
    );
    final VoiceListMatch<VoiceDynamicItem> replayMatch = VoiceListMatcher.match(
      replayText,
      items.items,
      (VoiceDynamicItem item) => item.label,
    );
    final String classification;
    if (VoiceListMatcher.normalize(liveText) ==
            VoiceListMatcher.normalize(replayText) &&
        liveText.trim().isNotEmpty) {
      classification = "same_text";
    } else if (liveMatch.type == VoiceListMatchType.unique &&
        replayMatch.type == VoiceListMatchType.unique &&
        liveMatch.item?.id == replayMatch.item?.id) {
      classification = "same_item";
    } else if (liveMatch.type == VoiceListMatchType.unique &&
        replayMatch.type != VoiceListMatchType.unique) {
      classification = "live_better";
    } else if (replayMatch.type == VoiceListMatchType.unique &&
        liveMatch.type != VoiceListMatchType.unique) {
      classification = "replay_better";
    } else if (liveMatch.type == VoiceListMatchType.none &&
        replayMatch.type == VoiceListMatchType.none) {
      classification = "both_none";
    } else {
      classification = "conflict";
    }
    print(
      "[VOICE_SHADOW_COMPARISON] classification=$classification "
      'liveText="$liveText" replayText="$replayText" '
      "liveMatchType=${liveMatch.type.name} "
      "replayMatchType=${replayMatch.type.name} "
      "liveMatchedItem=${liveMatch.item?.id} "
      "replayMatchedItem=${replayMatch.item?.id} "
      "liveLatencyMs=$liveLatencyMs replayLatencyMs=$replayLatencyMs",
    );
  }

  void _publishCoordinatedDecision({
    required String commandText,
    required String freeText,
    required int captureEpoch,
    required int epoch,
    required SpeechSegment segment,
    required int commandUtteranceId,
    _VoiceResultContext? resultContext,
  }) {
    final _VoiceResultContext context =
        resultContext ?? _currentResultContext(commandUtteranceId);
    final WearVoiceCommand? command = _commandParser.parseExactForScreen(
      context.sourceScreen,
      commandText,
    );
    final WearVoiceCommand? phraseCommand =
        _commandParser.parseExactForScreen(context.sourceScreen, freeText);
    final VoiceDynamicItemsSnapshot items =
        _dynamicItemsProvider(context.sourceScreen);
    final VoiceListMatch<VoiceDynamicItem> match =
        phraseCommand == command && command != null
            ? VoiceListMatch<VoiceDynamicItem>.none()
            : VoiceListMatcher.match(
                freeText,
                items.items,
                (VoiceDynamicItem item) => item.label,
              );
    final VoiceDecisionContext decisionContext = VoiceDecisionContext(
      key: VoiceUtteranceKey(
        captureEpoch: captureEpoch,
        commandUtteranceId: commandUtteranceId,
        routeRevision: context.routeRevision,
        grammarRevision: context.grammarRevision,
        freeTextEpoch: context.freeTextEpoch,
        sourceScreen: context.sourceScreen,
      ),
      listRevision: items.revision,
    );
    final VoiceDynamicItemsSnapshot currentItems =
        _dynamicItemsProvider(_sourceScreen);
    final VoiceDecision decision = _utteranceCoordinator.decide(
      context: decisionContext,
      currentContext: VoiceDecisionContext(
        key: VoiceUtteranceKey(
          captureEpoch: _captureEpoch.current,
          commandUtteranceId: commandUtteranceId,
          routeRevision: _routeRevision,
          grammarRevision: _grammarRevision,
          freeTextEpoch: _freeTextEpoch,
          sourceScreen: _sourceScreen,
        ),
        listRevision: currentItems.revision,
      ),
      command: command == null
          ? null
          : CommandCandidate(command: command, text: commandText),
      freeText: FreeTextCandidate(
        text: freeText,
        matchType: match.type,
        itemId: match.item?.id,
      ),
      itemStillExists: (String itemId) =>
          currentItems.items.any((VoiceDynamicItem item) => item.id == itemId),
    );
    if (decision.kind == VoiceDecisionKind.command) {
      _emitResult(
        _RecognitionSource.command,
        commandText,
        epoch: null,
        captureEpoch: captureEpoch,
        kind: RecognitionKind.streamFinal,
        segment: segment,
        commandUtteranceId: commandUtteranceId,
        resultContext: context,
      );
    } else if (decision.kind == VoiceDecisionKind.dynamicItem) {
      _emitResult(
        _RecognitionSource.freeText,
        freeText,
        epoch: epoch,
        captureEpoch: captureEpoch,
        kind: RecognitionKind.streamFinal,
        segment: segment,
        commandUtteranceId: commandUtteranceId,
        resultContext: context,
        isLiveFreeText: true,
      );
    } else if (decision.kind == VoiceDecisionKind.conflictRejected) {
      _conflictCount++;
      _voiceMetrics.recordConflict();
    } else if (decision.kind == VoiceDecisionKind.stale) {
      _voiceMetrics.recordStale();
    }
    print(
      "[VOICE_ARBITRATION] decision=${decision.kind.name} "
      'command="$commandText" phrase="$freeText" '
      "matchType=${match.type.name} matchedItemId=${match.item?.id}",
    );
  }

  void _enqueueFreeTextReplay(
    Uint8List bytes, {
    required int epoch,
    required int captureEpoch,
    required SpeechSegment segment,
    required int commandUtteranceId,
    _VoiceResultContext? resultContext,
    void Function(String text, int replayMs)? onCompleted,
  }) {
    final Future<void> next = _freeTextAudioProcessing.then((_) async {
      final int startedAt = DateTime.now().millisecondsSinceEpoch;
      await _freeTextRecognizerReady.timeout(
        _remainingReplayTimeout(startedAt),
      );
      final VoiceRecognizer? recognizer = _freeTextRecognizer;
      if (recognizer == null ||
          !_canProcess(
            _RecognitionSource.freeText,
            epoch,
            captureEpoch,
          )) {
        return;
      }
      await recognizer.reset().timeout(_remainingReplayTimeout(startedAt));
      const int replayBatchBytes = 2560; // 80 ms at 16 kHz mono PCM16.
      final List<String> results = <String>[];
      for (int offset = 0;
          offset < bytes.lengthInBytes;
          offset += replayBatchBytes) {
        final int requestedEnd = offset + replayBatchBytes;
        final int end = requestedEnd < bytes.lengthInBytes
            ? requestedEnd
            : bytes.lengthInBytes;
        if (!_canProcess(_RecognitionSource.freeText, epoch, captureEpoch)) {
          return;
        }
        final bool endpoint = await recognizer
            .acceptWaveformBytes(
              Uint8List.sublistView(bytes, offset, end),
            )
            .timeout(_remainingReplayTimeout(startedAt));
        if (endpoint) {
          final String endpointJson = await recognizer
              .getResult()
              .timeout(_remainingReplayTimeout(startedAt));
          final String endpointText =
              _extractText(endpointJson, preferredKeys: const <String>['text']);
          if (endpointText.isNotEmpty) results.add(endpointText);
        }
      }
      if (!_canProcess(_RecognitionSource.freeText, epoch, captureEpoch)) {
        return;
      }
      final String json = await recognizer
          .getFinalResult()
          .timeout(_remainingReplayTimeout(startedAt));
      final String tail =
          _extractText(json, preferredKeys: const <String>['text']);
      if (tail.isNotEmpty) results.add(tail);
      final String text = results.join(' ').trim();
      final int replayMs = DateTime.now().millisecondsSinceEpoch - startedAt;
      onCompleted?.call(text, replayMs);
      if (text.isNotEmpty) {
        _emitResult(
          _RecognitionSource.freeText,
          text,
          epoch: epoch,
          captureEpoch: captureEpoch,
          kind: RecognitionKind.streamFinal,
          segment: segment,
          commandUtteranceId: commandUtteranceId,
        );
      }
      print(
        '[VOICE_FREE_TEXT] replayBytes=${bytes.lengthInBytes} '
        'replayMs=$replayMs',
      );
    });
    _freeTextAudioProcessing =
        next.catchError((Object error, StackTrace stack) async {
      print('[VOICE_FREE_TEXT] replay failed: $error\n$stack');
      if (error is TimeoutException) {
        await _replaceTimedOutFreeTextRecognizer(recognizerEpoch: epoch);
      }
    });
  }

  Duration _remainingReplayTimeout(int startedAtMillis) {
    final int elapsed = DateTime.now().millisecondsSinceEpoch - startedAtMillis;
    final int remaining = _segmentCloseGuard.timeout.inMilliseconds - elapsed;
    return Duration(milliseconds: remaining > 0 ? remaining : 0);
  }

  Future<void> _replaceTimedOutFreeTextRecognizer({
    required int recognizerEpoch,
  }) async {
    if (recognizerEpoch != _freeTextEpoch || !_freeTextEnabled) return;
    _freeTextEpoch++;
    _freeTextRecognizer = null;
    final Future<void> ready = _runLifecycleOperation(
      'replaceTimedOutFreeTextRecognizer',
      () async {
        if (!_freeTextEnabled || _freeTextRecognizer != null) return;
        _freeTextRecognizer =
            await _createRecognizer(_RecognitionSource.freeText);
      },
    );
    _freeTextRecognizerReady = ready;
    await ready;
  }

  Future<void> _replaceUncertainFreeTextRecognizer({
    required VoiceRecognizer failedRecognizer,
    required Future<void>? pendingOperation,
    required int recognizerEpoch,
  }) async {
    if (recognizerEpoch != _freeTextEpoch ||
        !identical(_freeTextRecognizer, failedRecognizer)) {
      return;
    }
    _freeTextRecognizer = null;
    final VoiceRecognizer replacement =
        await _createRecognizer(_RecognitionSource.freeText);
    if (recognizerEpoch == _freeTextEpoch && _freeTextEnabled) {
      _freeTextRecognizer = replacement;
    } else {
      await replacement.dispose();
    }
    final Future<void> safeToDispose = pendingOperation == null
        ? Future<void>.value()
        : pendingOperation.catchError((Object _, StackTrace __) {});
    unawaited(safeToDispose.then((_) => failedRecognizer.dispose()).catchError(
      (Object error, StackTrace stackTrace) {
        print(
          '[VOICE_LIVE_FREE_TEXT] deferred recognizer cleanup failed: '
          '$error\n$stackTrace',
        );
      },
    ));
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

  bool _isCurrentRecognizer(
    _RecognitionSource source,
    VoiceRecognizer recognizer,
  ) {
    return switch (source) {
      _RecognitionSource.command => identical(_commandRecognizer, recognizer),
      _RecognitionSource.freeText => identical(_freeTextRecognizer, recognizer),
    };
  }

  _VoiceResultContext _currentResultContext(int utteranceId) {
    return _VoiceResultContext(
      commandUtteranceId: utteranceId,
      routeRevision: _routeRevision,
      grammarRevision: _grammarRevision,
      freeTextEpoch: _freeTextEpoch,
      sourceScreen: _sourceScreen,
      startedAtMillis: _commandUtteranceStartedAtMillis,
    );
  }

  void _emitResult(
    _RecognitionSource source,
    String text, {
    required int? epoch,
    required int? captureEpoch,
    required RecognitionKind kind,
    required SpeechSegment segment,
    int? commandUtteranceId,
    _VoiceResultContext? resultContext,
    bool isLiveFreeText = false,
  }) {
    final _VoiceResultContext context = resultContext ??
        _currentResultContext(commandUtteranceId ?? _commandUtteranceId);
    if (!_canProcess(source, epoch, captureEpoch)) {
      _voiceMetrics.recordStale();
      print(
        '[SpeechRecognitionService] suppress stale result '
        'source=${source.label} epoch=$epoch currentEpoch=$_freeTextEpoch',
      );
      return;
    }
    if (!_segmentedResultsController.isClosed) {
      final WearVoiceCommand? parsedCommand =
          source == _RecognitionSource.command
              ? _commandParser.parseExactForScreen(context.sourceScreen, text)
              : null;
      if (source == _RecognitionSource.command) {
        final CommandRecognitionEvent event = CommandRecognitionEvent(
          captureEpoch: segment.captureEpoch,
          acousticSegmentId: segment.segmentId,
          commandUtteranceId: commandUtteranceId ?? _commandUtteranceId,
          routeRevision: context.routeRevision,
          grammarRevision: context.grammarRevision,
          sourceScreen: context.sourceScreen,
          kind: switch (kind) {
            RecognitionKind.partial => RecognitionEventKind.partial,
            RecognitionKind.endpointResult =>
              RecognitionEventKind.endpointResult,
            RecognitionKind.streamFinal => RecognitionEventKind.streamFinal,
          },
          text: text,
          command: parsedCommand,
          recognizedAtMillis: DateTime.now().millisecondsSinceEpoch,
        );
        print(
          '[VOICE_COMMAND] captureEpoch=${event.captureEpoch} '
          'acousticSegmentId=${event.acousticSegmentId} '
          'commandUtteranceId=${event.commandUtteranceId} '
          'routeRevision=${event.routeRevision} '
          'grammarRevision=${event.grammarRevision} '
          'screen=${event.sourceScreen.name} kind=${event.kind.name} '
          'text="${event.text}" command=${event.command}',
        );
      }
      _segmentedResultsController.add(SegmentedRecognitionResult(
        captureEpoch: segment.captureEpoch,
        segmentId: segment.segmentId,
        lane: source == _RecognitionSource.command
            ? RecognitionLane.command
            : RecognitionLane.freeText,
        kind: kind,
        text: text,
        lastChunkId: segment.lastChunkId,
        parsedCommand: parsedCommand,
        commandUtteranceId: commandUtteranceId ?? _commandUtteranceId,
        routeRevision: context.routeRevision,
        grammarRevision: context.grammarRevision,
        sourceScreen: context.sourceScreen,
        partialRevision: _commandPartialRevision,
        commandUtteranceStartedAtMillis: context.startedAtMillis,
        freeTextEpoch: context.freeTextEpoch,
        isLiveFreeText: isLiveFreeText,
      ));
    }
  }

  void _publishPartialChange({
    required _RecognitionSource source,
    required String text,
    required int? epoch,
    required int? captureEpoch,
    required SpeechSegment segment,
  }) {
    if (source == _RecognitionSource.command) _commandPartialRevision++;
    _emitResult(
      source,
      text,
      epoch: epoch,
      captureEpoch: captureEpoch,
      kind: RecognitionKind.partial,
      segment: segment,
    );
  }

  void _finalizeCommandUtterance({bool clearPartial = true}) {
    _utterancePcm.clear();
    if (clearPartial) _commandPartialText = '';
    _commandUtteranceStartedAtMillis = null;
    _commandUtteranceId++;
  }

  bool _sameGrammar(List<String> first, List<String> second) {
    if (first.length != second.length) return false;
    for (int index = 0; index < first.length; index++) {
      if (first[index] != second[index]) return false;
    }
    return true;
  }

  Future<VoiceRecognizer> _recoverCommandRecognizer(
    VoiceRecognizer failed,
  ) async {
    late final VoiceRecognizer replacement;
    try {
      replacement = await _createRecognizer(_RecognitionSource.command);
      _commandRecognizer ??= replacement;
      if (!identical(_commandRecognizer, replacement)) {
        await replacement.dispose();
      }
    } catch (error, stackTrace) {
      print('[VOICE_GRAMMAR] recognizer recovery failed: $error\n$stackTrace');
      rethrow;
    }
    return _commandRecognizer!;
  }

  Future<void> _replaceUncertainCommandRecognizer({
    required VoiceRecognizer failedRecognizer,
    required Future<void>? pendingOperation,
    required int expectedUtteranceId,
  }) async {
    if (!identical(_commandRecognizer, failedRecognizer)) return;
    _commandRecognizer = null;
    final VoiceRecognizer replacement =
        await _createRecognizer(_RecognitionSource.command);
    _commandRecognizer = replacement;
    if (_commandUtteranceId == expectedUtteranceId) {
      _finalizeCommandUtterance();
    }
    print(
      '[VOICE_BOUNDARY] commandUtteranceId=$expectedUtteranceId '
      'recognizerReplaced=true',
    );

    final Future<void> safeToDispose = pendingOperation == null
        ? Future<void>.value()
        : pendingOperation.catchError((Object _, StackTrace __) {});
    unawaited(safeToDispose.then((_) => failedRecognizer.dispose()).catchError(
      (Object error, StackTrace stackTrace) {
        print(
          '[SpeechRecognitionService] uncertain recognizer cleanup failed: '
          '$error\n$stackTrace',
        );
      },
    ));
  }

  Future<void> _configureCommandRecognizer(
    VoiceRecognizer recognizer,
    List<String> grammar,
  ) async {
    Future<void> operation = recognizer.reset();
    try {
      await _segmentCloseGuard.run(operation);
      operation = recognizer.setGrammar(grammar);
      await _segmentCloseGuard.run(operation);
    } on TimeoutException {
      unawaited(operation.whenComplete(() => recognizer.dispose()).catchError(
        (Object error, StackTrace stackTrace) {
          print('[VOICE_GRAMMAR] deferred recognizer dispose failed: $error');
        },
      ));
      rethrow;
    } catch (_) {
      unawaited(recognizer.dispose());
      rethrow;
    }
  }

  void _removeAudioCallback() {
    final bool Function(Uint8List raw, Uint8List boosted)? callback =
        _audioCallback;
    if (callback != null) _audioStream.removePcmCallback(callback);
    _audioCallback = null;
  }

  Future<void> _ensureModelInitialized() async {
    if (_model != null || _recognizerFactory != null) {
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
    if (_commandGrammar.isNotEmpty && _commandRecognizer == null) {
      _commandRecognizer = await _createRecognizer(_RecognitionSource.command);
    }
    if (_freeTextEnabled && _freeTextRecognizer == null) {
      _freeTextRecognizer =
          await _createRecognizer(_RecognitionSource.freeText);
    }
  }

  Future<VoiceRecognizer> _createRecognizer(
    _RecognitionSource source,
  ) async {
    final VoiceRecognizerFactory? factory = _recognizerFactory;
    if (factory != null) {
      final VoiceRecognizer recognizer = await factory(
        source == _RecognitionSource.command
            ? RecognitionLane.command
            : RecognitionLane.freeText,
        _commandGrammar,
      );
      if (source == _RecognitionSource.command) {
        await recognizer.setGrammar(_commandGrammar);
      } else if (freeTextPipelineMode.usesLiveLane) {
        await _warmUpFreeTextRecognizer(recognizer);
      }
      return recognizer;
    }
    final vosk.Model? model = _model;
    if (model == null) throw StateError('Vosk модель не инициализирована.');

    final int startedAt = DateTime.now().millisecondsSinceEpoch;
    final VoiceRecognizer recognizer = VoskVoiceRecognizer(
      await _vosk.createRecognizer(
        model: model,
        sampleRate: _sampleRate,
      ),
    );
    if (source == _RecognitionSource.freeText) {
      if (freeTextPipelineMode.usesLiveLane) {
        await _warmUpFreeTextRecognizer(recognizer);
      }
      return recognizer;
    }
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
    final int finishedAt = DateTime.now().millisecondsSinceEpoch;
    print(
      '[SpeechRecognitionService] command recognizer ready '
      'durationMs=${finishedAt - startedAt}',
    );
    return recognizer;
  }

  Future<void> _warmUpFreeTextRecognizer(VoiceRecognizer recognizer) async {
    final int startedAt = DateTime.now().millisecondsSinceEpoch;
    final Uint8List silence = Uint8List(320);
    await _segmentCloseGuard.run(recognizer.acceptWaveformBytes(silence));
    await _segmentCloseGuard.run(recognizer.getFinalResult());
    await _segmentCloseGuard.run(recognizer.reset());
    print(
      '[VOICE_LIVE_FREE_TEXT] warmup done '
      'durationMs=${DateTime.now().millisecondsSinceEpoch - startedAt}',
    );
  }

  Future<void> _replaceRecognizersAfterTimedOutProcessing({
    required Future<void> commandProcessing,
    required Future<void> freeTextProcessing,
  }) async {
    final VoiceRecognizer? oldCommand = _commandRecognizer;
    final VoiceRecognizer? oldFreeText = _freeTextRecognizer;
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
    await stopListening();
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

class PcmFramePair {
  const PcmFramePair(this.raw, this.boosted);

  final Uint8List raw;
  final Uint8List boosted;
}

class BoundedPcmBuffer {
  BoundedPcmBuffer({required this.maxBytes});

  final int maxBytes;
  final Queue<Uint8List> _chunks = Queue<Uint8List>();
  int _length = 0;
  int _firstOffset = 0;

  int get length => _length;

  void add(Uint8List bytes) {
    if (bytes.isEmpty) return;
    final Uint8List chunk = Uint8List.fromList(bytes);
    _chunks.addLast(chunk);
    _length += chunk.lengthInBytes;
    int overflow = _length - maxBytes;
    while (overflow > 0 && _chunks.isNotEmpty) {
      final int available = _chunks.first.lengthInBytes - _firstOffset;
      if (overflow < available) {
        _firstOffset += overflow;
        _length -= overflow;
        overflow = 0;
      } else {
        _chunks.removeFirst();
        _firstOffset = 0;
        _length -= available;
        overflow -= available;
      }
    }
  }

  Uint8List take() {
    final Uint8List result = Uint8List(_length);
    int writeOffset = 0;
    for (final Uint8List chunk in _chunks) {
      final int readOffset = identical(chunk, _chunks.first) ? _firstOffset : 0;
      result.setRange(
        writeOffset,
        writeOffset + chunk.lengthInBytes - readOffset,
        chunk,
        readOffset,
      );
      writeOffset += chunk.lengthInBytes - readOffset;
    }
    clear();
    return result;
  }

  void clear() {
    _chunks.clear();
    _length = 0;
    _firstOffset = 0;
  }
}

/// Preserves packet remainders so VAD always receives exact 20 ms PCM frames.
class PcmFrameAccumulator {
  PcmFrameAccumulator({required this.frameBytes});

  final int frameBytes;
  Uint8List _rawRemainder = Uint8List(0);
  Uint8List _boostedRemainder = Uint8List(0);

  List<PcmFramePair> add(Uint8List raw, Uint8List boosted) {
    if (raw.lengthInBytes != boosted.lengthInBytes || raw.lengthInBytes.isOdd) {
      throw ArgumentError('PCM packets must be equally sized PCM16 buffers.');
    }
    final Uint8List rawBytes = _append(_rawRemainder, raw);
    final Uint8List boostedBytes = _append(_boostedRemainder, boosted);
    final int completeBytes = rawBytes.lengthInBytes ~/ frameBytes * frameBytes;
    final List<PcmFramePair> frames = <PcmFramePair>[];
    for (int offset = 0; offset < completeBytes; offset += frameBytes) {
      frames.add(PcmFramePair(
        Uint8List.sublistView(rawBytes, offset, offset + frameBytes),
        Uint8List.sublistView(boostedBytes, offset, offset + frameBytes),
      ));
    }
    _rawRemainder = Uint8List.fromList(rawBytes.sublist(completeBytes));
    _boostedRemainder = Uint8List.fromList(boostedBytes.sublist(completeBytes));
    return frames;
  }

  void reset() {
    _rawRemainder = Uint8List(0);
    _boostedRemainder = Uint8List(0);
  }

  Uint8List _append(Uint8List first, Uint8List second) {
    final Uint8List result =
        Uint8List(first.lengthInBytes + second.lengthInBytes)
          ..setAll(0, first)
          ..setAll(first.lengthInBytes, second);
    return result;
  }
}

class _VoiceResultContext {
  const _VoiceResultContext({
    required this.commandUtteranceId,
    required this.routeRevision,
    required this.grammarRevision,
    required this.freeTextEpoch,
    required this.sourceScreen,
    required this.startedAtMillis,
  });

  final int commandUtteranceId;
  final int routeRevision;
  final int grammarRevision;
  final int freeTextEpoch;
  final WearScreenId sourceScreen;
  final int? startedAtMillis;
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
