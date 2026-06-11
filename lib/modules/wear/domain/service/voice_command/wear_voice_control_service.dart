import 'dart:async';

import 'package:smart_glasses/modules/wear/domain/service/voice_command/voice_command_parser_service.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/wear_voice_command.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_typing/speech_recognition_service.dart';

class WearVoiceControlService {
  WearVoiceControlService({
    required SpeechRecognitionService speechRecognitionService,
    VoiceCommandParserService? parser,
  })  : _speechRecognitionService = speechRecognitionService,
        _parser = parser ?? VoiceCommandParserService();

  final SpeechRecognitionService _speechRecognitionService;
  final VoiceCommandParserService _parser;
  final StreamController<WearVoiceCommand> _commandsController =
      StreamController<WearVoiceCommand>.broadcast();

  StreamSubscription<String>? _resultsSubscription;

  Stream<WearVoiceCommand> get commandStream {
    _ensureSubscription();
    return _commandsController.stream;
  }

  void dispose() {
    _resultsSubscription?.cancel();
    _resultsSubscription = null;
  }

  void _ensureSubscription() {
    _resultsSubscription ??= _speechRecognitionService.resultsStream.listen(
      _handleText,
    );
  }

  void _handleText(String text) {
    final WearVoiceCommand? command = _parser.parse(text);
    if (command == null || _commandsController.isClosed) return;
    _commandsController.add(command);
  }
}
