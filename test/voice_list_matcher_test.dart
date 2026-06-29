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

    test('allows partial matching only for long enough phrases', () {
      expect(VoiceListMatcher.canMatchPartial('молоко'), isFalse);
      expect(VoiceListMatcher.canMatchPartial('безалкогольное'), isTrue);
    });
  });
}
