import 'package:smart_glasses/modules/wear/domain/service/voice_command/voice_list_matcher.dart';

class VoiceSearchPhrasePolicy {
  const VoiceSearchPhrasePolicy._();

  static const Set<String> _ignoredTokens = <String>{
    'а',
    'в',
    'во',
    'для',
    'до',
    'и',
    'из',
    'или',
    'ага',
    'угу',
    'к',
    'ко',
    'м',
    'мм',
    'гм',
    'хм',
    'эм',
    'на',
    'но',
    'ну',
    'о',
    'об',
    'от',
    'по',
    'с',
    'со',
    'у',
    'э',
    'ээ',
    'эээ',
    'unk',
  };

  static bool isMeaningful(String phrase) {
    final String normalized = VoiceListMatcher.normalize(phrase);
    if (normalized.isEmpty) return false;
    return normalized
        .split(' ')
        .where((String token) => token.isNotEmpty)
        .any(_isMeaningfulToken);
  }

  static bool _isMeaningfulToken(String token) {
    if (token.length <= 1 || _ignoredTokens.contains(token)) return false;
    if (RegExp(r'^([аэеыиум])\1+$', caseSensitive: false).hasMatch(token)) {
      return false;
    }
    return RegExp(r'^[0-9a-zа-яё]+$', caseSensitive: false).hasMatch(token);
  }
}
