import 'dart:async';

import 'package:smart_glasses/modules/wear/domain/service/voice_command/recognition_arbiter.dart';
import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/voice_action_catalog.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/voice_command_parser_service.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/wear_voice_command.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/wear_voice_command_event.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_typing/segmented_recognition_result.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_typing/speech_recognition_service.dart';

typedef WearVoiceClock = int Function();

class WearVoiceControlService {
  WearVoiceControlService({
    required SpeechRecognitionService speechRecognitionService,
    VoiceCommandParserService? commandParserService,
    VoiceActionCatalog? actionCatalog,
    WearScreenId Function()? screenProvider,
    WearVoiceClock? clock,
  })  : _speechRecognitionService = speechRecognitionService,
        _arbiter = RecognitionArbiter(
          actionCatalog: actionCatalog,
          screenProvider: screenProvider,
          routeRevisionProvider: () => speechRecognitionService.routeRevision,
          grammarRevisionProvider: () =>
              speechRecognitionService.grammarRevision,
        ),
        _clock = clock ?? (() => DateTime.now().millisecondsSinceEpoch) {
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
  final StreamController<WearVoiceCommand> _commandController =
      StreamController<WearVoiceCommand>.broadcast();
  final StreamController<WearVoiceCommandEvent> _commandEventController =
      StreamController<WearVoiceCommandEvent>.broadcast();
  final StreamController<String> _phraseController =
      StreamController<String>.broadcast();
  final StreamController<String?> _freeTextPreviewController =
      StreamController<String?>.broadcast();
  StreamSubscription<SegmentedRecognitionResult>? _recognitionSubscription;
  StreamSubscription<SpeechSegmentStarted>? _segmentStartedSubscription;
  StreamSubscription<SpeechSegmentEnded>? _segmentEndedSubscription;
  int _emittedCommandSeq = 0;
  final Map<String, int> _segmentStartedAt = <String, int>{};
  final Map<String, Timer> _stabilityTimers = <String, Timer>{};
  static const Duration _stablePartialDelay = Duration(milliseconds: 150);

  static const int _minPartialPhraseLength = 6;
  Stream<WearVoiceCommand> get commandStream => _commandController.stream;
  Stream<WearVoiceCommandEvent> get commandEventStream =>
      _commandEventController.stream;
  Stream<String> get phraseStream => _phraseController.stream;
  Stream<String?> get freeTextPreviewStream =>
      _freeTextPreviewController.stream;

  void _onRecognitionResult(SegmentedRecognitionResult result) {
    final RecognitionArbitration? outcome = _arbiter.accept(result);
    if (outcome == null) return;
    if (outcome.stableCandidate
        case final SegmentedRecognitionResult candidate) {
      final String key =
          '${candidate.captureEpoch}:${candidate.commandUtteranceId}';
      _stabilityTimers.remove(key)?.cancel();
      _stabilityTimers[key] = Timer(_stablePartialDelay, () {
        _stabilityTimers.remove(key);
        final RecognitionArbitration? stable = _arbiter.claimStable(candidate);
        if (stable?.command case final WearVoiceCommand command) {
          _emitFreeTextPreview(null);
          _emitCommand(
            command,
            captureEpoch: candidate.captureEpoch,
            segmentId: candidate.segmentId,
            source: 'stable_partial',
          );
        }
      });
      return;
    }
    if (outcome.command case final WearVoiceCommand command) {
      if (outcome.clearPreview) _emitFreeTextPreview(null);
      _emitCommand(
        command,
        captureEpoch: result.captureEpoch,
        segmentId: result.segmentId,
        source: result.kind.name,
      );
      return;
    }
    if (outcome.preview case final String preview) {
      _emitFreeTextPreview(preview);
      return;
    }
    if (outcome.phrase case final String phrase) {
      _emitPhrase(phrase);
    }
  }

  void _onSegmentEnded(SpeechSegmentEnded ended) {
    try {
      final RecognitionArbitration? outcome = _arbiter.endSegment(ended);
      if (outcome?.command case final WearVoiceCommand command) {
        if (outcome!.clearPreview) _emitFreeTextPreview(null);
        _emitCommand(
          command,
          captureEpoch: ended.captureEpoch,
          segmentId: ended.segmentId,
          source: 'segment_final',
        );
        return;
      }
      if (outcome?.phrase case final String phrase) {
        _emitPhrase(phrase);
      }
    } finally {
      _segmentStartedAt.remove('${ended.captureEpoch}:${ended.segmentId}');
    }
  }

  void _emitCommand(
    WearVoiceCommand cmd, {
    required int captureEpoch,
    required int segmentId,
    String source = 'final',
  }) {
    if (!_commandController.isClosed) {
      final int emitSeq = ++_emittedCommandSeq;
      final int recognizedAtMillis = _clock();
      final String segmentKey = '$captureEpoch:$segmentId';
      final int asrMillis = recognizedAtMillis -
          (_segmentStartedAt[segmentKey] ?? recognizedAtMillis);
      final WearVoiceCommandEvent event = WearVoiceCommandEvent(
        command: cmd,
        traceId: '$segmentKey:$emitSeq',
        recognizedAtMillis: recognizedAtMillis,
        asrMillis: asrMillis,
      );
      print(
        '[WearVoiceControlService] emitting#$emitSeq $source command: $cmd '
        'hasListener=${_commandController.hasListener}',
      );
      _commandController.add(cmd);
      if (!_commandEventController.isClosed) {
        _commandEventController.add(event);
      }
    }
  }

  void _onSegmentStarted(SpeechSegmentStarted started) {
    _arbiter.startSegment(started);
    _segmentStartedAt['${started.captureEpoch}:${started.segmentId}'] =
        _clock();
  }

  void _emitPhrase(String phrase) {
    final String trimmed = phrase.trim();
    if (trimmed.isEmpty || _phraseController.isClosed) {
      return;
    }
    print(
      '[WearVoiceControlService] emitting phrase: "$trimmed" '
      'hasListener=${_phraseController.hasListener}',
    );
    _phraseController.add(trimmed);
  }

  void _emitFreeTextPreview(String? phrase) {
    if (_freeTextPreviewController.isClosed) return;
    if (phrase == null) {
      _freeTextPreviewController.add(null);
      return;
    }
    final String trimmed = phrase.trim();
    if (trimmed.length < _minPartialPhraseLength) {
      return;
    }
    print(
      '[WearVoiceControlService] emitting free-text preview: "$trimmed" '
      'hasListener=${_freeTextPreviewController.hasListener}',
    );
    _freeTextPreviewController.add(trimmed);
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
    await _recognitionSubscription?.cancel();
    await _segmentStartedSubscription?.cancel();
    await _segmentEndedSubscription?.cancel();
    _arbiter.dispose();
    await _commandController.close();
    await _commandEventController.close();
    await _phraseController.close();
    await _freeTextPreviewController.close();
  }
}
