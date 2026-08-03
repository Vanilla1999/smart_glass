import 'package:smart_glasses/modules/wear/domain/service/voice_command/voice_list_matcher.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/voice_utterance_coordinator.dart';

class VoiceHintRange {
  const VoiceHintRange({required this.start, required this.end});

  final int start;
  final int end;
}

class VoiceHint {
  const VoiceHint({
    required this.itemId,
    required this.phrase,
    required this.ranges,
  });

  final String itemId;
  final String phrase;
  final List<VoiceHintRange> ranges;
}

class VoiceHintValidationIssue {
  const VoiceHintValidationIssue({required this.itemId, required this.reason});

  final String itemId;
  final String reason;
}

class VoiceHintSet {
  const VoiceHintSet({
    required this.revision,
    required this.hintsByItemId,
    required this.advertisedPhrases,
    required this.issues,
  });

  final int revision;
  final Map<String, VoiceHint> hintsByItemId;
  final Set<String> advertisedPhrases;
  final List<VoiceHintValidationIssue> issues;
}

class VoiceHintGenerator {
  const VoiceHintGenerator._();

  static const Set<String> _stopWords = <String>{
    'в',
    'во',
    'на',
    'для',
    'из',
    'с',
    'со',
    'к',
    'ко',
    'у',
    'о',
    'об',
    'от',
    'до',
    'по',
    'и',
    'а',
    'но',
  };

  static VoiceHintSet generate(
    VoiceDynamicItemsSnapshot snapshot, {
    Set<String> reservedPhrases = const <String>{},
    Set<String> excludedWords = const <String>{},
  }) {
    final Set<String> normalizedReserved =
        reservedPhrases.map(VoiceListMatcher.normalize).toSet();
    final Set<String> normalizedExcluded = excludedWords
        .map(VoiceListMatcher.normalize)
        .expand((String phrase) => phrase.split(' '))
        .where((String word) => word.isNotEmpty)
        .toSet();
    if (excludedWords.isNotEmpty && snapshot.items.length > 1) {
      final Set<String> commonWords = _tokens(snapshot.items.first.label)
          .map((_LabelToken token) => token.normalized)
          .where(_isMeaningful)
          .toSet();
      for (final VoiceDynamicItem item in snapshot.items.skip(1)) {
        final List<String> itemWords = _tokens(item.label)
            .map((_LabelToken token) => token.normalized)
            .where(_isMeaningful)
            .toList(growable: false);
        commonWords.removeWhere((String commonWord) => !itemWords.any(
              (String itemWord) =>
                  VoiceListMatcher.wordsMatch(commonWord, itemWord),
            ));
      }
      normalizedExcluded.addAll(commonWords);
    }
    final Map<String, VoiceHint> hints = <String, VoiceHint>{};
    final List<VoiceHintValidationIssue> issues = <VoiceHintValidationIssue>[];
    for (final VoiceDynamicItem item in snapshot.items) {
      final List<_LabelToken> tokens = _tokens(item.label);
      final _LabelToken? selected = tokens.cast<_LabelToken?>().firstWhere(
            (_LabelToken? token) =>
                token != null &&
                _isMeaningful(token.normalized) &&
                !normalizedReserved.contains(token.normalized) &&
                !normalizedExcluded.any((String excluded) =>
                    VoiceListMatcher.wordsMatch(token.normalized, excluded)),
            orElse: () => null,
          );
      if (selected == null) {
        issues.add(VoiceHintValidationIssue(
          itemId: item.id,
          reason: 'no_valid_cyrillic_word',
        ));
      } else {
        hints[item.id] = VoiceHint(
          itemId: item.id,
          phrase: selected.normalized,
          ranges: <VoiceHintRange>[
            VoiceHintRange(
              start: selected.start,
              end: selected.end,
            ),
          ],
        );
      }
    }
    return VoiceHintSet(
      revision: snapshot.revision,
      hintsByItemId: Map<String, VoiceHint>.unmodifiable(hints),
      advertisedPhrases: Set<String>.unmodifiable(
        hints.values.map((VoiceHint hint) => hint.phrase),
      ),
      issues: List<VoiceHintValidationIssue>.unmodifiable(issues),
    );
  }

  static bool _isMeaningful(String word) =>
      word.length > 1 &&
      !_stopWords.contains(word) &&
      RegExp(r'^[а-яё]+$', caseSensitive: false).hasMatch(word);

  static List<_LabelToken> _tokens(String label) {
    return RegExp(r'[0-9A-Za-zА-Яа-яЁё]+')
        .allMatches(label)
        .map((match) {
          final String value = match.group(0)!;
          return _LabelToken(
            normalized: VoiceListMatcher.normalize(value),
            start: match.start,
            end: match.end,
          );
        })
        .where((_LabelToken token) => token.normalized.isNotEmpty)
        .toList(
          growable: false,
        );
  }
}

class _LabelToken {
  const _LabelToken({
    required this.normalized,
    required this.start,
    required this.end,
  });

  final String normalized;
  final int start;
  final int end;
}
