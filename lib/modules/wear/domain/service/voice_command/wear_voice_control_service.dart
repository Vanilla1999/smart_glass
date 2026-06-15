import 'dart:async';

import 'package:smart_glasses/modules/wear/domain/service/voice_command/voice_command_parser_service.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/wear_voice_command.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_typing/speech_recognition_service.dart';

class WearVoiceControlService {
  WearVoiceControlService({
    required SpeechRecognitionService speechRecognitionService,
    VoiceCommandParserService? commandParserService,
  })  : _speechRecognitionService = speechRecognitionService,
        _commandParserService =
            commandParserService ?? VoiceCommandParserService() {
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
  final StreamController<WearVoiceCommand> _commandController =
      StreamController<WearVoiceCommand>.broadcast();
  StreamSubscription<String>? _recognitionSubscription;
  StreamSubscription<String>? _partialRecognitionSubscription;
  WearVoiceCommand? _lastPartialCommand;
  int _lastPartialCommandAt = 0;
  WearVoiceCommand? _pendingFinalDuplicateCommand;
  WearVoiceCommand? _lastSuppressedFinalCommand;
  int _lastSuppressedFinalCommandAt = 0;
  WearVoiceCommand? _lastEmittedCommand;
  int _lastEmittedCommandAt = 0;
  int _recognitionEventSeq = 0;

  Stream<WearVoiceCommand> get commandStream => _commandController.stream;

  void _onRecognitionResult(String resultText) {
    final t0 = DateTime.now().millisecondsSinceEpoch;
    final int seq = ++_recognitionEventSeq;
    print(
      '[WearVoiceControlService] ASR#$seq final at $t0: "$resultText" '
      'pendingFinal=$_pendingFinalDuplicateCommand '
      'lastPartial=$_lastPartialCommand '
      'partialAge=${t0 - _lastPartialCommandAt}ms '
      'lastEmitted=$_lastEmittedCommand '
      'emittedAge=${t0 - _lastEmittedCommandAt}ms',
    );
    final WearVoiceCommand? cmd = _commandParserService.parse(resultText);
    if (cmd == null) {
      print('[WearVoiceControlService] no command matched for "$resultText"');
      return;
    }
    if (_pendingFinalDuplicateCommand == cmd) {
      _lastSuppressedFinalCommand = cmd;
      _lastSuppressedFinalCommandAt = t0;
      print(
        '[WearVoiceControlService] skip duplicate final command: $cmd '
        'seq=$seq partialAge=${t0 - _lastPartialCommandAt}ms',
      );
      _pendingFinalDuplicateCommand = null;
      return;
    }
    _pendingFinalDuplicateCommand = null;
    _emitCommand(cmd, t0);
  }

  void _onPartialRecognitionResult(String resultText) {
    final int t0 = DateTime.now().millisecondsSinceEpoch;
    final int seq = ++_recognitionEventSeq;
    print(
      '[WearVoiceControlService] ASR#$seq partial at $t0: "$resultText" '
      'pendingFinal=$_pendingFinalDuplicateCommand '
      'lastPartial=$_lastPartialCommand '
      'partialAge=${t0 - _lastPartialCommandAt}ms '
      'lastSuppressedFinal=$_lastSuppressedFinalCommand '
      'suppressedFinalAge=${t0 - _lastSuppressedFinalCommandAt}ms '
      'lastEmitted=$_lastEmittedCommand '
      'emittedAge=${t0 - _lastEmittedCommandAt}ms',
    );
    final WearVoiceCommand? cmd = _commandParserService.parse(resultText);
    if (cmd == null) {
      print(
        '[WearVoiceControlService] no partial command matched for "$resultText"',
      );
      return;
    }
    if (_isResidualPartialAfterSuppressedFinal(cmd, t0)) {
      print(
        '[WearVoiceControlService] skip residual partial after suppressed final: '
        '$cmd seq=$seq suppressedFinalAge='
        '${t0 - _lastSuppressedFinalCommandAt}ms',
      );
      _lastPartialCommand = cmd;
      _lastPartialCommandAt = t0;
      return;
    }
    if (_isDuplicatePartialCommand(cmd, t0)) {
      print('[WearVoiceControlService] skip duplicate partial command: $cmd');
      return;
    }
    _lastPartialCommand = cmd;
    _lastPartialCommandAt = t0;
    _pendingFinalDuplicateCommand = cmd;
    _emitCommand(cmd, t0, source: 'partial');
  }

  bool _isDuplicatePartialCommand(WearVoiceCommand cmd, int now) {
    return _lastPartialCommand == cmd && now - _lastPartialCommandAt < 1200;
  }

  bool _isResidualPartialAfterSuppressedFinal(WearVoiceCommand cmd, int now) {
    return _lastSuppressedFinalCommand == cmd &&
        now - _lastSuppressedFinalCommandAt < 2500;
  }

  bool _isDuplicateEmittedCommand(WearVoiceCommand cmd, int now) {
    if (_lastEmittedCommand != cmd) return false;

    final int cooldownMs = switch (cmd) {
      WearVoiceCommand.select => 2500,
      WearVoiceCommand.back => 2500,
      WearVoiceCommand.home => 2500,
      WearVoiceCommand.up => 900,
      WearVoiceCommand.down => 900,
    };

    return now - _lastEmittedCommandAt < cooldownMs;
  }

  void _emitCommand(
    WearVoiceCommand cmd,
    int startedAt, {
    String source = 'final',
  }) {
    if (!_commandController.isClosed) {
      final t1 = DateTime.now().millisecondsSinceEpoch;
      if (_isDuplicateEmittedCommand(cmd, t1)) {
        print(
          '[WearVoiceControlService] skip duplicate emitted command: $cmd',
        );
        return;
      }
      _lastEmittedCommand = cmd;
      _lastEmittedCommandAt = t1;
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
