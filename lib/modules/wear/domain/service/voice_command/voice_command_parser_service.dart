import 'package:smart_glasses/modules/wear/domain/service/voice_command/wear_voice_command.dart';

class VoiceCommandParserService {
  static const Map<String, WearVoiceCommand> _exactCommandMap =
      <String, WearVoiceCommand>{
    'вверх': WearVoiceCommand.up,
    'верх': WearVoiceCommand.up,
    'наверх': WearVoiceCommand.up,
    'на верх': WearVoiceCommand.up,
    'выше': WearVoiceCommand.up,
    'вниз': WearVoiceCommand.down,
    'низ': WearVoiceCommand.down,
    'в низ': WearVoiceCommand.down,
    'ниже': WearVoiceCommand.down,
    'выбрать': WearVoiceCommand.select,
    'выбери': WearVoiceCommand.select,
    'выбор': WearVoiceCommand.select,
    'ок': WearVoiceCommand.select,
    'окей': WearVoiceCommand.select,
    'да': WearVoiceCommand.select,
    'назад': WearVoiceCommand.back,
    'выход': WearVoiceCommand.home,
    'домой': WearVoiceCommand.home,
    'дом': WearVoiceCommand.home,
  };

  static const Map<WearVoiceCommand, List<String>> _commandTokens =
      <WearVoiceCommand, List<String>>{
    WearVoiceCommand.up: <String>['вверх', 'наверх', 'выше'],
    WearVoiceCommand.down: <String>['вниз', 'ниже'],
    WearVoiceCommand.select: <String>['выбрать', 'выбери', 'ок', 'окей'],
    WearVoiceCommand.back: <String>['назад'],
    WearVoiceCommand.home: <String>['домой', 'выход'],
  };

  WearVoiceCommand? parse(String text) {
    final String normalized = text
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-zа-яё\s]'), '')
        .trim();
    print('[VoiceCommandParser] raw="$text" normalized="$normalized"');
    if (normalized.isEmpty) return null;
    final WearVoiceCommand? exact = _exactCommandMap[normalized];
    if (exact != null) {
      print('[VoiceCommandParser] exact match parsed=$exact');
      return exact;
    }

    WearVoiceCommand? cmd;
    String? matchedToken;
    for (final MapEntry<WearVoiceCommand, List<String>> entry
        in _commandTokens.entries) {
      for (final String token in entry.value) {
        if (!_containsToken(normalized, token)) {
          continue;
        }
        cmd = entry.key;
        matchedToken = token;
        break;
      }
      if (cmd != null) break;
    }
    if (cmd == null) {
      print('[VoiceCommandParser] no command token matched');
    } else {
      print('[VoiceCommandParser] token="$matchedToken" parsed=$cmd');
    }
    return cmd;
  }

  bool _containsToken(String text, String token) {
    return RegExp('(^|\\s)${RegExp.escape(token)}(\\s|\$)').hasMatch(text);
  }
}
