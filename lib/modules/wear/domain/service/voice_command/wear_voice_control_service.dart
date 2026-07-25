import 'dart:async';

import 'package:smart_glasses/modules/wear/domain/service/voice_command/recognition_arbiter.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/voice_command_parser_service.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/wear_voice_command.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_typing/segmented_recognition_result.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_typing/speech_recognition_service.dart';

typedef WearVoiceClock = int Function();

class WearVoiceControlService {
  WearVoiceControlService({
    required SpeechRecognitionService speechRecognitionService,
    VoiceCommandParserService? commandParserService,
    WearVoiceClock? clock,
  })  : _speechRecognitionService = speechRecognitionService,
        _arbiter = RecognitionArbiter(
          commandParserService: commandParserService,
        ) {
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
  }

  final SpeechRecognitionService _speechRecognitionService;
  final RecognitionArbiter _arbiter;
  final StreamController<WearVoiceCommand> _commandController =
      StreamController<WearVoiceCommand>.broadcast();
  final StreamController<String> _phraseController =
      StreamController<String>.broadcast();
  final StreamController<String> _partialPhraseController =
      StreamController<String>.broadcast();
  StreamSubscription<SegmentedRecognitionResult>? _recognitionSubscription;
  StreamSubscription<SpeechSegmentEnded>? _segmentEndedSubscription;
  int _emittedCommandSeq = 0;

  static const int _minPartialPhraseLength = 6;
  Stream<WearVoiceCommand> get commandStream => _commandController.stream;
  Stream<String> get phraseStream => _phraseController.stream;
  Stream<String> get partialPhraseStream => _partialPhraseController.stream;

  void _onRecognitionResult(SegmentedRecognitionResult result) {
    final RecognitionArbitration? outcome = _arbiter.accept(result);
    if (outcome == null) return;
    if (outcome.command case final WearVoiceCommand command) {
      _emitCommand(command, source: result.kind.name);
      return;
    }
    if (outcome.phrase case final String phrase) {
      if (outcome.isPartial) {
        _emitPartialPhrase(phrase);
      } else {
        _emitPhrase(phrase);
      }
    }
  }

  void _onSegmentEnded(SpeechSegmentEnded ended) {
    final RecognitionArbitration? outcome = _arbiter.endSegment(ended);
    if (outcome?.phrase case final String phrase) {
      _emitPhrase(phrase);
    }
  }

  void _emitCommand(
    WearVoiceCommand cmd, {
    String source = 'final',
  }) {
    if (!_commandController.isClosed) {
      final int emitSeq = ++_emittedCommandSeq;
      print(
        '[WearVoiceControlService] emitting#$emitSeq $source command: $cmd '
        'hasListener=${_commandController.hasListener}',
      );
      _commandController.add(cmd);
    }
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

  void _emitPartialPhrase(String phrase) {
    final String trimmed = phrase.trim();
    if (trimmed.length < _minPartialPhraseLength ||
        _partialPhraseController.isClosed) {
      return;
    }
    print(
      '[WearVoiceControlService] emitting partial phrase: "$trimmed" '
      'hasListener=${_partialPhraseController.hasListener}',
    );
    _partialPhraseController.add(trimmed);
  }

  void _onRecognitionError(Object error, StackTrace stackTrace) {
    print('[WearVoiceControlService] ASR stream error: $error');
    if (!_commandController.isClosed) {
      _commandController.addError(error, stackTrace);
    }
  }

  Future<void> dispose() async {
    await _recognitionSubscription?.cancel();
    await _segmentEndedSubscription?.cancel();
    _arbiter.dispose();
    await _commandController.close();
    await _phraseController.close();
    await _partialPhraseController.close();
  }
}
