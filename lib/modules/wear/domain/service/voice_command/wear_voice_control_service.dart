import 'dart:async';

import 'package:smart_glasses/modules/wear/domain/service/voice_command/voice_command_parser_service.dart';
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
  StreamSubscription<String>? _recognitionSubscription;
  StreamSubscription<String>? _partialRecognitionSubscription;
  WearVoiceCommand? _lastPartialCommand;
  int _lastPartialCommandAt = 0;
  WearVoiceCommand? _lastEmittedPartialCommand;
  int _lastEmittedPartialCommandAt = 0;
  int _recognitionEventSeq = 0;

  static const int _duplicatePartialMs = 1200;
  static const int _matchingFinalSuppressMs = 1500;

  Stream<WearVoiceCommand> get commandStream => _commandController.stream;

  void _onRecognitionResult(String resultText) {
    final t0 = _now();
    final int seq = ++_recognitionEventSeq;
    print(
      '[WearVoiceControlService] ASR#$seq final at $t0: "$resultText" '
      'lastEmittedPartial=$_lastEmittedPartialCommand '
      'emittedPartialAge=${t0 - _lastEmittedPartialCommandAt}ms',
    );
    final WearVoiceCommand? cmd = _commandParserService.parse(resultText);
    if (cmd == null) {
      print('[WearVoiceControlService] no command matched for "$resultText"');
      return;
    }
    if (_isMatchingFinalForRecentPartial(cmd, t0)) {
      print(
        '[WearVoiceControlService] skip final matching emitted partial: '
        '$cmd seq=$seq age=${t0 - _lastEmittedPartialCommandAt}ms',
      );
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
      'partialAge=${t0 - _lastPartialCommandAt}ms '
      'lastEmittedPartial=$_lastEmittedPartialCommand',
    );
    final WearVoiceCommand? cmd = _commandParserService.parse(resultText);
    if (cmd == null) {
      print(
        '[WearVoiceControlService] no partial command matched for "$resultText"',
      );
      return;
    }
    if (_isDuplicatePartialCommand(cmd, t0)) {
      print('[WearVoiceControlService] skip duplicate partial command: $cmd');
      return;
    }
    _lastPartialCommand = cmd;
    _lastPartialCommandAt = t0;
    _lastEmittedPartialCommand = cmd;
    _lastEmittedPartialCommandAt = t0;
    _emitCommand(cmd, t0, source: 'partial');
  }

  bool _isDuplicatePartialCommand(WearVoiceCommand cmd, int now) {
    return _lastPartialCommand == cmd &&
        now - _lastPartialCommandAt < _duplicatePartialMs;
  }

  bool _isMatchingFinalForRecentPartial(WearVoiceCommand cmd, int now) {
    return _lastEmittedPartialCommand == cmd &&
        now - _lastEmittedPartialCommandAt <= _matchingFinalSuppressMs;
  }

  void _emitCommand(
    WearVoiceCommand cmd,
    int startedAt, {
    String source = 'final',
  }) {
    if (!_commandController.isClosed) {
      final t1 = _now();
      print(
        '[WearVoiceControlService] emitting $source command: $cmd at $t1 '
        '(parse_latency: ${t1 - startedAt}ms)',
      );
      _commandController.add(cmd);
    }
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
  }
}
