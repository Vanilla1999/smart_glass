import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import 'package:smart_glasses/modules/wear/domain/service/voice_command/voice_command_parser_service.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/voice_action_catalog.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/command_recognition_event.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/wear_voice_command.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/voice_list_matcher.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/voice_hint_generator.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/voice_hint_index_cache.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/voice_utterance_coordinator.dart';
import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_typing/audio_stream_service.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_typing/free_text_pipeline_mode.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_typing/segmented_recognition_result.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_typing/speech_segmenter.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_typing/voice_device_profile.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_typing/voice_recognition_metrics.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_typing/voice_replay_ownership.dart';
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
  // A replay is a sequence of native calls. Keep its total deadline separate
  // from the timeout that detects one stuck JNI/Vosk operation.
  static const Duration _minimumFreeTextReplayBudget = Duration(seconds: 4);
  static const Duration _freeTextReplayHeadroom = Duration(seconds: 2);
  static const Duration _maximumFreeTextReplayBudget = Duration(seconds: 8);

  SpeechRecognitionService({
    AudioStreamService? audioStreamService,
    List<String> commandGrammar = const <String>[],
    SpeechSegmenter? speechSegmenter,
    VoiceActionCatalog? actionCatalog,
    VoiceRecognizerFactory? recognizerFactory,
    Duration recognizerOperationTimeout = const Duration(seconds: 2),
    this.freeTextPipelineMode = FreeTextPipelineMode.replayOnly,
    int commandBacklogLimitBytes = 64000,
    int freeTextBacklogLimitBytes = 7680,
    VoiceDynamicItemsProvider? dynamicItemsProvider,
    VoiceHintIndexCache? voiceHintIndexCache,
  })  : _audioStreamOverride = audioStreamService,
        _speechSegmenter = speechSegmenter ?? SpeechSegmenter(),
        _actionCatalog = actionCatalog ?? VoiceActionCatalog(),
        _commandGrammar = List<String>.unmodifiable(
          commandGrammar
              .map((String item) => item.trim())
              .where((String item) => item.isNotEmpty),
        ),
        _freeTextEnabled = commandGrammar.isEmpty,
        _freeTextAcceptingPcm = commandGrammar.isEmpty,
        _commandParser = VoiceCommandParserService(catalog: actionCatalog),
        _recognizerFactory = recognizerFactory,
        _segmentCloseGuard = VoiceRecognitionSegmentCloseGuard(
          timeout: recognizerOperationTimeout,
        ),
        _commandBacklog = VoicePcmBacklog(maxBytes: commandBacklogLimitBytes),
        _freeTextBacklog = VoicePcmBacklog(maxBytes: freeTextBacklogLimitBytes),
        _voiceHintIndexCache = voiceHintIndexCache ?? VoiceHintIndexCache(),
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
  final VoiceActionCatalog _actionCatalog;
  final VoiceCommandParserService _commandParser;
  final VoiceRecognizerFactory? _recognizerFactory;
  final VoiceRecognitionSegmentCloseGuard _segmentCloseGuard;
  final VoiceDynamicItemsProvider _dynamicItemsProvider;
  final VoiceHintIndexCache _voiceHintIndexCache;
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
  bool _freeTextAcceptingPcm;
  bool _isSessionActive = false;
  bool _isListening = false;
  Future<void> _commandAudioProcessing = Future<void>.value();
  Future<void> _freeTextAudioProcessing = Future<void>.value();
  Future<void> _lifecycleOperation = Future<void>.value();
  int _freeTextEpoch = 0;
  int _commandUtteranceId = 1;
  int _latestActionableCommandUtteranceId = 0;
  int _admittedCommandUtteranceId = 1;
  int _latestAdmittedSegmentId = 0;
  int _pendingCommandFrames = 0;
  final List<Uint8List> _recognizerBatchFrames = <Uint8List>[];
  int? _recognizerBatchCaptureEpoch;
  int? _recognizerBatchUtteranceId;
  SpeechSegment? _recognizerBatchSegment;
  int _recognizerBatchCommandBytes = 0;
  bool _recognizerBatchCommandEnabled = false;
  int _freeTextLiveBatchCount = 0;
  int _commandPartialRevision = 0;
  int _freeTextPartialRevision = 0;
  final Map<String, String> _shadowPartialItemIds = <String, String>{};
  ({
    WearScreenId screen,
    List<String> grammar,
    List<Completer<void>> waiters,
  })? _pendingGrammarSwitch;
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
  static const int _recognizerBatchFrameCount = 4; // 80 ms.
  final _RecognitionMetrics _commandMetrics = _RecognitionMetrics();
  final _RecognitionMetrics _freeTextMetrics = _RecognitionMetrics();
  final VoicePcmBacklog _commandBacklog;
  final VoicePcmBacklog _freeTextBacklog;
  final VoiceRecognitionMetrics _voiceMetrics = VoiceRecognitionMetrics();
  final VoiceReplayOwnershipStateMachine _replayOwnership =
      VoiceReplayOwnershipStateMachine();
  final Map<int, List<String>> _liveFreeTextResults = <int, List<String>>{};
  final Map<int, String> _naturalCommandFinals = <int, String>{};
  final Map<int, _VoiceResultContext> _utteranceContexts =
      <int, _VoiceResultContext>{};
  final Set<int> _invalidLiveFreeTextUtterances = <int>{};
  final Set<int> _loggedLiveFreeTextUtterances = <int>{};
  final Map<int, String> _liveFreeTextInvalidReasons = <int, String>{};
  final Map<int, _FreeTextBoundary> _freeTextBoundaries =
      <int, _FreeTextBoundary>{};
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
  bool get usesFreeTextRecognition => _freeTextAcceptingPcm;
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
  int get captureEpoch => _captureEpoch.current;
  int get grammarRevision => _grammarRevision;
  WearScreenId get sourceScreen => _sourceScreen;
  int get commandUtteranceId => _commandUtteranceId;
  int get freeTextPartialRevision => _freeTextPartialRevision;
  int get commandPartialRevision => _commandPartialRevision;
  int get currentDynamicItemsRevision =>
      _dynamicItemsProvider(_sourceScreen).revision;
  int get bufferedUtteranceBytes => _utterancePcm.length;
  int get replayFallbackCount => _replayFallbackCount;
  int get conflictCount => _conflictCount;
  VoiceRecognitionMetricsSnapshot get metricsSnapshot =>
      _voiceMetrics.snapshot();
  VoiceReplayOwnership get replayOwnership => _replayOwnership.current;
  Stream<VoiceReplayOwnership> get replayOwnershipStream =>
      _replayOwnership.transitions;

  void markActionableCommandUtterance(int commandUtteranceId) {
    if (commandUtteranceId > _latestActionableCommandUtteranceId) {
      _latestActionableCommandUtteranceId = commandUtteranceId;
    }
    final VoiceReplayOwnership ownership = _replayOwnership.current;
    final VoiceReplayContext? context = ownership.context;
    if (ownership.status == VoiceReplayOwnershipStatus.pending &&
        context != null &&
        commandUtteranceId > context.commandUtteranceId) {
      _supersedeReplay(context, supersededBy: commandUtteranceId);
    }
  }

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
    _flushRecognizerBatch();
    final int captureEpoch = _captureEpoch.begin();
    _beginCaptureEpoch(captureEpoch);
    _utterancePcm.clear();
    _commandUtteranceStartedAtMillis = null;
    _latestActionableCommandUtteranceId = 0;
    _admittedCommandUtteranceId = _commandUtteranceId;
    _pendingCommandFrames = 0;
    _cancelPendingGrammarSwitch(
      StateError('Grammar switch cancelled because capture restarted'),
    );
    _clearPerCaptureState();
    _freeTextBacklog.reset();
  }

  void _beginCaptureEpoch(int captureEpoch) {
    _speechSegmenter.begin(captureEpoch);
    _latestAdmittedSegmentId = 0;
  }

  Future<void> switchCommandGrammar({
    required WearScreenId screen,
    required List<String> grammar,
  }) {
    final int expectedCaptureEpoch = _captureEpoch.current;
    final List<String> normalized = List<String>.unmodifiable(
      grammar.map((item) => item.trim()).where((item) => item.isNotEmpty),
    );
    if (_commandUtteranceStartedAtMillis != null ||
        _utterancePcm.length > 0 ||
        _pendingCommandFrames > 0 ||
        _recognizerBatchFrames.isNotEmpty) {
      final Completer<void> waiter = Completer<void>();
      final pending = _pendingGrammarSwitch;
      _pendingGrammarSwitch = (
        screen: screen,
        grammar: normalized,
        waiters: <Completer<void>>[...?pending?.waiters, waiter],
      );
      print(
        '[VOICE_GRAMMAR] deferred screen=$screen phrases=${normalized.length}',
      );
      return waiter.future;
    }
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
      if (_captureEpoch.current != expectedCaptureEpoch) {
        if (recognizer != null && identical(_commandRecognizer, recognizer)) {
          _commandRecognizer = null;
          try {
            final VoiceRecognizer replacement =
                await _createRecognizer(_RecognitionSource.command);
            _commandRecognizer = replacement;
          } finally {
            await recognizer.dispose();
          }
        }
        throw StateError('Grammar switch cancelled because capture changed');
      }
      _freeTextEpoch++;
      _freeTextPartialText = '';
      _sourceScreen = screen;
      _commandGrammar = normalized;
      final int routeRevision = ++_routeRevision;
      final int grammarRevision = ++_grammarRevision;
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

  Future<void> prepareVoiceHints(WearScreenId screen) async {
    final VoiceDynamicItemsSnapshot items = _dynamicItemsProvider(screen);
    if (items.items.isEmpty) return;
    final Set<String> reservedPhrases = _actionCatalog.phrasesFor(screen);
    if (_voiceHintIndexCache.getIfReady(
          snapshot: items,
          screen: screen.name,
          reservedPhrases: reservedPhrases,
        ) !=
        null) {
      return;
    }
    if (items.items.length <= VoiceHintIndexCache.synchronousItemLimit) {
      _voiceHintIndexCache.prepareSmallSynchronously(
        snapshot: items,
        screen: screen.name,
        reservedPhrases: reservedPhrases,
      );
      return;
    }
    await _voiceHintIndexCache.prepare(
      snapshot: items,
      screen: screen.name,
      reservedPhrases: reservedPhrases,
    );
  }

  void useDeviceProfile(VoiceDeviceProfile profile) {
    _audioStream.useDeviceProfile(profile);
  }

  Future<void> setFreeTextEnabled(bool enabled) {
    if (_freeTextAcceptingPcm == enabled &&
        (!enabled || _freeTextRecognizer != null)) {
      print(
        '[SpeechRecognitionService] setFreeTextEnabled skipped '
        'enabled=$enabled',
      );
      return Future<void>.value();
    }

    if (!enabled) {
      _flushRecognizerBatch();
      _freeTextAcceptingPcm = false;
      final int expectedEpoch = _freeTextEpoch;
      final Future<void> next = _freeTextAudioProcessing.then((_) {
        if (_freeTextAcceptingPcm || _freeTextEpoch != expectedEpoch) return;
        final int epoch = ++_freeTextEpoch;
        _freeTextEnabled = false;
        _freeTextPartialText = '';
        print(
          '[SpeechRecognitionService] freeText enabled=false epoch=$epoch',
        );
      });
      _freeTextAudioProcessing = next.catchError(
        (Object error, StackTrace stackTrace) {
          print(
            '[SpeechRecognitionService] freeText disable error: '
            '$error\n$stackTrace',
          );
        },
      );
      return next;
    }

    _flushRecognizerBatch();
    _freeTextAcceptingPcm = false;
    final Future<void> commandDrain = _commandAudioProcessing;
    final Future<void> freeTextDrain = _freeTextAudioProcessing;
    final int epoch = ++_freeTextEpoch;
    _freeTextPartialText = '';
    print(
      '[SpeechRecognitionService] freeText enabled=true epoch=$epoch',
    );
    _freeTextEnabled = true;
    _freeTextAcceptingPcm = true;
    if (_freeTextRecognizer == null) {
      final Future<void> ready =
          _runLifecycleOperation('createFreeTextRecognizer', () async {
        await commandDrain;
        if (epoch == _freeTextEpoch && _freeTextRecognizer == null) {
          final VoiceRecognizer recognizer =
              await _createRecognizer(_RecognitionSource.freeText);
          if (epoch != _freeTextEpoch) {
            unawaited(recognizer.dispose());
            return;
          }
          _freeTextRecognizer = recognizer;
          _freeTextEnabled = true;
          _admittedCommandUtteranceId = _commandUtteranceId;
          _freeTextAcceptingPcm = true;
        }
      });
      _freeTextRecognizerReady = ready.whenComplete(() {
        if (_freeTextRecognizer == null) {
          _freeTextEnabled = false;
          _freeTextAcceptingPcm = false;
          _freeTextRecognizerReady = Future<void>.value();
        }
      });
      return _freeTextRecognizerReady;
    }

    final Future<void> next =
        commandDrain.then((_) => freeTextDrain).then((_) async {
      if (!_freeTextEnabled || epoch != _freeTextEpoch) return;
      await _freeTextRecognizer?.reset();
      _admittedCommandUtteranceId = _commandUtteranceId;
      _freeTextAcceptingPcm = true;
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
      _beginCaptureEpoch(captureEpoch);
      _vadFrames.reset();
      _utterancePcm.clear();
      _commandUtteranceStartedAtMillis = null;
      _admittedCommandUtteranceId = _commandUtteranceId;
      _preRollFrames.clear();
      _clearRecognizerBatch();
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
    _removeAudioCallback();
    _flushRecognizerBatch();
    final int processingStartedAt = DateTime.now().millisecondsSinceEpoch;
    final bool processingFinished =
        await const VoiceRecognitionProcessingQueue().waitForIdle(
      command: _commandAudioProcessing,
      freeText: _freeTextAudioProcessing,
    );
    _captureEpoch.invalidate();
    _speechSegmenter.end(_captureEpoch.current - 1);
    _vadFrames.reset();
    _utterancePcm.clear();
    _commandUtteranceStartedAtMillis = null;
    _admittedCommandUtteranceId = _commandUtteranceId;
    _clearPerCaptureState();
    _cancelPendingGrammarSwitch(
      StateError('Grammar switch cancelled because recognition stopped'),
    );
    _preRollFrames.clear();
    _clearRecognizerBatch();
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
    final List<PcmFramePair> frames =
        _vadFrames.add(rawBytes, boostedBytes).toList(growable: false);
    if (_commandRecognizer != null) {
      final int potentialCommandBytes = frames.fold<int>(
            0,
            (int total, PcmFramePair frame) =>
                total + frame.boosted.lengthInBytes,
          ) +
          _preRollFrames.fold<int>(
            0,
            (int total, _PcmFrame frame) => total + frame.boosted.lengthInBytes,
          );
      if (!_commandBacklog.canAdmit(potentialCommandBytes)) return false;
    }
    for (final PcmFramePair frame in frames) {
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

  bool processAudioPacketForTest(Uint8List bytes) {
    return _onAudioChunk(bytes, bytes, _captureEpoch.current);
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
      if (!_flushRecognizerBatch()) return false;
      final int endpointDetectedAtMillis =
          DateTime.now().millisecondsSinceEpoch;
      _logVadEvent('VAD_ENDPOINT', segment);
      if (segment.endpointReason == AcousticEndpointReason.silence) {
        _installFreeTextBoundary(_admittedCommandUtteranceId);
        _enqueueSilenceBoundary(
          segment,
          captureEpoch,
          endpointDetectedAtMillis: endpointDetectedAtMillis,
        );
        _admittedCommandUtteranceId++;
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
    if (segment.segmentId > _latestAdmittedSegmentId) {
      _latestAdmittedSegmentId = segment.segmentId;
    }
    final int utteranceId = _admittedCommandUtteranceId;
    final bool sameBatch = _recognizerBatchFrames.isEmpty ||
        (_recognizerBatchCaptureEpoch == captureEpoch &&
            _recognizerBatchUtteranceId == utteranceId &&
            _recognizerBatchSegment?.segmentId == segment.segmentId);
    if (!sameBatch && !_flushRecognizerBatch()) return false;
    if (_recognizerBatchFrames.isEmpty) {
      _recognizerBatchCommandEnabled = _commandRecognizer != null;
    }
    if (_recognizerBatchCommandEnabled &&
        !_commandBacklog.admit(boostedBytes.lengthInBytes)) {
      return false;
    }
    _recognizerBatchCaptureEpoch = captureEpoch;
    _recognizerBatchUtteranceId = utteranceId;
    _recognizerBatchSegment = segment;
    if (_recognizerBatchCommandEnabled) {
      _recognizerBatchCommandBytes += boostedBytes.lengthInBytes;
    }
    _recognizerBatchFrames.add(Uint8List.fromList(boostedBytes));
    if (_recognizerBatchFrames.length < _recognizerBatchFrameCount) return true;
    return _flushRecognizerBatch();
  }

  bool _flushRecognizerBatch() {
    if (_recognizerBatchFrames.isEmpty) return true;
    final int captureEpoch = _recognizerBatchCaptureEpoch!;
    final int utteranceId = _recognizerBatchUtteranceId!;
    final SpeechSegment segment = _recognizerBatchSegment!;
    final int admittedCommandBytes = _recognizerBatchCommandBytes;
    final bool commandEnabled = _recognizerBatchCommandEnabled;
    final int byteCount = _recognizerBatchFrames.fold<int>(
      0,
      (int total, Uint8List frame) => total + frame.lengthInBytes,
    );
    final Uint8List immutableBytes = Uint8List(byteCount);
    int offset = 0;
    for (final Uint8List frame in _recognizerBatchFrames) {
      immutableBytes.setRange(offset, offset + frame.lengthInBytes, frame);
      offset += frame.lengthInBytes;
    }
    _clearRecognizerBatch(releaseCommandBacklog: false);
    final bool hasCommand = commandEnabled && _commandRecognizer != null;
    if (!hasCommand && admittedCommandBytes > 0) {
      _commandBacklog.complete(admittedCommandBytes);
    }
    if (hasCommand) {
      _enqueueCommandChunk(
        immutableBytes,
        captureEpoch,
        segment,
        admitted: admittedCommandBytes > 0,
      );
    }
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

  void _clearRecognizerBatch({bool releaseCommandBacklog = true}) {
    if (releaseCommandBacklog && _recognizerBatchCommandBytes > 0) {
      _commandBacklog.complete(_recognizerBatchCommandBytes);
    }
    _recognizerBatchFrames.clear();
    _recognizerBatchCaptureEpoch = null;
    _recognizerBatchUtteranceId = null;
    _recognizerBatchSegment = null;
    _recognizerBatchCommandBytes = 0;
    _recognizerBatchCommandEnabled = false;
  }

  bool get _usesLiveFreeText =>
      freeTextPipelineMode.usesLiveLane &&
      _freeTextAcceptingPcm &&
      _freeTextRecognizer != null;

  Future<void> processAudioChunk(Uint8List bytes) async {
    final int captureEpoch = _captureEpoch.current;
    final SpeechSegment? segment = _speechSegmenter.add(bytes, captureEpoch);
    if (segment == null) return;
    if (segment.segmentId > _latestAdmittedSegmentId) {
      _latestAdmittedSegmentId = segment.segmentId;
    }
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
      _installFreeTextBoundary(_admittedCommandUtteranceId);
      _enqueueSilenceBoundary(
        segment,
        captureEpoch,
        endpointDetectedAtMillis: DateTime.now().millisecondsSinceEpoch,
      );
      _admittedCommandUtteranceId++;
    }
    if (segment.isEndpoint) await _finishSegment(segment, captureEpoch);
  }

  void _enqueueSilenceBoundary(
    SpeechSegment segment,
    int captureEpoch, {
    required int endpointDetectedAtMillis,
  }) {
    final int expectedUtteranceId = _commandUtteranceId;
    final VoiceRecognizer? expectedRecognizer = _commandRecognizer;
    if (expectedRecognizer == null) return;

    final Future<void> boundary = _commandAudioProcessing.then((_) async {
      try {
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
          endpointDetectedAtMillis: endpointDetectedAtMillis,
        );
      } finally {
        _releaseFreeTextBoundary(expectedUtteranceId);
      }
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
    required int endpointDetectedAtMillis,
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
      await _completeCommandUtterance(
        resultText: text,
        captureEpoch: captureEpoch,
        segment: segment,
        commandUtteranceId: expectedUtteranceId,
        endpointDetectedAtMillis: endpointDetectedAtMillis,
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
    _pendingCommandFrames++;
    final int queuedAt = DateTime.now().millisecondsSinceEpoch;
    final Future<void> next = _commandAudioProcessing.then((_) {
      if (_pendingCommandFrames > 0) _pendingCommandFrames--;
      final VoiceRecognizer? recognizer = _commandRecognizer;
      if (recognizer == null) return Future<void>.value();
      return _processRecognizerChunk(
          source: _RecognitionSource.command,
          recognizer: recognizer,
          bytes: bytes,
          queuedAt: queuedAt,
          epoch: null,
          captureEpoch: captureEpoch,
          segment: segment);
    }).whenComplete(() {
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
    if (_invalidLiveFreeTextUtterances.contains(commandUtteranceId)) {
      return Future<void>.value();
    }
    final VoiceRecognizer? recognizer = _freeTextRecognizer;
    final int epoch = _freeTextEpoch;
    final _VoiceResultContext resultContext =
        _utteranceContexts[commandUtteranceId] ??
            _currentResultContext(commandUtteranceId);
    if (recognizer == null || !_freeTextBacklog.admit(bytes.lengthInBytes)) {
      final String invalidReason = recognizer == null
          ? 'live_lane_not_ready'
          : 'live_lane_backlog_exceeded';
      _invalidLiveFreeTextUtterances.add(commandUtteranceId);
      _liveFreeTextInvalidReasons[commandUtteranceId] = invalidReason;
      _voiceMetrics.recordDroppedFrame();
      print(
        '[VOICE_LIVE_FREE_TEXT] mode=${freeTextPipelineMode.name} '
        'captureEpoch=$captureEpoch segmentId=${segment.segmentId} '
        'utteranceId=$commandUtteranceId chunkId=${segment.lastChunkId} '
        'decision=$invalidReason batchBytes=${bytes.lengthInBytes} '
        'backlogBytes=${_freeTextBacklog.pendingBytes} '
        'recognizerReady=${recognizer != null} epoch=$epoch '
        'freeTextEpoch=$_freeTextEpoch sessionActive=$_isSessionActive',
      );
      return Future<void>.value();
    }
    final int queuedAt = DateTime.now().millisecondsSinceEpoch;
    final _FreeTextBoundary? boundary =
        _freeTextBoundaries.remove(commandUtteranceId);
    final Future<void> predecessor =
        boundary?.predecessor ?? _freeTextAudioProcessing;
    final Future<void> next = predecessor.then((_) async {
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
      _freeTextLiveBatchCount++;
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
      } else {
        final bool shouldPollPartial = queueDelayMs <= 300 &&
            (bytes.lengthInBytes <
                    _vadFrameBytes * _recognizerBatchFrameCount ||
                _freeTextLiveBatchCount.isEven);
        if (shouldPollPartial) {
          final String partialJson = await recognizer.getPartialResult();
          final String partialText = _extractText(
            partialJson,
            preferredKeys: const <String>['partial'],
          );
          if (partialText != _freeTextPartialText &&
              _canProcess(_RecognitionSource.freeText, epoch, captureEpoch) &&
              identical(_freeTextRecognizer, recognizer)) {
            _publishPartialChange(
              source: _RecognitionSource.freeText,
              text: partialText,
              epoch: epoch,
              captureEpoch: captureEpoch,
              segment: segment,
              commandUtteranceId: commandUtteranceId,
              resultContext: resultContext,
            );
            _freeTextPartialText = partialText;
          }
        }
      }
      final bool firstLogForUtterance =
          _loggedLiveFreeTextUtterances.add(commandUtteranceId);
      final bool periodicLog = _freeTextMetrics.processedChunks % 25 == 0;
      final bool slowLog = queueDelayMs > _slowAudioQueueDelayMs ||
          recognizerMs > _slowRecognizerLatencyMs;
      if (firstLogForUtterance || periodicLog || slowLog) {
        final String sample = firstLogForUtterance
            ? 'first'
            : slowLog
                ? 'slow'
                : 'periodic';
        print(
          '[VOICE_LIVE_FREE_TEXT] mode=${freeTextPipelineMode.name} '
          'captureEpoch=$captureEpoch segmentId=${segment.segmentId} '
          'utteranceId=$commandUtteranceId chunkId=${segment.lastChunkId} '
          'processedThroughChunkId=${segment.lastChunkId} sample=$sample '
          'batchBytes=${bytes.lengthInBytes} '
          'batchAudioMs=${bytes.lengthInBytes * 1000 ~/ (_sampleRate * 2)} '
          'queueDelayMs=$queueDelayMs recognizerMs=$recognizerMs '
          'audioLagMs=${finishedAt - queuedAt}',
        );
      }
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
        } else {
          _logCommandOov(resultText, _sourceScreen);
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
          await _completeCommandUtterance(
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

  Future<void> _completeCommandUtterance({
    required String resultText,
    required int captureEpoch,
    required SpeechSegment segment,
    required int commandUtteranceId,
    int? endpointDetectedAtMillis,
  }) async {
    final int? speechStartedAtMillis = _commandUtteranceStartedAtMillis;
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
    if (commandFound &&
        commandUtteranceId > _latestActionableCommandUtteranceId) {
      _latestActionableCommandUtteranceId = commandUtteranceId;
    }
    Future<void>? liveFinalization;
    if (_freeTextEnabled && replay.isNotEmpty) {
      if (_usesLiveFreeText) {
        liveFinalization = _enqueueLiveFreeTextFinalization(
          replay,
          commandText: resultText.isNotEmpty ? resultText : _commandPartialText,
          commandFound: commandFound,
          epoch: _freeTextEpoch,
          captureEpoch: captureEpoch,
          segment: segment,
          commandUtteranceId: commandUtteranceId,
          endpointDetectedAtMillis:
              endpointDetectedAtMillis ?? DateTime.now().millisecondsSinceEpoch,
          speechStartedAtMillis: speechStartedAtMillis,
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
    _finalizeCommandUtterance(applyPendingGrammarSwitch: !_usesLiveFreeText);
    if (liveFinalization != null) await liveFinalization;
    if (_usesLiveFreeText) await _applyPendingGrammarSwitchNow();
  }

  Future<void> _enqueueLiveFreeTextFinalization(
    Uint8List replay, {
    required String commandText,
    required bool commandFound,
    required int epoch,
    required int captureEpoch,
    required SpeechSegment segment,
    required int commandUtteranceId,
    required int endpointDetectedAtMillis,
    int? speechStartedAtMillis,
    _VoiceResultContext? resultContext,
  }) {
    final _FreeTextBoundary? boundary =
        _freeTextBoundaries.remove(commandUtteranceId);
    final Future<void> predecessor =
        boundary?.predecessor ?? _freeTextAudioProcessing;
    final Future<void> next = predecessor.then((_) async {
      final int finalizationStartedAtMillis =
          DateTime.now().millisecondsSinceEpoch;
      final int queueWaitAfterEndpointMs =
          finalizationStartedAtMillis - endpointDetectedAtMillis;
      final VoiceRecognizer? recognizer = _freeTextRecognizer;
      print(
        '[VOICE_DUAL_FINAL_TRACE] stage=predecessor_completed '
        'captureEpoch=$captureEpoch utteranceId=$commandUtteranceId '
        'queueWaitAfterEndpointMs=$queueWaitAfterEndpointMs '
        'boundaryPresent=${boundary != null} '
        'invalid=${_invalidLiveFreeTextUtterances.contains(commandUtteranceId)} '
        'invalidReason=${_liveFreeTextInvalidReasons[commandUtteranceId]} '
        'recognizerReady=${recognizer != null} '
        'backlogBytes=${_freeTextBacklog.pendingBytes}',
      );
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
      final int freeTextFinalAtMillis = DateTime.now().millisecondsSinceEpoch;
      final int freeTextFinalizationMs =
          freeTextFinalAtMillis - finalizationStartedAtMillis;
      final int endpointToFreeTextFinalMs =
          freeTextFinalAtMillis - endpointDetectedAtMillis;
      _voiceMetrics.recordLiveFinalization(
        queueWaitAfterEndpointMs: queueWaitAfterEndpointMs,
        finalizationMs: freeTextFinalizationMs,
        endpointToFreeTextFinalMs: endpointToFreeTextFinalMs,
      );
      _loggedLiveFreeTextUtterances.remove(commandUtteranceId);
      print(
        '[VOICE_DUAL_FINAL] commandText="$commandText" '
        'freeText="$liveText" '
        'freeTextQueueWaitAfterEndpointMs=$queueWaitAfterEndpointMs '
        'freeTextFinalizationMs=$freeTextFinalizationMs '
        'endpointToFreeTextFinalMs=$endpointToFreeTextFinalMs',
      );
      if (freeTextPipelineMode != FreeTextPipelineMode.shadowLive &&
          (_commandUtteranceId != commandUtteranceId + 1 ||
              _latestAdmittedSegmentId > segment.segmentId)) {
        _voiceMetrics.recordStale();
        // ignore: avoid_print
        print(
          '[VOICE_DUAL_FINAL] rejected reason=newer_utterance_started '
          'utteranceId=$commandUtteranceId '
          'currentUtteranceId=$_commandUtteranceId '
          'segmentId=${segment.segmentId} '
          'latestSegmentId=$_latestAdmittedSegmentId',
        );
        return;
      }
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
          await _runFreeTextReplay(
            replay,
            epoch: epoch,
            captureEpoch: captureEpoch,
            segment: segment,
            commandUtteranceId: commandUtteranceId,
            replayContext: _replayContext(
              captureEpoch,
              segment,
              commandUtteranceId,
              resultContext,
            ),
            resultContext: resultContext,
            onCompleted: (String replayText, int replayMs) {
              _logShadowComparison(
                liveText: liveText,
                replayText: replayText,
                liveLatencyMs: endpointToFreeTextFinalMs,
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
          await _runFreeTextReplay(
            replay,
            epoch: epoch,
            captureEpoch: captureEpoch,
            segment: segment,
            commandUtteranceId: commandUtteranceId,
            replayContext: _replayContext(
              captureEpoch,
              segment,
              commandUtteranceId,
              resultContext,
            ),
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
      final VoiceDecisionKind decision = _publishCoordinatedDecision(
        commandText: commandText,
        freeText: liveText,
        captureEpoch: captureEpoch,
        epoch: epoch,
        segment: segment,
        commandUtteranceId: commandUtteranceId,
        resultContext: resultContext,
      );
      final int decisionAtMillis = DateTime.now().millisecondsSinceEpoch;
      final int endpointToDecisionMs =
          decisionAtMillis - endpointDetectedAtMillis;
      final int? speechToPhraseMs = decision == VoiceDecisionKind.dynamicItem &&
              speechStartedAtMillis != null
          ? decisionAtMillis - speechStartedAtMillis
          : null;
      _voiceMetrics.recordDecision(
        endpointToDecisionMs: endpointToDecisionMs,
        speechToPhraseMs: speechToPhraseMs,
      );
      print(
        '[VOICE_DUAL_DECISION] decision=${decision.name} '
        'endpointToDecisionMs=$endpointToDecisionMs '
        'speechToPhraseMs=$speechToPhraseMs',
      );
    }).whenComplete(() {
      _cleanupUtteranceState(commandUtteranceId);
      if (boundary != null && !boundary.gate.isCompleted) {
        boundary.gate.complete();
      }
    });
    final Future<void> guarded = next.catchError(
      (Object error, StackTrace stackTrace) {
        print('[VOICE_DUAL_FINAL] failed: $error\n$stackTrace');
      },
    );
    if (boundary == null) _freeTextAudioProcessing = guarded;
    return guarded;
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
      aliasesOf: (VoiceDynamicItem item) => item.voiceAliases,
    );
    final VoiceListMatch<VoiceDynamicItem> replayMatch = VoiceListMatcher.match(
      replayText,
      items.items,
      (VoiceDynamicItem item) => item.label,
      aliasesOf: (VoiceDynamicItem item) => item.voiceAliases,
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

  VoiceDecisionKind _publishCoordinatedDecision({
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
    final Stopwatch dynamicStopwatch = Stopwatch()..start();
    final VoiceDynamicItemsSnapshot items =
        _dynamicItemsProvider(context.sourceScreen);
    final int snapshotMs = dynamicStopwatch.elapsedMilliseconds;
    dynamicStopwatch.reset();
    final CommandCandidate? commandCandidate = command != null
        ? CommandCandidate(command: command, text: commandText)
        : phraseCommand == null
            ? null
            : CommandCandidate(command: phraseCommand, text: freeText);
    final ({VoiceHintSet hints, bool isReady}) hintLookup =
        _voiceHintsFor(context.sourceScreen, items);
    final VoiceHintSet hintSet = hintLookup.hints;
    final int hintMs = dynamicStopwatch.elapsedMilliseconds;
    dynamicStopwatch.reset();
    final String normalizedFreeText = VoiceListMatcher.normalize(freeText);
    final VoiceListMatch<VoiceDynamicItem> match = VoiceListMatcher.match(
      freeText,
      items.items,
      (VoiceDynamicItem item) => item.label,
      aliasesOf: (VoiceDynamicItem item) => item.voiceAliases,
    );
    final bool isExactHint =
        hintSet.advertisedPhrases.contains(normalizedFreeText) &&
            match.type == VoiceListMatchType.unique;
    final int matchMs = dynamicStopwatch.elapsedMilliseconds;
    if (items.items.length >= 100 || snapshotMs + hintMs + matchMs >= 20) {
      print(
        '[VOICE_DYNAMIC_PERF] phase=final screen=${context.sourceScreen.name} '
        'items=${items.items.length} snapshotMs=$snapshotMs hintMs=$hintMs '
        'matchMs=$matchMs '
        'textLength=${freeText.length} matchType=${match.type.name}',
      );
    }
    final VoiceDecisionContext decisionContext = VoiceDecisionContext(
      key: VoiceUtteranceKey(
        captureEpoch: captureEpoch,
        commandUtteranceId: commandUtteranceId,
        routeRevision: context.routeRevision,
        grammarRevision: context.grammarRevision,
        freeTextEpoch: context.freeTextEpoch,
        sourceScreen: context.sourceScreen,
      ),
      listRevision: context.listRevision,
    );
    final String shadowKey = '$captureEpoch:$commandUtteranceId:'
        '${context.routeRevision}:${context.grammarRevision}:'
        '${context.freeTextEpoch}:${context.sourceScreen.name}';
    final String? shadowItemId = _shadowPartialItemIds[shadowKey];
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
      command: commandCandidate,
      freeText: FreeTextCandidate(
        text: freeText,
        matchType: match.type,
        itemId: match.item?.id,
        isExactHint: isExactHint,
        isStableMatch: shadowItemId != null && shadowItemId == match.item?.id,
      ),
      itemStillExists: (String itemId) =>
          currentItems.items.any((VoiceDynamicItem item) => item.id == itemId),
    );
    _shadowPartialItemIds.remove(shadowKey);
    print(
      '[VOICE_PREVIEW_FINAL_COMPARISON] shadowItemId=$shadowItemId '
      'finalItemId=${match.item?.id} agreement='
      '${shadowItemId != null && shadowItemId == match.item?.id}',
    );
    if (decision.kind == VoiceDecisionKind.command) {
      _emitResult(
        _RecognitionSource.command,
        commandCandidate!.text,
        epoch: null,
        captureEpoch: captureEpoch,
        kind: RecognitionKind.streamFinal,
        segment: segment,
        commandUtteranceId: commandUtteranceId,
        resultContext: context,
      );
    } else if (decision.kind == VoiceDecisionKind.dynamicItem ||
        decision.kind == VoiceDecisionKind.ambiguousRejected) {
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
    return decision.kind;
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
    final VoiceReplayContext replayContext = _replayContext(
      captureEpoch,
      segment,
      commandUtteranceId,
      resultContext,
    );
    final Future<void> next =
        _freeTextAudioProcessing.then((_) => _runFreeTextReplay(
              bytes,
              epoch: epoch,
              captureEpoch: captureEpoch,
              segment: segment,
              commandUtteranceId: commandUtteranceId,
              replayContext: replayContext,
              resultContext: resultContext,
              onCompleted: onCompleted,
            ));
    _freeTextAudioProcessing =
        next.catchError((Object error, StackTrace stack) async {
      print('[VOICE_FREE_TEXT] replay failed: $error\n$stack');
    });
  }

  VoiceReplayContext _replayContext(
    int captureEpoch,
    SpeechSegment segment,
    int commandUtteranceId,
    _VoiceResultContext? resultContext,
  ) {
    final _VoiceResultContext voiceContext =
        resultContext ?? _currentResultContext(commandUtteranceId);
    return VoiceReplayContext(
      captureEpoch: captureEpoch,
      segmentId: segment.segmentId,
      commandUtteranceId: commandUtteranceId,
      sourceScreen: voiceContext.sourceScreen,
      routeRevision: voiceContext.routeRevision,
      grammarRevision: voiceContext.grammarRevision,
      freeTextEpoch: voiceContext.freeTextEpoch,
      listRevision: voiceContext.listRevision,
    );
  }

  Future<void> _runFreeTextReplay(
    Uint8List bytes, {
    required int epoch,
    required int captureEpoch,
    required SpeechSegment segment,
    required int commandUtteranceId,
    required VoiceReplayContext replayContext,
    _VoiceResultContext? resultContext,
    void Function(String text, int replayMs)? onCompleted,
  }) async {
    _replayOwnership.begin(replayContext);
    if (_abortReplayIfInvalid(replayContext)) return;
    final Stopwatch replayClock = Stopwatch()..start();
    final int startedAt = DateTime.now().millisecondsSinceEpoch;
    final int replayBatchCount = (bytes.lengthInBytes + 2559) ~/ 2560;
    final int replayAudioMs = _pcmDurationMillis(bytes.lengthInBytes);
    final Duration replayBudget =
        _freeTextReplayBudgetForBytes(bytes.lengthInBytes);
    print(
      '[VOICE_FREE_TEXT_REPLAY_TRACE] stage=start '
      '${replayContext.describeCaptured()} '
      'utteranceId=$commandUtteranceId replayBytes=${bytes.lengthInBytes} '
      'batchCount=$replayBatchCount audioMs=$replayAudioMs '
      'budgetMs=${replayBudget.inMilliseconds} '
      'operationTimeoutMs=${_segmentCloseGuard.timeout.inMilliseconds} '
      'epoch=$epoch '
      'freeTextEpoch=$_freeTextEpoch '
      'recognizerPresent=${_freeTextRecognizer != null}',
    );
    final Future<void> recognizerReady = _freeTextRecognizerReady;
    try {
      await recognizerReady.timeout(
        _replayOperationTimeout(replayClock, replayBudget),
      );
    } catch (error) {
      if (error is TimeoutException &&
          identical(_freeTextRecognizerReady, recognizerReady)) {
        _freeTextRecognizerReady = Future<void>.value();
      }
      if (_abortReplayIfInvalid(replayContext)) return;
      _replayOwnership.resolve(
        replayContext,
        error is TimeoutException
            ? VoiceReplayOwnershipStatus.timedOut
            : VoiceReplayOwnershipStatus.failed,
        failure: error,
      );
      _logReplayDecision(
        replayContext,
        'failed',
        error is TimeoutException ? 'recognizer_ready_timeout' : 'ready',
      );
      rethrow;
    }
    if (_abortReplayIfInvalid(replayContext)) return;
    print(
      '[VOICE_FREE_TEXT_REPLAY_TRACE] stage=recognizer_ready '
      'utteranceId=$commandUtteranceId elapsedMs='
      '${DateTime.now().millisecondsSinceEpoch - startedAt} '
      'remainingMs=${_remainingReplayBudget(replayClock, replayBudget).inMilliseconds}',
    );
    VoiceRecognizer? recognizer = _freeTextRecognizer;
    if (recognizer == null) {
      try {
        recognizer = await _createFreeTextRecognizerForReplay(
          epoch,
          _replayOperationTimeout(replayClock, replayBudget),
        );
      } catch (error) {
        if (_abortReplayIfInvalid(replayContext)) return;
        _replayOwnership.resolve(
          replayContext,
          error is TimeoutException
              ? VoiceReplayOwnershipStatus.timedOut
              : VoiceReplayOwnershipStatus.failed,
          failure: error,
        );
        _logReplayDecision(replayContext, 'failed', 'recognizer_recovery');
        return;
      }
    }
    if (_abortReplayIfInvalid(replayContext)) return;
    if (recognizer == null) {
      _replayOwnership.resolve(
        replayContext,
        VoiceReplayOwnershipStatus.failed,
        failure: StateError('Free-text recognizer is unavailable'),
      );
      _logReplayDecision(replayContext, 'failed', 'recognizer_unavailable');
      return;
    }
    Future<void>? pendingOperation;
    String stage = 'reset_call';
    int batchIndex = -1;
    try {
      int operationStartedAt = DateTime.now().millisecondsSinceEpoch;
      final Future<void> reset = recognizer.reset();
      print(
        '[VOICE_FREE_TEXT_REPLAY_TRACE] stage=reset_called '
        'utteranceId=$commandUtteranceId callMs='
        '${DateTime.now().millisecondsSinceEpoch - operationStartedAt}',
      );
      pendingOperation = reset;
      stage = 'reset_wait';
      await reset.timeout(_replayOperationTimeout(replayClock, replayBudget));
      if (_abortReplayIfInvalid(replayContext)) return;
      print(
        '[VOICE_FREE_TEXT_REPLAY_TRACE] stage=reset_done '
        'utteranceId=$commandUtteranceId elapsedMs='
        '${DateTime.now().millisecondsSinceEpoch - startedAt} '
        'remainingMs=${_remainingReplayBudget(replayClock, replayBudget).inMilliseconds}',
      );
      const int replayBatchBytes = 2560; // 80 ms at 16 kHz mono PCM16.
      final List<String> results = <String>[];
      for (int offset = 0;
          offset < bytes.lengthInBytes;
          offset += replayBatchBytes) {
        final int requestedEnd = offset + replayBatchBytes;
        final int end = requestedEnd < bytes.lengthInBytes
            ? requestedEnd
            : bytes.lengthInBytes;
        if (_abortReplayIfInvalid(replayContext)) return;
        batchIndex++;
        stage = 'accept_call';
        operationStartedAt = DateTime.now().millisecondsSinceEpoch;
        final Future<bool> accept = recognizer.acceptWaveformBytes(
          Uint8List.sublistView(bytes, offset, end),
        );
        final int callFinishedAt = DateTime.now().millisecondsSinceEpoch;
        print(
          '[VOICE_FREE_TEXT_REPLAY_TRACE] stage=accept_called '
          'utteranceId=$commandUtteranceId batch=$batchIndex/'
          '$replayBatchCount offset=$offset bytes=${end - offset} '
          'callMs=${callFinishedAt - operationStartedAt} '
          'elapsedMs=${callFinishedAt - startedAt} '
          'remainingMs=${_remainingReplayBudget(replayClock, replayBudget).inMilliseconds}',
        );
        pendingOperation = accept.then<void>((_) {});
        stage = 'accept_wait';
        final bool endpoint = await accept.timeout(
          _replayOperationTimeout(replayClock, replayBudget),
        );
        final int acceptFinishedAt = DateTime.now().millisecondsSinceEpoch;
        _voiceMetrics.recordReplayAcceptLatency(
          acceptFinishedAt - callFinishedAt,
        );
        if (_abortReplayIfInvalid(replayContext)) return;
        print(
          '[VOICE_FREE_TEXT_REPLAY_TRACE] stage=accept_done '
          'utteranceId=$commandUtteranceId batch=$batchIndex/'
          '$replayBatchCount endpoint=$endpoint '
          'awaitMs=${acceptFinishedAt - callFinishedAt} '
          'elapsedMs=${acceptFinishedAt - startedAt} '
          'remainingMs=${_remainingReplayBudget(replayClock, replayBudget).inMilliseconds}',
        );
        if (endpoint) {
          stage = 'endpoint_result_call';
          operationStartedAt = DateTime.now().millisecondsSinceEpoch;
          final Future<String> endpointResult = recognizer.getResult();
          print(
            '[VOICE_FREE_TEXT_REPLAY_TRACE] stage=endpoint_result_called '
            'utteranceId=$commandUtteranceId batch=$batchIndex '
            'callMs=${DateTime.now().millisecondsSinceEpoch - operationStartedAt}',
          );
          pendingOperation = endpointResult.then<void>((_) {});
          stage = 'endpoint_result_wait';
          final String endpointJson = await endpointResult.timeout(
            _replayOperationTimeout(replayClock, replayBudget),
          );
          if (_abortReplayIfInvalid(replayContext)) return;
          final String endpointText =
              _extractText(endpointJson, preferredKeys: const <String>['text']);
          if (endpointText.isNotEmpty) results.add(endpointText);
        }
      }
      if (_abortReplayIfInvalid(replayContext)) return;
      stage = 'final_result_call';
      operationStartedAt = DateTime.now().millisecondsSinceEpoch;
      final Future<String> finalResult = recognizer.getFinalResult();
      print(
        '[VOICE_FREE_TEXT_REPLAY_TRACE] stage=final_result_called '
        'utteranceId=$commandUtteranceId callMs='
        '${DateTime.now().millisecondsSinceEpoch - operationStartedAt} '
        'elapsedMs=${DateTime.now().millisecondsSinceEpoch - startedAt}',
      );
      pendingOperation = finalResult.then<void>((_) {});
      stage = 'final_result_wait';
      final String json = await finalResult.timeout(
        _replayOperationTimeout(replayClock, replayBudget),
      );
      if (_abortReplayIfInvalid(replayContext)) return;
      final String tail =
          _extractText(json, preferredKeys: const <String>['text']);
      if (tail.isNotEmpty) results.add(tail);
      final String text = results.join(' ').trim();
      final int replayMs = DateTime.now().millisecondsSinceEpoch - startedAt;
      print(
        '[VOICE_FREE_TEXT_REPLAY_TRACE] stage=final_result_done '
        'utteranceId=$commandUtteranceId text="$text" replayMs=$replayMs',
      );
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
          resultContext: resultContext,
        );
        _replayOwnership.resolve(
          replayContext,
          VoiceReplayOwnershipStatus.resolvedAsDynamicPhrase,
        );
        _logReplayDecision(replayContext, 'accepted', 'dynamic_phrase');
      } else {
        _replayOwnership.resolve(
          replayContext,
          VoiceReplayOwnershipStatus.resolvedEmpty,
        );
        _logReplayDecision(replayContext, 'rejected', 'empty_result');
      }
      print(
        '[VOICE_FREE_TEXT] replayBytes=${bytes.lengthInBytes} '
        'replayMs=$replayMs',
      );
    } catch (error, stackTrace) {
      print(
        '[VOICE_FREE_TEXT_REPLAY_TRACE] stage=failed operation=$stage '
        '${replayContext.describeCaptured()} '
        'batch=$batchIndex/$replayBatchCount '
        'elapsedMs=${DateTime.now().millisecondsSinceEpoch - startedAt} '
        'remainingMs=${_remainingReplayBudget(replayClock, replayBudget).inMilliseconds} '
        'error=$error\n$stackTrace',
      );
      _logReplayDecision(
        replayContext,
        'failed',
        error is TimeoutException ? 'timeout' : stage,
      );
      _replayOwnership.resolve(
        replayContext,
        error is TimeoutException
            ? VoiceReplayOwnershipStatus.timedOut
            : VoiceReplayOwnershipStatus.failed,
        failure: error,
      );
      await _replaceUncertainFreeTextRecognizer(
        failedRecognizer: recognizer,
        pendingOperation: pendingOperation,
        recognizerEpoch: epoch,
      );
      rethrow;
    }
  }

  bool _abortReplayIfInvalid(VoiceReplayContext context) {
    final VoiceReplayOwnership? ownership = _replayOwnership.stateFor(context);
    if (ownership?.isTerminal == true) return true;
    final int latestActionable = _latestActionableCommandUtteranceId;
    if (latestActionable > context.commandUtteranceId) {
      _supersedeReplay(context, supersededBy: latestActionable);
      return true;
    }
    final VoiceReplayContextCancellation? staleReason =
        _replayStaleReason(context);
    if (staleReason != null) {
      _rejectReplay(context, staleReason);
      return true;
    }
    return false;
  }

  VoiceReplayContextCancellation? _replayStaleReason(
    VoiceReplayContext context,
  ) {
    if (!_isSessionActive) return VoiceReplayContextCancellation.sessionStopped;
    if (!_captureEpoch.isCurrent(context.captureEpoch)) {
      return VoiceReplayContextCancellation.captureChanged;
    }
    if (!_freeTextEnabled || context.freeTextEpoch != _freeTextEpoch) {
      return VoiceReplayContextCancellation.freeTextChanged;
    }
    if (context.sourceScreen != _sourceScreen) {
      return VoiceReplayContextCancellation.screenChanged;
    }
    if (context.routeRevision != _routeRevision) {
      return VoiceReplayContextCancellation.routeChanged;
    }
    if (context.grammarRevision != _grammarRevision) {
      return VoiceReplayContextCancellation.grammarChanged;
    }
    if (context.listRevision != _dynamicItemsProvider(_sourceScreen).revision) {
      return VoiceReplayContextCancellation.dynamicItemsChanged;
    }
    return null;
  }

  void _rejectReplay(
    VoiceReplayContext context,
    VoiceReplayContextCancellation reason,
  ) {
    _voiceMetrics.recordStale();
    _replayOwnership.resolve(
      context,
      VoiceReplayOwnershipStatus.cancelledByContextChange,
      cancellation: reason,
    );
    _logReplayDecision(context, 'rejected', reason.name);
  }

  void _supersedeReplay(
    VoiceReplayContext context, {
    int? supersededBy,
  }) {
    _voiceMetrics.recordStale();
    _replayOwnership.resolve(
      context,
      VoiceReplayOwnershipStatus.supersededByActionableUtterance,
      supersededByUtteranceId: supersededBy,
    );
    _logReplayDecision(
      context,
      'rejected',
      'newer_actionable_command',
      supersededBy: supersededBy,
    );
  }

  void _logReplayDecision(
    VoiceReplayContext context,
    String outcome,
    String reason, {
    int? supersededBy,
  }) {
    print(
      '[VOICE_FREE_TEXT_REPLAY_TRACE] stage=decision_$outcome reason=$reason '
      '${context.describeCaptured()} ${context.describeCurrent(this)} '
      'supersededBy=${supersededBy ?? 0}',
    );
  }

  int _pcmDurationMillis(int byteLength) {
    if (byteLength <= 0) return 0;
    return byteLength * 1000 ~/ (_sampleRate * 2);
  }

  Duration _freeTextReplayBudgetForBytes(int byteLength) {
    final int requested =
        _pcmDurationMillis(byteLength) + _freeTextReplayHeadroom.inMilliseconds;
    final int minimum = _minimumFreeTextReplayBudget.inMilliseconds;
    final int maximum = _maximumFreeTextReplayBudget.inMilliseconds;
    final int bounded = requested < minimum
        ? minimum
        : requested > maximum
            ? maximum
            : requested;
    return Duration(milliseconds: bounded);
  }

  Duration _remainingReplayBudget(
    Stopwatch replayClock,
    Duration replayBudget,
  ) {
    final int remaining =
        replayBudget.inMilliseconds - replayClock.elapsedMilliseconds;
    return Duration(milliseconds: remaining > 0 ? remaining : 0);
  }

  Duration _replayOperationTimeout(
    Stopwatch replayClock,
    Duration replayBudget,
  ) {
    final int remaining =
        _remainingReplayBudget(replayClock, replayBudget).inMilliseconds;
    final int operationTimeout = _segmentCloseGuard.timeout.inMilliseconds;
    final int bounded =
        remaining < operationTimeout ? remaining : operationTimeout;
    return Duration(milliseconds: bounded > 0 ? bounded : 0);
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
    VoiceRecognizer? replacement;
    try {
      replacement = await _createFreeTextRecognizer(
        _segmentCloseGuard.timeout,
      );
    } catch (error, stackTrace) {
      print(
        '[VOICE_FREE_TEXT] recognizer replacement failed: '
        '$error\n$stackTrace',
      );
      return;
    }
    if (recognizerEpoch == _freeTextEpoch &&
        _freeTextEnabled &&
        _freeTextRecognizer == null) {
      _freeTextRecognizer = replacement;
    } else {
      await replacement.dispose();
    }
  }

  Future<VoiceRecognizer?> _createFreeTextRecognizerForReplay(
    int recognizerEpoch,
    Duration timeout,
  ) async {
    if (recognizerEpoch != _freeTextEpoch || !_freeTextEnabled) return null;
    final VoiceRecognizer replacement =
        await _createFreeTextRecognizer(timeout);
    if (recognizerEpoch == _freeTextEpoch &&
        _freeTextEnabled &&
        _freeTextRecognizer == null) {
      _freeTextRecognizer = replacement;
      return replacement;
    }
    await replacement.dispose();
    return _freeTextRecognizer;
  }

  Future<VoiceRecognizer> _createFreeTextRecognizer(Duration timeout) async {
    final Future<VoiceRecognizer> creation =
        _createRecognizer(_RecognitionSource.freeText);
    var timedOut = false;
    try {
      return await creation.timeout(timeout);
    } on TimeoutException {
      timedOut = true;
      rethrow;
    } finally {
      if (timedOut) {
        unawaited(creation.then((VoiceRecognizer recognizer) {
          return recognizer.dispose();
        }).catchError((Object _, StackTrace __) {}));
      }
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
      listRevision: _dynamicItemsProvider(_sourceScreen).revision,
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
    String? dynamicItemId,
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
      final int recognizedAtMillis = DateTime.now().millisecondsSinceEpoch;
      final int listRevision =
          source == _RecognitionSource.freeText || dynamicItemId != null
              ? context.listRevision
              : 0;
      final WearVoiceCommand? parsedCommand =
          source == _RecognitionSource.command
              ? _commandParser.parseExactForScreen(context.sourceScreen, text)
              : null;
      if (source == _RecognitionSource.command &&
          kind != RecognitionKind.partial &&
          text.trim().isNotEmpty) {
        _logCommandOov(text, context.sourceScreen);
      }
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
          recognizedAtMillis: recognizedAtMillis,
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
        partialRevision: source == _RecognitionSource.command
            ? _commandPartialRevision
            : _freeTextPartialRevision,
        commandUtteranceStartedAtMillis: context.startedAtMillis,
        freeTextEpoch: context.freeTextEpoch,
        isLiveFreeText: isLiveFreeText,
        recognizedAtMillis: recognizedAtMillis,
        listRevision: listRevision,
        dynamicItemId: dynamicItemId,
      ));
    }
  }

  void _publishPartialChange({
    required _RecognitionSource source,
    required String text,
    required int? epoch,
    required int? captureEpoch,
    required SpeechSegment segment,
    int? commandUtteranceId,
    _VoiceResultContext? resultContext,
  }) {
    final _VoiceResultContext context = resultContext ??
        _currentResultContext(commandUtteranceId ?? _commandUtteranceId);
    final String normalized = VoiceListMatcher.normalize(text);
    final bool isFixedCommand =
        _actionCatalog.resolve(context.sourceScreen, normalized) != null;
    if (normalized.isEmpty || isFixedCommand) {
      if (source == _RecognitionSource.command) {
        _commandPartialRevision++;
      } else {
        _freeTextPartialRevision++;
        if (freeTextPipelineMode == FreeTextPipelineMode.shadowLive) return;
      }
      _emitResult(
        source,
        text,
        epoch: epoch,
        captureEpoch: captureEpoch,
        kind: RecognitionKind.partial,
        segment: segment,
        commandUtteranceId: commandUtteranceId,
        resultContext: context,
      );
      return;
    }
    final Stopwatch dynamicStopwatch = Stopwatch()..start();
    final VoiceDynamicItemsSnapshot items =
        _dynamicItemsProvider(context.sourceScreen);
    final int snapshotMs = dynamicStopwatch.elapsedMilliseconds;
    dynamicStopwatch.reset();
    final VoiceHintSet? hints = source == _RecognitionSource.command
        ? _voiceHintsFor(context.sourceScreen, items).hints
        : null;
    final int hintMs = dynamicStopwatch.elapsedMilliseconds;
    dynamicStopwatch.reset();
    final bool shouldMatch = source == _RecognitionSource.freeText ||
        hints!.advertisedPhrases.contains(normalized);
    final VoiceListMatch<VoiceDynamicItem> match = shouldMatch
        ? VoiceListMatcher.match(
            text,
            items.items,
            (VoiceDynamicItem item) => item.label,
            aliasesOf: (VoiceDynamicItem item) => item.voiceAliases,
          )
        : VoiceListMatch<VoiceDynamicItem>.none();
    final int matchMs = dynamicStopwatch.elapsedMilliseconds;
    if (items.items.length >= 100 || snapshotMs + matchMs + hintMs >= 20) {
      print(
        '[VOICE_DYNAMIC_PERF] phase=partial screen=${context.sourceScreen.name} '
        'lane=${source.label} items=${items.items.length} '
        'snapshotMs=$snapshotMs matchMs=$matchMs hintMs=$hintMs '
        'textLength=${text.length} matchType=${match.type.name}',
      );
    }
    String? dynamicItemId;
    if (source == _RecognitionSource.command) {
      if (hints!.advertisedPhrases.contains(normalized) &&
          match.type == VoiceListMatchType.unique) {
        dynamicItemId = match.item!.id;
      }
    } else if (match.type == VoiceListMatchType.unique) {
      dynamicItemId = match.item!.id;
    }
    if (source == _RecognitionSource.command) {
      _commandPartialRevision++;
    } else {
      _freeTextPartialRevision++;
      final String key = '${captureEpoch ?? segment.captureEpoch}:'
          '${commandUtteranceId ?? _commandUtteranceId}:'
          '${context.routeRevision}:${context.grammarRevision}:'
          '${context.freeTextEpoch}:${context.sourceScreen.name}';
      if (match.type == VoiceListMatchType.unique) {
        _shadowPartialItemIds[key] = match.item!.id;
      }
      while (_shadowPartialItemIds.length > 128) {
        _shadowPartialItemIds.remove(_shadowPartialItemIds.keys.first);
      }
      print(
        '[VOICE_DYNAMIC_PARTIAL_SHADOW] text="$text" '
        'matchType=${match.type.name} itemId=${match.item?.id} '
        'listRevision=${items.revision} '
        'partialRevision=$_freeTextPartialRevision',
      );
      if (freeTextPipelineMode == FreeTextPipelineMode.shadowLive) return;
    }
    _emitResult(
      source,
      text,
      epoch: epoch,
      captureEpoch: captureEpoch,
      kind: RecognitionKind.partial,
      segment: segment,
      commandUtteranceId: commandUtteranceId,
      resultContext: context,
      dynamicItemId: dynamicItemId,
    );
  }

  ({VoiceHintSet hints, bool isReady}) _voiceHintsFor(
    WearScreenId screen,
    VoiceDynamicItemsSnapshot items,
  ) {
    final Set<String> reservedPhrases = _actionCatalog.phrasesFor(screen);
    final VoiceHintSet? ready = _voiceHintIndexCache.getIfReady(
      snapshot: items,
      screen: screen.name,
      reservedPhrases: reservedPhrases,
    );
    if (ready != null) return (hints: ready, isReady: true);
    return (
      hints: VoiceHintSet(
        revision: items.revision,
        hintsByItemId: const <String, VoiceHint>{},
        advertisedPhrases: const <String>{},
        issues: const <VoiceHintValidationIssue>[],
      ),
      isReady: false,
    );
  }

  void _finalizeCommandUtterance({
    bool clearPartial = true,
    bool applyPendingGrammarSwitch = true,
  }) {
    _utterancePcm.clear();
    if (clearPartial) _commandPartialText = '';
    _freeTextPartialText = '';
    _freeTextLiveBatchCount = 0;
    _commandUtteranceStartedAtMillis = null;
    _naturalCommandFinals.remove(_commandUtteranceId);
    _commandUtteranceId++;
    if (!applyPendingGrammarSwitch) return;
    final pending = _pendingGrammarSwitch;
    _pendingGrammarSwitch = null;
    if (pending != null) {
      unawaited(switchCommandGrammar(
        screen: pending.screen,
        grammar: pending.grammar,
      ).then((_) {
        for (final Completer<void> waiter in pending.waiters) {
          if (!waiter.isCompleted) waiter.complete();
        }
      }, onError: (Object error, StackTrace stackTrace) {
        for (final Completer<void> waiter in pending.waiters) {
          if (!waiter.isCompleted) waiter.completeError(error, stackTrace);
        }
      }));
    }
  }

  Future<void> _applyPendingGrammarSwitchNow() async {
    final pending = _pendingGrammarSwitch;
    _pendingGrammarSwitch = null;
    if (pending == null) return;
    try {
      if (_sourceScreen != pending.screen ||
          !_sameGrammar(_commandGrammar, pending.grammar)) {
        VoiceRecognizer? recognizer = _commandRecognizer;
        if (recognizer != null) {
          try {
            await _configureCommandRecognizer(recognizer, pending.grammar);
          } catch (_) {
            if (!identical(_commandRecognizer, recognizer)) rethrow;
            _commandRecognizer = null;
            recognizer = await _recoverCommandRecognizer(recognizer);
            try {
              await _configureCommandRecognizer(recognizer, pending.grammar);
            } catch (_) {
              if (identical(_commandRecognizer, recognizer)) {
                _commandRecognizer = null;
              }
              rethrow;
            }
          }
        }
        _freeTextEpoch++;
        _freeTextPartialText = '';
        _sourceScreen = pending.screen;
        _commandGrammar = pending.grammar;
        final int routeRevision = ++_routeRevision;
        final int grammarRevision = ++_grammarRevision;
        print(
          '[VOICE_GRAMMAR] screen=${pending.screen} '
          'routeRevision=$routeRevision grammarRevision=$grammarRevision '
          'phrases=${pending.grammar.length} switchOwner=utterance_boundary',
        );
      }
      for (final Completer<void> waiter in pending.waiters) {
        if (!waiter.isCompleted) waiter.complete();
      }
    } catch (error, stackTrace) {
      for (final Completer<void> waiter in pending.waiters) {
        if (!waiter.isCompleted) waiter.completeError(error, stackTrace);
      }
      rethrow;
    }
  }

  void _installFreeTextBoundary(int utteranceId) {
    if (!_usesLiveFreeText || _freeTextBoundaries.containsKey(utteranceId)) {
      return;
    }
    final Future<void> predecessor = _freeTextAudioProcessing;
    final Completer<void> gate = Completer<void>();
    _freeTextBoundaries[utteranceId] =
        _FreeTextBoundary(predecessor: predecessor, gate: gate);
    _freeTextAudioProcessing = predecessor.then((_) => gate.future);
  }

  void _releaseFreeTextBoundary(int utteranceId) {
    final _FreeTextBoundary? boundary = _freeTextBoundaries.remove(utteranceId);
    if (boundary != null && !boundary.gate.isCompleted) {
      boundary.gate.complete();
    }
  }

  void _clearPerCaptureState() {
    _commandPartialText = '';
    _freeTextPartialText = '';
    _naturalCommandFinals.clear();
    _utteranceContexts.clear();
    _liveFreeTextResults.clear();
    _invalidLiveFreeTextUtterances.clear();
    _loggedLiveFreeTextUtterances.clear();
    _liveFreeTextInvalidReasons.clear();
    _shadowPartialItemIds.clear();
    for (final _FreeTextBoundary boundary in _freeTextBoundaries.values) {
      if (!boundary.gate.isCompleted) boundary.gate.complete();
    }
    _freeTextBoundaries.clear();
  }

  void _cleanupUtteranceState(int utteranceId) {
    _utteranceContexts.remove(utteranceId);
    _naturalCommandFinals.remove(utteranceId);
    _liveFreeTextResults.remove(utteranceId);
    _invalidLiveFreeTextUtterances.remove(utteranceId);
    _loggedLiveFreeTextUtterances.remove(utteranceId);
    _liveFreeTextInvalidReasons.remove(utteranceId);
  }

  void _cancelPendingGrammarSwitch(Object error) {
    final pending = _pendingGrammarSwitch;
    _pendingGrammarSwitch = null;
    if (pending == null) return;
    for (final Completer<void> waiter in pending.waiters) {
      if (!waiter.isCompleted) waiter.completeError(error);
    }
  }

  void _logCommandOov(String text, WearScreenId screen) {
    final String normalized = VoiceListMatcher.normalize(text);
    if (normalized.isEmpty ||
        _commandGrammar.any((String phrase) =>
            VoiceListMatcher.normalize(phrase) == normalized)) {
      return;
    }
    // ignore: avoid_print
    print('[VOICE_GRAMMAR_OOV] screen=${screen.name} text="$normalized"');
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

    final VoiceRecognizer replacement =
        await _createRecognizer(_RecognitionSource.command);
    _commandRecognizer ??= replacement;
    if (!identical(_commandRecognizer, replacement)) {
      await replacement.dispose();
    }
    if (_commandUtteranceId == expectedUtteranceId) {
      _finalizeCommandUtterance();
    }
    print(
      '[VOICE_BOUNDARY] commandUtteranceId=$expectedUtteranceId '
      'recognizerReplaced=true',
    );
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
      final VoiceRecognizer replacement =
          await _createRecognizer(_RecognitionSource.command);
      _commandRecognizer ??= replacement;
      if (!identical(_commandRecognizer, replacement)) {
        await replacement.dispose();
      }
    }
    if ((_freeTextEnabled || freeTextPipelineMode.usesLiveLane) &&
        _freeTextRecognizer == null) {
      final VoiceRecognizer replacement =
          await _createRecognizer(_RecognitionSource.freeText);
      if ((_freeTextEnabled || freeTextPipelineMode.usesLiveLane) &&
          _freeTextRecognizer == null) {
        _freeTextRecognizer = replacement;
      } else {
        await replacement.dispose();
      }
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
      try {
        if (source == _RecognitionSource.command) {
          await recognizer.setGrammar(_commandGrammar);
        } else if (freeTextPipelineMode.usesLiveLane) {
          await _warmUpFreeTextRecognizer(recognizer);
        }
      } catch (_) {
        await recognizer.dispose();
        rethrow;
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
      try {
        if (freeTextPipelineMode.usesLiveLane) {
          await _warmUpFreeTextRecognizer(recognizer);
        }
      } catch (_) {
        await recognizer.dispose();
        rethrow;
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
    VoiceRecognizer? createdCommand;
    VoiceRecognizer? createdFreeText;
    try {
      if (_commandGrammar.isNotEmpty) {
        createdCommand = await _createRecognizer(_RecognitionSource.command);
        _commandRecognizer ??= createdCommand;
        if (!identical(_commandRecognizer, createdCommand)) {
          await createdCommand.dispose();
          createdCommand = null;
        }
      }
      if (_freeTextEnabled) {
        createdFreeText = await _createRecognizer(_RecognitionSource.freeText);
        if (_freeTextEnabled && _freeTextRecognizer == null) {
          _freeTextRecognizer = createdFreeText;
        } else {
          await createdFreeText.dispose();
          createdFreeText = null;
        }
      }
    } catch (_) {
      if (identical(_commandRecognizer, createdCommand)) {
        _commandRecognizer = null;
        await createdCommand?.dispose();
      }
      if (identical(_freeTextRecognizer, createdFreeText)) {
        _freeTextRecognizer = null;
        await createdFreeText?.dispose();
      }
      rethrow;
    }
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
    await _replayOwnership.dispose();
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
    required this.listRevision,
  });

  final int commandUtteranceId;
  final int routeRevision;
  final int grammarRevision;
  final int freeTextEpoch;
  final WearScreenId sourceScreen;
  final int? startedAtMillis;
  final int listRevision;
}

extension on VoiceReplayContext {
  String describeCaptured() => 'captureEpoch=$captureEpoch '
      'segmentId=$segmentId utteranceId=$commandUtteranceId '
      'sourceScreen=${sourceScreen.name} routeRevision=$routeRevision '
      'grammarRevision=$grammarRevision freeTextEpoch=$freeTextEpoch '
      'listRevision=$listRevision';

  String describeCurrent(SpeechRecognitionService service) =>
      'currentCaptureEpoch=${service.captureEpoch} '
      'currentUtteranceId=${service.commandUtteranceId} '
      'currentScreen=${service.sourceScreen.name} '
      'currentRouteRevision=${service.routeRevision} '
      'currentGrammarRevision=${service.grammarRevision} '
      'currentFreeTextEpoch=${service.freeTextEpoch} '
      'currentListRevision=${service.currentDynamicItemsRevision}';
}

class _FreeTextBoundary {
  const _FreeTextBoundary({required this.predecessor, required this.gate});

  final Future<void> predecessor;
  final Completer<void> gate;
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
