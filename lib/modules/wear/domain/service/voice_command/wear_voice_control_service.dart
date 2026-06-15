import 'dart:async';

import 'package:smart_glasses/modules/wear/domain/service/voice_command/wear_voice_command.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_typing/speech_recognition_service.dart';

class WearVoiceControlService {
  WearVoiceControlService({
    required SpeechRecognitionService speechRecognitionService,
  }) : _speechRecognitionService = speechRecognitionService {
    _initStream();
  }

  final SpeechRecognitionService _speechRecognitionService;
  final StreamController<WearVoiceCommand> _commandController =
      StreamController<WearVoiceCommand>.broadcast();

  Stream<WearVoiceCommand> get commandStream => _commandController.stream;

  static const Map<String, WearVoiceCommand> _commandMap =
      <String, WearVoiceCommand>{
    'вверх': WearVoiceCommand.up,
    'верх': WearVoiceCommand.up,
    'вниз': WearVoiceCommand.down,
    'выбрать': WearVoiceCommand.select,
    'назад': WearVoiceCommand.back,
    'выход': WearVoiceCommand.home,
    'домой': WearVoiceCommand.home,
  };

  void _initStream() {
    _speechRecognitionService.resultsStream.listen((text) {
      final cmd = parseCommand(text);
      if (cmd != null) {
        _commandController.add(cmd);
      }
    });
  }

  WearVoiceCommand? parseCommand(String text) {
    final String normalized = text
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-zа-яё\s]'), '')
        .trim();
    if (normalized.isEmpty) return null;
    return _commandMap[normalized];
  }

  void dispose() {
    _commandController.close();
  }
}
