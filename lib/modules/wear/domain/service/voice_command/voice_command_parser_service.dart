import 'package:smart_glasses/modules/wear/domain/service/voice_command/wear_voice_command.dart';

class VoiceCommandParserService {
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

  WearVoiceCommand? parse(String text) {
    final String normalized = text
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-zа-яё\s]'), '')
        .trim();
    print('[VoiceCommandParser] raw="$text" normalized="$normalized"');
    if (normalized.isEmpty) return null;
    final cmd = _commandMap[normalized];
    print('[VoiceCommandParser] parsed=$cmd');
    return cmd;
  }
}
