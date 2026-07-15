import 'dart:async';

import 'package:smart_glasses/modules/wear/domain/service/voice_command/voice_command_parser_service.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/voice_list_matcher.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/wear_voice_command.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_typing/speech_recognition_service.dart';

typedef WearVoiceClock = int Function();

class WearVoiceControlService {
  WearVoiceControlService({
    required SpeechRecognitionService speechRecognitionService,
    VoiceCommandParserService? commandParserService,
    WearVoiceClock? clock,
  })  : _speechRecognitionService = speechRecognitionService,
        _commandParserService =
            commandParserService ?? VoiceCommandParserService(),
        _now = clock ?? (() => DateTime.now().millisecondsSinceEpoch) {
    print('[WearVoiceControlService] subscribing to ASR results');
    _recognitionSubscription = _speechRecognitionService.resultsStream.listen(
      _onRecognitionResult,
      onError: _onRecognitionError,
      onDone: () => print('[WearVoiceControlService] ASR results stream done'),
    );
    _partialRecognitionSubscription =
        _speechRecognitionService.partialResultsStream.listen(
      _onPartialRecognitionResult,
      onError: _onRecognitionError,
      onDone: () => print('[WearVoiceControlService] ASR partial stream done'),
    );
  }

  final SpeechRecognitionService _speechRecognitionService;
  final VoiceCommandParserService _commandParserService;
  final WearVoiceClock _now;
  final StreamController<WearVoiceCommand> _commandController =
      StreamController<WearVoiceCommand>.broadcast();
  final StreamController<String> _phraseController =
      StreamController<String>.broadcast();
  final StreamController<String> _partialPhraseController =
      StreamController<String>.broadcast();
  StreamSubscription<String>? _recognitionSubscription;
  StreamSubscription<String>? _partialRecognitionSubscription;
  WearVoiceCommand? _lastPartialCommand;
  int _lastPartialCommandAt = 0;
  int _recognitionEventSeq = 0;
  int _emittedCommandSeq = 0;
  String? _lastPartialPhrase;
  int _lastPartialPhraseAt = 0;

  static const int _partialPhraseThrottleMs = 300;
  static const int _minPartialPhraseLength = 6;
  Stream<WearVoiceCommand> get commandStream => _commandController.stream;
  Stream<String> get phraseStream => _phraseController.stream;
  Stream<String> get partialPhraseStream => _partialPhraseController.stream;

  void _onRecognitionResult(String resultText) {
    final t0 = _now();
    final int seq = ++_recognitionEventSeq;
    print(
      '[WearVoiceControlService] ASR#$seq final at $t0: "$resultText"',
    );
    final WearVoiceCommand? cmd = _parseCommand(resultText);
    if (cmd == null) {
      print('[WearVoiceControlService] no command matched for "$resultText"');
      _emitPhrase(resultText, t0);
      return;
    }
    _emitCommand(cmd, t0);
  }

  void _onPartialRecognitionResult(String resultText) {
    final int t0 = _now();
    final int seq = ++_recognitionEventSeq;
    print(
      '[WearVoiceControlService] ASR#$seq partial at $t0: "$resultText" '
      'lastPartial=$_lastPartialCommand '
      'partialAge=${t0 - _lastPartialCommandAt}ms',
    );
    final WearVoiceCommand? cmd = _parseCommand(resultText);
    if (cmd == null) {
      print(
        '[WearVoiceControlService] no partial command matched for "$resultText"',
      );
      _emitPartialPhrase(resultText, t0);
      return;
    }
    _lastPartialCommand = cmd;
    _lastPartialCommandAt = t0;
    print('[WearVoiceControlService] defer partial command until final: $cmd');
  }

  WearVoiceCommand? _parseCommand(String text) {
    if (_speechRecognitionService.usesFreeTextRecognition) {
      return _commandParserService.parseExact(text);
    }
    return _commandParserService.parse(text);
  }

  void _emitCommand(
    WearVoiceCommand cmd,
    int startedAt, {
    String source = 'final',
  }) {
    if (!_commandController.isClosed) {
      final t1 = _now();
      final int emitSeq = ++_emittedCommandSeq;
      print(
        '[WearVoiceControlService] emitting#$emitSeq $source command: $cmd '
        'at=$t1 parseLatencyMs=${t1 - startedAt} '
        'hasListener=${_commandController.hasListener}',
      );
      _commandController.add(cmd);
    }
  }

  void _emitPhrase(String phrase, int startedAt) {
    final String trimmed = phrase.trim();
    if (trimmed.isEmpty || _phraseController.isClosed) {
      return;
    }
    final t1 = _now();
    print(
      '[WearVoiceControlService] emitting phrase: "$trimmed" '
      'at=$t1 parseLatencyMs=${t1 - startedAt} '
      'hasListener=${_phraseController.hasListener}',
    );
    _phraseController.add(trimmed);
  }

  void _emitPartialPhrase(String phrase, int startedAt) {
    final String trimmed = phrase.trim();
    final String normalized = VoiceListMatcher.normalize(trimmed);
    if (normalized.length < _minPartialPhraseLength ||
        _partialPhraseController.isClosed) {
      return;
    }
    if (_lastPartialPhrase == normalized &&
        startedAt - _lastPartialPhraseAt < _partialPhraseThrottleMs) {
      return;
    }
    _lastPartialPhrase = normalized;
    _lastPartialPhraseAt = startedAt;
    final t1 = _now();
    print(
      '[WearVoiceControlService] emitting partial phrase: "$trimmed" '
      'at=$t1 parseLatencyMs=${t1 - startedAt} '
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
    await _partialRecognitionSubscription?.cancel();
    await _commandController.close();
    await _phraseController.close();
    await _partialPhraseController.close();
  }
}
