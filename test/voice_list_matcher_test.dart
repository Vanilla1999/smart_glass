import 'package:flutter_test/flutter_test.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/voice_list_matcher.dart';

void main() {
  group('VoiceListMatcher', () {
    test('returns unique match by enough product name words', () {
      final VoiceListMatch<String> match = VoiceListMatcher.match(
        'чудо творожок',
        <String>['Чудо творожок', 'Чудо сок'],
        (String item) => item,
      );

      expect(match.type, VoiceListMatchType.unique);
      expect(match.item, 'Чудо творожок');
    });

    test('returns ambiguous match for shared prefix', () {
      final VoiceListMatch<String> match = VoiceListMatcher.match(
        'чудо',
        <String>['Чудо творожок', 'Чудо сок'],
        (String item) => item,
      );

      expect(match.type, VoiceListMatchType.ambiguous);
      expect(match.matches, <String>['Чудо творожок', 'Чудо сок']);
    });

    test('returns none when item is not found', () {
      final VoiceListMatch<String> match = VoiceListMatcher.match(
        'кефир',
        <String>['Чудо творожок', 'Чудо сок'],
        (String item) => item,
      );

      expect(match.type, VoiceListMatchType.none);
      expect(match.item, isNull);
    });

    test('normalizes case punctuation and yo letter', () {
      final VoiceListMatch<String> match = VoiceListMatcher.match(
        'Творожок! ежик',
        <String>['Чудо творожок Ёжик'],
        (String item) => item,
      );

      expect(match.type, VoiceListMatchType.unique);
    });

    test('matches long words with different endings by prefix', () {
      final VoiceListMatch<String> match = VoiceListMatcher.match(
        'безалкогольное',
        <String>['Безалкогольные'],
        (String item) => item,
      );

      expect(match.type, VoiceListMatchType.unique);
      expect(match.item, 'Безалкогольные');
    });

    test('keeps ending match ambiguous when multiple items match', () {
      final VoiceListMatch<String> match = VoiceListMatcher.match(
        'безалкогольное',
        <String>['Безалкогольные напитки', 'Безалкогольное пиво'],
        (String item) => item,
      );

      expect(match.type, VoiceListMatchType.ambiguous);
      expect(match.matches,
          <String>['Безалкогольные напитки', 'Безалкогольное пиво']);
    });

    test('does not fuzzy match short words by prefix', () {
      final VoiceListMatch<String> match = VoiceListMatcher.match(
        'чай',
        <String>['часть'],
        (String item) => item,
      );

      expect(match.type, VoiceListMatchType.none);
    });

    test('does not match a short substring inside another word', () {
      final VoiceListMatch<String> result = VoiceListMatcher.match(
        'сок',
        <String>['Высокий стакан'],
        (String item) => item,
      );

      expect(result.type, VoiceListMatchType.none);
    });

    test('allows partial matching only for long enough phrases', () {
      expect(VoiceListMatcher.canMatchPartial('молоко'), isFalse);
      expect(VoiceListMatcher.canMatchPartial('безалкогольное'), isTrue);
    });

    test('matches short exact word when explicitly requested', () {
      final VoiceListMatch<String> match = VoiceListMatcher.matchExactWord(
        'белый',
        <String>['MOCK Белый 1', 'MOCK Желтый 1'],
        (String item) => item,
        minLength: 5,
      );

      expect(match.type, VoiceListMatchType.unique);
      expect(match.item, 'MOCK Белый 1');
    });

    test('normalizes short exact word for printer labels', () {
      final VoiceListMatch<String> yellow = VoiceListMatcher.matchExactWord(
        'жёлтый',
        <String>['MOCK Белый 1', 'MOCK Желтый 1', 'MOCK Мобильный 2'],
        (String item) => item,
        minLength: 5,
      );
      final VoiceListMatch<String> mobile = VoiceListMatcher.matchExactWord(
        'мобильный',
        <String>['MOCK Белый 1', 'MOCK Желтый 1', 'MOCK Мобильный 2'],
        (String item) => item,
        minLength: 5,
      );

      expect(yellow.type, VoiceListMatchType.unique);
      expect(yellow.item, 'MOCK Желтый 1');
      expect(mobile.type, VoiceListMatchType.unique);
      expect(mobile.item, 'MOCK Мобильный 2');
    });

    test('does not match short exact word below minimum length', () {
      final VoiceListMatch<String> match = VoiceListMatcher.matchExactWord(
        'мок',
        <String>['MOCK Белый 1'],
        (String item) => item,
        minLength: 5,
      );

      expect(match.type, VoiceListMatchType.none);
    });

    test('keeps short exact word ambiguous when multiple items match', () {
      final VoiceListMatch<String> match = VoiceListMatcher.matchExactWord(
        'белый',
        <String>['MOCK Белый 1', 'MOCK Белый 2'],
        (String item) => item,
        minLength: 5,
      );

      expect(match.type, VoiceListMatchType.ambiguous);
    });
  });
}
