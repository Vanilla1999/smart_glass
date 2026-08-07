import 'dart:async';

import 'package:smart_glasses/modules/wear/domain/service/voice_command/recognition_arbiter.dart';
import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/voice_action_catalog.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/voice_command_parser_service.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/wear_voice_command.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/wear_voice_command_event.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/wear_voice_phrase_event.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/wear_voice_preview_event.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/wear_voice_delay_event.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/wear_voice_replay_feedback_controller.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/voice_search_phrase_policy.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_typing/segmented_recognition_result.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_typing/speech_recognition_service.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_typing/voice_replay_ownership.dart';

typedef WearVoiceClock = int Function();
typedef WearVoiceTimerFactory = Timer Function(
  Duration duration,
  void Function() callback,
);

class WearVoiceControlService {
  WearVoiceControlService({
    required SpeechRecognitionService speechRecognitionService,
    VoiceCommandParserService? commandParserService,
    VoiceActionCatalog? actionCatalog,
    WearScreenId Function()? screenProvider,
    WearVoiceClock? clock,
    WearVoiceTimerFactory? timerFactory,
  })  : _speechRecognitionService = speechRecognitionService,
        _arbiter = RecognitionArbiter(
          actionCatalog: actionCatalog,
          screenProvider: screenProvider,
          routeRevisionProvider: () => speechRecognitionService.routeRevision,
          grammarRevisionProvider: () =>
              speechRecognitionService.grammarRevision,
          freeTextEpochProvider: () => speechRecognitionService.freeTextEpoch,
        ),
        _clock = clock ?? (() => DateTime.now().millisecondsSinceEpoch),
        _timerFactory = timerFactory ?? Timer.new {
    _replayFeedbackController = WearVoiceReplayFeedbackController(
      onEvent: _publishDelayEvent,
      timerFactory: _timerFactory,
    );
    _replayOwnershipSubscription =
        _speechRecognitionService.replayOwnershipStream.listen(
      _onReplayOwnership,
      onError: (Object error, StackTrace stackTrace) {
        print(
          '[WearVoiceControlService] replay ownership stream error: '
          '$error\n$stackTrace',
        );
      },
    );
    print('[WearVoiceControlService] subscribing to ASR results');
    _recognitionSubscription =
        _speechRecognitionService.segmentedResultsStream.listen(
      _onRecognitionResult,
      onError: _onRecognitionError,
      onDone: () => print(
        '[WearVoiceControlService] segmented results stream done',
      ),
    );
    _segmentEndedSubscription =
        _speechRecognitionService.segmentEndedStream.listen(
      _onSegmentEnded,
      onError: _onRecognitionError,
    );
    _segmentStartedSubscription =
        _speechRecognitionService.segmentStartedStream.listen(
      _onSegmentStarted,
      onError: _onRecognitionError,
    );
  }

  final SpeechRecognitionService _speechRecognitionService;
  final RecognitionArbiter _arbiter;
  final WearVoiceClock _clock;
  final WearVoiceTimerFactory _timerFactory;
  late final WearVoiceReplayFeedbackController _replayFeedbackController;
  final StreamController<WearVoiceCommand> _commandController =
      StreamController<WearVoiceCommand>.broadcast();
  final StreamController<WearVoiceCommandEvent> _commandEventController =
      StreamController<WearVoiceCommandEvent>.broadcast();
  final StreamController<String> _phraseController =
      StreamController<String>.broadcast();
  final StreamController<WearVoicePhraseEvent> _phraseEventController =
      StreamController<WearVoicePhraseEvent>.broadcast();
  final StreamController<WearVoicePreviewEvent> _previewEventController =
      StreamController<WearVoicePreviewEvent>.broadcast();
  final StreamController<WearVoiceDelayEvent> _delayEventController =
      StreamController<WearVoiceDelayEvent>.broadcast();
  StreamSubscription<SegmentedRecognitionResult>? _recognitionSubscription;
  StreamSubscription<SpeechSegmentStarted>? _segmentStartedSubscription;
  StreamSubscription<SpeechSegmentEnded>? _segmentEndedSubscription;
  StreamSubscription<VoiceReplayOwnership>? _replayOwnershipSubscription;
  final Set<String> _feedbackEligibleUtterances = <String>{};
  int _emittedCommandSeq = 0;
  final Map<String, int> _segmentStartedAt = <String, int>{};
  final Map<String, Timer> _stabilityTimers = <String, Timer>{};
  final Map<String, int> _latestPartialRevisions = <String, int>{};
  final Map<String, _PreviewStabilityState> _previewStates =
      <String, _PreviewStabilityState>{};
  Timer? _recognitionPreviewTimeout;
  bool _recognitionDelayVisible = false;
  _RecognitionDelayContext? _recognitionDelayContext;
  static const Duration _stablePartialDelay = Duration(milliseconds: 150);
  static const Duration _recognitionPreviewDuration = Duration(seconds: 3);

  Stream<WearVoiceCommand> get commandStream => _commandController.stream;
  Stream<WearVoiceCommandEvent> get commandEventStream =>
      _commandEventController.stream;
  Stream<String> get phraseStream => _phraseController.stream;
  Stream<WearVoicePhraseEvent> get phraseEventStream =>
      _phraseEventController.stream;
  Stream<WearVoicePreviewEvent> get previewEventStream =>
      _previewEventController.stream;
  Stream<WearVoiceDelayEvent> get delayEventStream =>
      _delayEventController.stream;
  int get debugRetainedPartialRevisionCount => _latestPartialRevisions.length;

  void _onRecognitionResult(SegmentedRecognitionResult result) {
    if (result.lane == RecognitionLane.command &&
        VoiceSearchPhrasePolicy.isMeaningful(result.text)) {
      _feedbackEligibleUtterances.add(_feedbackUtteranceKey(
        result.captureEpoch,
        result.commandUtteranceId,
      ));
      while (_feedbackEligibleUtterances.length > 128) {
        _feedbackEligibleUtterances.remove(
          _feedbackEligibleUtterances.first,
        );
      }
    }
    final String timerKey = '${result.lane.name}:${result.captureEpoch}:'
        '${result.commandUtteranceId}:${result.routeRevision}:'
        '${result.grammarRevision}:${result.freeTextEpoch}:'
        '${result.sourceScreen.name}';
    final RecognitionArbitration? outcome = _arbiter.accept(result);
    if (result.kind == RecognitionKind.partial &&
        result.dynamicItemId == null) {
      _cancelPendingPreview(result);
    }
    if (outcome?.ignoredEndpointOnly ?? false) return;
    if (result.kind == RecognitionKind.partial) {
      _stabilityTimers.remove(timerKey)?.cancel();
      _latestPartialRevisions[timerKey] = result.partialRevision;
      while (_latestPartialRevisions.length > 128) {
        _latestPartialRevisions.remove(_latestPartialRevisions.keys.first);
      }
    } else {
      _cancelUtteranceStabilityTimers(result);
    }
    if (outcome == null) return;
    if (outcome.stableCandidate
        case final SegmentedRecognitionResult candidate) {
      final String key = timerKey;
      _stabilityTimers.remove(key)?.cancel();
      final int expectedPartialRevision = candidate.partialRevision;
      _stabilityTimers[key] = _timerFactory(_stablePartialDelay, () {
        _stabilityTimers.remove(key);
        if (_latestPartialRevisions[key] != expectedPartialRevision) return;
        final RecognitionArbitration? stable = _arbiter.claimStable(candidate);
        if (stable?.command case final WearVoiceCommand command) {
          _emitCommand(
            command,
            result: candidate,
            source: 'stable_partial',
          );
        }
      });
      return;
    }
    if (outcome.command case final WearVoiceCommand command) {
      _clearRecognitionDelay(result: result);
      _emitCommand(
        command,
        result: result,
        source: result.kind.name,
      );
      return;
    }
    if (outcome.preview case final SegmentedRecognitionResult preview) {
      _schedulePreview(preview);
      return;
    }
    if (outcome.phrase case final SegmentedRecognitionResult phrase) {
      _clearRecognitionDelay(result: phrase);
      _emitPhrase(phrase);
    }
  }

  void _onSegmentEnded(SpeechSegmentEnded ended) {
    try {
      final RecognitionArbitration? outcome = _arbiter.endSegment(ended);
      if (outcome?.command case final WearVoiceCommand command) {
        _emitCommand(
          command,
          result: null,
          source: 'segment_final',
        );
        return;
      }
      if (outcome?.phrase case final SegmentedRecognitionResult phrase) {
        _emitPhrase(phrase);
      }
    } finally {
      _clearRecognitionDelay(ended: ended);
      _segmentStartedAt.remove('${ended.captureEpoch}:${ended.segmentId}');
    }
  }

  void _emitCommand(
    WearVoiceCommand cmd, {
    required SegmentedRecognitionResult? result,
    String source = 'final',
  }) {
    if (!_commandController.isClosed) {
      final int emitSeq = ++_emittedCommandSeq;
      final int recognizedAtMillis = _clock();
      if (result == null) return;
      _speechRecognitionService.markActionableCommandUtterance(
        result.commandUtteranceId,
      );
      final String segmentKey = '${result.captureEpoch}:${result.segmentId}';
      final int decoderUtteranceOpenAgeMs = recognizedAtMillis -
          (result.commandUtteranceStartedAtMillis ?? recognizedAtMillis);
      final int acousticSpeechToCommandMs = recognizedAtMillis -
          (_segmentStartedAt[segmentKey] ??
              result.commandUtteranceStartedAtMillis ??
              recognizedAtMillis);
      final WearVoiceCommandEvent event = WearVoiceCommandEvent(
        command: cmd,
        traceId: '$segmentKey:$emitSeq',
        recognizedAtMillis: recognizedAtMillis,
        asrMillis: acousticSpeechToCommandMs,
        captureEpoch: result.captureEpoch,
        commandUtteranceId: result.commandUtteranceId,
        sourceScreen: result.sourceScreen,
        routeRevision: result.routeRevision,
        grammarRevision: result.grammarRevision,
      );
      print(
        '[WearVoiceControlService] emitting#$emitSeq $source command: $cmd '
        'hasListener=${_commandController.hasListener} '
        'acousticSpeechToCommandMs=$acousticSpeechToCommandMs '
        'decoderUtteranceOpenAgeMs=$decoderUtteranceOpenAgeMs',
      );
      _commandController.add(cmd);
      if (!_commandEventController.isClosed) {
        _commandEventController.add(event);
      }
    }
  }

  void _onSegmentStarted(SpeechSegmentStarted started) {
    _replayFeedbackController.onSegmentStarted(
      started.captureEpoch,
      started.segmentId,
    );
    _arbiter.startSegment(started);
    _segmentStartedAt['${started.captureEpoch}:${started.segmentId}'] =
        _clock();
    _clearRecognitionDelay();
    final _RecognitionDelayContext context = _RecognitionDelayContext(
      captureEpoch: started.captureEpoch,
      segmentId: started.segmentId,
      sourceScreen: _speechRecognitionService.sourceScreen,
      routeRevision: _speechRecognitionService.routeRevision,
      grammarRevision: _speechRecognitionService.grammarRevision,
      freeTextEpoch: _speechRecognitionService.freeTextEpoch,
    );
    _recognitionDelayContext = context;
  }

  void _onReplayOwnership(VoiceReplayOwnership ownership) {
    final VoiceReplayContext? context = ownership.context;
    final String? utteranceKey = context == null
        ? null
        : _feedbackUtteranceKey(
            context.captureEpoch,
            context.commandUtteranceId,
          );
    final bool meaningfulEvidence = utteranceKey != null &&
        _feedbackEligibleUtterances.contains(utteranceKey);
    if (ownership.status == VoiceReplayOwnershipStatus.pending) {
      _clearRecognitionDelay();
    }
    _replayFeedbackController.accept(
      ownership,
      meaningfulEvidence: meaningfulEvidence,
    );
    if (ownership.isTerminal && utteranceKey != null) {
      _feedbackEligibleUtterances.remove(utteranceKey);
    }
  }

  String _feedbackUtteranceKey(int captureEpoch, int commandUtteranceId) =>
      '$captureEpoch:$commandUtteranceId';

  void _emitPhrase(SegmentedRecognitionResult result) {
    final String trimmed = result.text.trim();
    if (trimmed.isEmpty || _phraseController.isClosed) {
      return;
    }
    print(
      '[WearVoiceControlService] emitting phrase: "$trimmed" '
      'hasListener=${_phraseController.hasListener}',
    );
    _phraseController.add(trimmed);
    if (!_phraseEventController.isClosed) {
      _phraseEventController.add(WearVoicePhraseEvent(
        phrase: trimmed,
        captureEpoch: result.captureEpoch,
        commandUtteranceId: result.commandUtteranceId,
        sourceScreen: result.sourceScreen,
        routeRevision: result.routeRevision,
        grammarRevision: result.grammarRevision,
        freeTextEpoch: result.freeTextEpoch,
        listRevision: result.listRevision,
      ));
    }
  }

  void _emitPreview(SegmentedRecognitionResult result) {
    if (_previewEventController.isClosed) return;
    final String trimmed = result.text.trim();
    if (trimmed.isEmpty) return;
    final int recognizedAtMillis =
        result.recognizedAtMillis > 0 ? result.recognizedAtMillis : _clock();
    final WearVoicePreviewEvent event = WearVoicePreviewEvent(
      text: trimmed,
      captureEpoch: result.captureEpoch,
      commandUtteranceId: result.commandUtteranceId,
      routeRevision: result.routeRevision,
      grammarRevision: result.grammarRevision,
      freeTextEpoch: result.freeTextEpoch,
      sourceScreen: result.sourceScreen,
      partialRevision: result.partialRevision,
      recognizedAtMillis: recognizedAtMillis,
      listRevision: result.listRevision,
      segmentId: result.segmentId,
      itemId: result.dynamicItemId!,
      isCommandLane: result.lane == RecognitionLane.command,
    );
    print(
      '[VOICE_PREVIEW_SHADOW] text="$trimmed" '
      'captureEpoch=${event.captureEpoch} '
      'utteranceId=${event.commandUtteranceId} '
      'routeRevision=${event.routeRevision} '
      'grammarRevision=${event.grammarRevision} '
      'freeTextEpoch=${event.freeTextEpoch} '
      'screen=${event.sourceScreen.name} '
      'partialRevision=${event.partialRevision} '
      'admissionMs=${_clock() - recognizedAtMillis}',
    );
    _previewEventController.add(event);
  }

  void _schedulePreview(SegmentedRecognitionResult candidate) {
    final String key = _previewKey(candidate);
    final String itemId = candidate.dynamicItemId!;
    final String observation = '${candidate.lane.name}:'
        '${candidate.partialRevision}';
    _PreviewStabilityState state = _previewStates.putIfAbsent(
      key,
      _PreviewStabilityState.new,
    );
    if (state.emittedItemId != null) return;
    if (state.itemId != itemId) {
      state = _PreviewStabilityState()
        ..itemId = itemId
        ..candidate = candidate;
      _previewStates[key] = state;
    } else {
      state.candidate = candidate;
    }
    state.observations.add(observation);
    while (_previewStates.length > 128) {
      final String oldest = _previewStates.keys.first;
      _stabilityTimers.remove('preview:$oldest')?.cancel();
      _previewStates.remove(oldest);
    }
    final String timerKey = 'preview:$key';
    _stabilityTimers.remove(timerKey)?.cancel();
    final _PreviewStabilityState expectedState = state;
    _stabilityTimers[timerKey] = _timerFactory(_stablePartialDelay, () {
      _stabilityTimers.remove(timerKey);
      if (!identical(_previewStates[key], expectedState) ||
          expectedState.emittedItemId != null ||
          expectedState.observations.length < 2) {
        return;
      }
      final SegmentedRecognitionResult preview = expectedState.candidate!;
      if (!_arbiter.canPreview(preview)) return;
      expectedState.emittedItemId = preview.dynamicItemId;
      _emitPreview(preview);
    });
  }

  void _cancelPendingPreview(SegmentedRecognitionResult result) {
    final String key = _previewKey(result);
    final _PreviewStabilityState? state = _previewStates[key];
    if (state?.emittedItemId != null || state?.candidate?.lane != result.lane) {
      return;
    }
    _stabilityTimers.remove('preview:$key')?.cancel();
    _previewStates.remove(key);
  }

  String _previewKey(SegmentedRecognitionResult result) =>
      '${result.captureEpoch}:${result.commandUtteranceId}:'
      '${result.routeRevision}:${result.grammarRevision}:'
      '${result.freeTextEpoch}:${result.sourceScreen.name}';

  void _clearRecognitionDelay({
    SegmentedRecognitionResult? result,
    SpeechSegmentEnded? ended,
  }) {
    final _RecognitionDelayContext? context = _recognitionDelayContext;
    if (context != null &&
        ((result != null &&
                (result.captureEpoch != context.captureEpoch ||
                    result.segmentId != context.segmentId)) ||
            (ended != null &&
                (ended.captureEpoch != context.captureEpoch ||
                    ended.segmentId != context.segmentId)))) {
      return;
    }
    _recognitionPreviewTimeout?.cancel();
    _recognitionPreviewTimeout = null;
    if (_recognitionDelayVisible) {
      _recognitionDelayVisible = false;
      if (context != null) _emitDelay(visible: false, context: context);
    }
    _recognitionDelayContext = null;
  }

  void markPreviewUseful(WearVoicePreviewEvent event) {
    final _RecognitionDelayContext? context = _recognitionDelayContext;
    if (context == null ||
        context.captureEpoch != event.captureEpoch ||
        context.segmentId != event.segmentId ||
        context.sourceScreen != event.sourceScreen ||
        context.routeRevision != event.routeRevision ||
        context.grammarRevision != event.grammarRevision ||
        context.freeTextEpoch != event.freeTextEpoch) {
      return;
    }
    if (_recognitionDelayVisible) return;
    _recognitionDelayVisible = true;
    _emitDelay(visible: true, context: context, previewText: event.text);
    _recognitionPreviewTimeout = _timerFactory(
      _recognitionPreviewDuration,
      () => _clearRecognitionDelay(),
    );
  }

  void _emitDelay({
    required bool visible,
    required _RecognitionDelayContext context,
    String? previewText,
  }) {
    _publishDelayEvent(
      WearVoiceDelayEvent(
        visible: visible,
        captureEpoch: context.captureEpoch,
        segmentId: context.segmentId,
        sourceScreen: context.sourceScreen,
        routeRevision: context.routeRevision,
        grammarRevision: context.grammarRevision,
        freeTextEpoch: context.freeTextEpoch,
        previewText: previewText,
      ),
    );
  }

  void _publishDelayEvent(WearVoiceDelayEvent event) {
    if (_delayEventController.isClosed) return;
    print(
      '[VOICE_FEEDBACK] kind=${event.kind.name} visible=${event.visible} '
      'status="${event.statusText ?? event.previewText ?? ''}" '
      'screen=${event.sourceScreen.name} '
      'captureEpoch=${event.captureEpoch} segmentId=${event.segmentId} '
      'utteranceId=${event.commandUtteranceId}',
    );
    _delayEventController.add(event);
  }

  void _cancelUtteranceStabilityTimers(SegmentedRecognitionResult result) {
    final String utteranceKey = ':${result.captureEpoch}:'
        '${result.commandUtteranceId}:${result.routeRevision}:'
        '${result.grammarRevision}:${result.freeTextEpoch}:'
        '${result.sourceScreen.name}';
    final List<String> keys = _stabilityTimers.keys
        .where((String key) => key.endsWith(utteranceKey))
        .toList(growable: false);
    for (final String key in keys) {
      _stabilityTimers.remove(key)?.cancel();
      _latestPartialRevisions.remove(key);
    }
    final String previewKey = _previewKey(result);
    _stabilityTimers.remove('preview:$previewKey')?.cancel();
    _previewStates.remove(previewKey);
  }

  void _onRecognitionError(Object error, StackTrace stackTrace) {
    print('[WearVoiceControlService] ASR stream error: $error');
    if (!_commandController.isClosed) {
      _commandController.addError(error, stackTrace);
    }
  }

  Future<void> dispose() async {
    for (final Timer timer in _stabilityTimers.values) {
      timer.cancel();
    }
    _stabilityTimers.clear();
    _latestPartialRevisions.clear();
    _previewStates.clear();
    _feedbackEligibleUtterances.clear();
    _recognitionPreviewTimeout?.cancel();
    await _recognitionSubscription?.cancel();
    await _segmentStartedSubscription?.cancel();
    await _segmentEndedSubscription?.cancel();
    await _replayOwnershipSubscription?.cancel();
    _replayFeedbackController.dispose();
    _arbiter.dispose();
    await _commandController.close();
    await _commandEventController.close();
    await _phraseController.close();
    await _phraseEventController.close();
    await _previewEventController.close();
    await _delayEventController.close();
  }
}

class _PreviewStabilityState {
  String? itemId;
  SegmentedRecognitionResult? candidate;
  final Set<String> observations = <String>{};
  String? emittedItemId;
}

class _RecognitionDelayContext {
  const _RecognitionDelayContext({
    required this.captureEpoch,
    required this.segmentId,
    required this.sourceScreen,
    required this.routeRevision,
    required this.grammarRevision,
    required this.freeTextEpoch,
  });

  final int captureEpoch;
  final int segmentId;
  final WearScreenId sourceScreen;
  final int routeRevision;
  final int grammarRevision;
  final int freeTextEpoch;
}
