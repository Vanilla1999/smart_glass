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
        'бер': WearVoiceCommand.up,
        'сбер': WearVoiceCommand.up,
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
        'люмус максима': WearVoiceCommand.flashlight,
        'подтвердить': WearVoiceCommand.select,
        'принять': WearVoiceCommand.select,
        'печать ценника': WearVoiceCommand.openPrintPriceTag,
        'печать ценников': WearVoiceCommand.openPrintPriceTag,
        'напечатать': WearVoiceCommand.print,
        'продолжить': WearVoiceCommand.continueScan,
        'ручной ввод': WearVoiceCommand.manualInput,
        'сделать фото': WearVoiceCommand.takePhoto,
        'Фото': WearVoiceCommand.takePhoto,
        'к списку': WearVoiceCommand.backToList,
        'прямое сканирование': WearVoiceCommand.openDirectScan,
        'отмена': WearVoiceCommand.cancel,
        'закрыть': WearVoiceCommand.cancel,
        'закрой': WearVoiceCommand.cancel,
        'вернуться': WearVoiceCommand.back,
        'включить фонарик': WearVoiceCommand.flashlight,
        'следующая страница': WearVoiceCommand.nextPage,
        'дальше': WearVoiceCommand.nextPage,
        'далее': WearVoiceCommand.nextPage,
        'прошлая страница': WearVoiceCommand.previousPage,
        'прошлое страница': WearVoiceCommand.previousPage,
        'прошлую страницу': WearVoiceCommand.previousPage,
        'предыдущая страница': WearVoiceCommand.previousPage,
        'предыдущую страницу': WearVoiceCommand.previousPage,
        'страница назад': WearVoiceCommand.previousPage,
        'назад страница': WearVoiceCommand.previousPage,
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
      expect(parser.parse('можно печать ценника'),
          WearVoiceCommand.openPrintPriceTag);
      expect(parser.parse('давай напечатать'), WearVoiceCommand.print);
      expect(parser.parse('нужно продолжить'), WearVoiceCommand.continueScan);
      expect(parser.parse('можно вернуться'), WearVoiceCommand.back);
      expect(
          parser.parse('можно страница назад'), WearVoiceCommand.previousPage);
      expect(parser.parse('давай прошлое страница'),
          WearVoiceCommand.previousPage);
    });

    test('exposes grammar phrases for Vosk recognizer', () {
      expect(VoiceCommandParserService.grammarPhrases, contains('вверх'));
      expect(
          VoiceCommandParserService.grammarPhrases, contains('печать ценника'));
      expect(VoiceCommandParserService.grammarPhrases,
          contains('прямое сканирование'));
      expect(VoiceCommandParserService.grammarPhrases,
          contains('включить фонарик'));
      expect(
          VoiceCommandParserService.grammarPhrases, contains('люмус максима'));
      expect(VoiceCommandParserService.grammarPhrases,
          contains('следующая страница'));
      expect(VoiceCommandParserService.grammarPhrases,
          contains('прошлая страница'));
    });

    test('does not parse partial words as commands', () {
      expect(parser.parse('сверхновая'), isNull);
      expect(parser.parse('домовой'), isNull);
      expect(parser.parse('выбирать'), isNull);
      expect(parser.parse('стоп'), isNull);
      expect(parser.parse('конец'), isNull);
    });

    test('returns null for empty or unknown text', () {
      expect(parser.parse(''), isNull);
      expect(parser.parse('   '), isNull);
      expect(parser.parse('привет мир'), isNull);
    });
  });
}
