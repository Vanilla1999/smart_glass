import 'package:flutter_test/flutter_test.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/voice_command_parser_service.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/wear_voice_command.dart';

void main() {
  group('VoiceCommandParserService', () {
    late VoiceCommandParserService parser;

    setUp(() {
      parser = VoiceCommandParserService();
    });

    test('parses exact Russian command aliases', () {
      const Map<String, WearVoiceCommand> cases = <String, WearVoiceCommand>{
        'вверх': WearVoiceCommand.up,
        'на верх': WearVoiceCommand.up,
        'выше': WearVoiceCommand.up,
        'вниз': WearVoiceCommand.down,
        'в низ': WearVoiceCommand.down,
        'ниже': WearVoiceCommand.down,
        'выбери': WearVoiceCommand.select,
        'окей': WearVoiceCommand.select,
        'да': WearVoiceCommand.yes,
        'ага': WearVoiceCommand.yes,
        'нет': WearVoiceCommand.no,
        'назад': WearVoiceCommand.back,
        'домой': WearVoiceCommand.home,
        'дом': WearVoiceCommand.home,
        'завершить': WearVoiceCommand.finish,
        'закончить': WearVoiceCommand.finish,
        'готово': WearVoiceCommand.finish,
        'фонарик': WearVoiceCommand.flashlight,
      };

      for (final MapEntry<String, WearVoiceCommand> entry in cases.entries) {
        expect(parser.parse(entry.key), entry.value, reason: entry.key);
      }
    });

    test('normalizes case and punctuation', () {
      expect(parser.parse('  ВЫБЕРИ! '), WearVoiceCommand.select);
      expect(parser.parse('Назад.'), WearVoiceCommand.back);
      expect(parser.parse('Окей,'), WearVoiceCommand.select);
      expect(parser.parse('Да.'), WearVoiceCommand.yes);
      expect(parser.parse('Нет,'), WearVoiceCommand.no);
      expect(parser.parse('Фонарик.'), WearVoiceCommand.flashlight);
    });

    test('parses command token inside short recognition phrase', () {
      expect(parser.parse('иди вверх'), WearVoiceCommand.up);
      expect(parser.parse('листай вниз пожалуйста'), WearVoiceCommand.down);
      expect(parser.parse('можно выбрать'), WearVoiceCommand.select);
      expect(parser.parse('да можно'), WearVoiceCommand.yes);
      expect(parser.parse('нет нельзя'), WearVoiceCommand.no);
      expect(parser.parse('перейти домой'), WearVoiceCommand.home);
      expect(parser.parse('включи фонарик пожалуйста'),
          WearVoiceCommand.flashlight);
      expect(parser.parse('можно завершить'), WearVoiceCommand.finish);
    });

    test('does not parse partial words as commands', () {
      expect(parser.parse('сверхновая'), isNull);
      expect(parser.parse('домовой'), isNull);
      expect(parser.parse('выбирать'), isNull);
    });

    test('returns null for empty or unknown text', () {
      expect(parser.parse(''), isNull);
      expect(parser.parse('   '), isNull);
      expect(parser.parse('привет мир'), isNull);
    });
  });
}
