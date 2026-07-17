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
    _commandRecognitionSubscription =
        _speechRecognitionService.commandResultsStream.listen(
      _onCommandRecognitionResult,
      onError: _onRecognitionError,
      onDone: () => print(
        '[WearVoiceControlService] command results stream done',
      ),
    );
    _commandPartialRecognitionSubscription =
        _speechRecognitionService.commandPartialResultsStream.listen(
      _onCommandPartialRecognitionResult,
      onError: _onRecognitionError,
      onDone: () => print(
        '[WearVoiceControlService] command partial stream done',
      ),
    );
    _freeTextRecognitionSubscription =
        _speechRecognitionService.freeTextResultsStream.listen(
      _onFreeTextRecognitionResult,
      onError: _onRecognitionError,
      onDone: () => print(
        '[WearVoiceControlService] freeText results stream done',
      ),
    );
    _freeTextPartialRecognitionSubscription =
        _speechRecognitionService.freeTextPartialResultsStream.listen(
      _onFreeTextPartialRecognitionResult,
      onError: _onRecognitionError,
      onDone: () => print(
        '[WearVoiceControlService] freeText partial stream done',
      ),
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
  StreamSubscription<String>? _commandRecognitionSubscription;
  StreamSubscription<String>? _commandPartialRecognitionSubscription;
  StreamSubscription<String>? _freeTextRecognitionSubscription;
  StreamSubscription<String>? _freeTextPartialRecognitionSubscription;
  WearVoiceCommand? _lastPartialCommand;
  int _lastPartialCommandAt = 0;
  int _firstPartialCommandAt = 0;
  WearVoiceCommand? _lastEmittedPartialCommand;
  int _lastEmittedPartialCommandAt = 0;
  int _recognitionEventSeq = 0;
  int _emittedCommandSeq = 0;
  String? _lastPartialPhrase;
  int _lastPartialPhraseAt = 0;

  static const int _partialPhraseThrottleMs = 300;
  static const int _minPartialPhraseLength = 6;
  static const int _matchingFinalSuppressMs = 2000;
  Stream<WearVoiceCommand> get commandStream => _commandController.stream;
  Stream<String> get phraseStream => _phraseController.stream;
  Stream<String> get partialPhraseStream => _partialPhraseController.stream;

  void _onCommandRecognitionResult(String resultText) {
    final t0 = _now();
    final int seq = ++_recognitionEventSeq;
    print(
      '[WearVoiceControlService] ASR#$seq final at $t0: "$resultText" '
      'priorPartial=$_lastPartialCommand '
      'partialToFinalMs=${_firstPartialCommandAt == 0 ? null : t0 - _firstPartialCommandAt} '
      'lastPartialAgeMs=${_lastPartialCommandAt == 0 ? null : t0 - _lastPartialCommandAt}',
    );
    final WearVoiceCommand? cmd = _commandParserService.parse(resultText);
    final WearVoiceCommand? emittedPartial = _lastEmittedPartialCommand;
    final int emittedPartialAgeMs = _lastEmittedPartialCommandAt == 0
        ? 0
        : t0 - _lastEmittedPartialCommandAt;
    _lastPartialCommand = null;
    _lastPartialCommandAt = 0;
    _firstPartialCommandAt = 0;
    _lastEmittedPartialCommand = null;
    _lastEmittedPartialCommandAt = 0;
    if (cmd == null) {
      print('[WearVoiceControlService] no command matched for "$resultText"');
      return;
    }
    if (emittedPartial != null &&
        emittedPartialAgeMs <= _matchingFinalSuppressMs) {
      print(
        '[WearVoiceControlService] suppress final after emitted grammar '
        'partial: partial=$emittedPartial final=$cmd '
        'ageMs=$emittedPartialAgeMs',
      );
      return;
    }
    _emitCommand(cmd, t0);
  }

  void _onCommandPartialRecognitionResult(String resultText) {
    final int t0 = _now();
    final int seq = ++_recognitionEventSeq;
    print(
      '[WearVoiceControlService] ASR#$seq partial at $t0: "$resultText" '
      'lastPartial=$_lastPartialCommand '
      'partialAgeMs=${_lastPartialCommandAt == 0 ? null : t0 - _lastPartialCommandAt}',
    );
    final WearVoiceCommand? cmd = _commandParserService.parse(resultText);
    if (cmd == null) {
      print(
        '[WearVoiceControlService] no partial command matched for "$resultText"',
      );
      return;
    }
    if (_firstPartialCommandAt == 0) {
      _firstPartialCommandAt = t0;
    }
    _lastPartialCommand = cmd;
    _lastPartialCommandAt = t0;
    if (_lastEmittedPartialCommand == null) {
      _lastEmittedPartialCommand = cmd;
      _lastEmittedPartialCommandAt = t0;
      _emitCommand(cmd, t0, source: 'grammar-partial');
      return;
    }
    print('[WearVoiceControlService] defer partial command until final: $cmd');
  }

  void _onFreeTextRecognitionResult(String resultText) {
    final int startedAt = _now();
    final int seq = ++_recognitionEventSeq;
    print(
      '[WearVoiceControlService] ASR#$seq freeText final at $startedAt: '
      '"$resultText"',
    );
    if (_commandParserService.parseExact(resultText) != null) {
      print(
        '[WearVoiceControlService] discard command from freeText final: '
        '"$resultText"',
      );
      return;
    }
    _emitPhrase(resultText, startedAt);
  }

  void _onFreeTextPartialRecognitionResult(String resultText) {
    final int startedAt = _now();
    final int seq = ++_recognitionEventSeq;
    print(
      '[WearVoiceControlService] ASR#$seq freeText partial at $startedAt: '
      '"$resultText"',
    );
    if (_commandParserService.parseExact(resultText) != null) {
      print(
        '[WearVoiceControlService] discard command from freeText partial: '
        '"$resultText"',
      );
      return;
    }
    _emitPartialPhrase(resultText, startedAt);
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
    await _commandRecognitionSubscription?.cancel();
    await _commandPartialRecognitionSubscription?.cancel();
    await _freeTextRecognitionSubscription?.cancel();
    await _freeTextPartialRecognitionSubscription?.cancel();
    await _commandController.close();
    await _phraseController.close();
    await _partialPhraseController.close();
  }
}
