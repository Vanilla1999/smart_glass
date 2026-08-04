import 'package:flutter_test/flutter_test.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/voice_search_phrase_policy.dart';

void main() {
  group('VoiceSearchPhrasePolicy', () {
    test('rejects conjunctions, prepositions and filler sounds', () {
      for (final String phrase in <String>[
        'и',
        'а',
        'э',
        'ну',
        'в и на',
        'эээ',
        'ээээ',
        'ммм',
        '[unk]',
      ]) {
        expect(
          VoiceSearchPhrasePolicy.isMeaningful(phrase),
          isFalse,
          reason: phrase,
        );
      }
    });

    test('keeps short real product words', () {
      for (final String phrase in <String>['сыр', 'чай', 'сок', 'чудо']) {
        expect(
          VoiceSearchPhrasePolicy.isMeaningful(phrase),
          isTrue,
          reason: phrase,
        );
      }
    });

    test('accepts a phrase when at least one token is meaningful', () {
      expect(VoiceSearchPhrasePolicy.isMeaningful('и молоко'), isTrue);
      expect(VoiceSearchPhrasePolicy.isMeaningful('на чудо'), isTrue);
    });
  });
}
