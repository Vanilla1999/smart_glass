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
    required this.itemIdByPhrase,
    required this.issues,
  });

  final int revision;
  final Map<String, VoiceHint> hintsByItemId;
  final Map<String, String> itemIdByPhrase;
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
    final Set<String> normalizedExcluded =
        excludedWords.map(VoiceListMatcher.normalize).toSet();
    if (excludedWords.isNotEmpty && snapshot.items.isNotEmpty) {
      final Set<String> commonWords = _tokens(snapshot.items.first.label)
          .map((_LabelToken token) => token.normalized)
          .where(_isMeaningful)
          .toSet();
      for (final VoiceDynamicItem item in snapshot.items.skip(1)) {
        commonWords.retainAll(
          _tokens(item.label)
              .map((_LabelToken token) => token.normalized)
              .where(_isMeaningful),
        );
      }
      normalizedExcluded.addAll(commonWords);
    }
    final Map<String, Set<String>> phraseOwners = _phraseOwners(snapshot.items);
    final Map<String, VoiceHint> hints = <String, VoiceHint>{};
    final List<VoiceHintValidationIssue> issues = <VoiceHintValidationIssue>[];
    for (final VoiceDynamicItem item in snapshot.items) {
      final List<_LabelToken> tokens = _tokens(item.label);
      VoiceHint? selected;
      VoiceHint? tryCandidate(List<_LabelToken> candidate) {
        if (!_isValid(candidate)) return null;
        final String phrase =
            candidate.map((_LabelToken token) => token.normalized).join(' ');
        if (normalizedReserved.contains(phrase) ||
            !candidate.any((_LabelToken token) =>
                _isMeaningful(token.normalized) &&
                !normalizedExcluded.contains(token.normalized))) {
          return null;
        }
        final Set<String>? owners = phraseOwners[phrase];
        if (owners == null || owners.length != 1 || !owners.contains(item.id)) {
          return null;
        }
        return VoiceHint(
          itemId: item.id,
          phrase: phrase,
          ranges: <VoiceHintRange>[
            VoiceHintRange(
              start: candidate.first.start,
              end: candidate.last.end,
            ),
          ],
        );
      }

      for (final String alias in item.voiceAliases) {
        final String normalizedAlias = VoiceListMatcher.normalize(alias);
        for (int wordCount = 1;
            wordCount <= tokens.length && selected == null;
            wordCount++) {
          for (int start = 0;
              start + wordCount <= tokens.length && selected == null;
              start++) {
            final candidate = tokens.sublist(start, start + wordCount);
            final phrase = candidate.map((token) => token.normalized).join(' ');
            if (phrase == normalizedAlias) selected = tryCandidate(candidate);
          }
        }
      }
      for (int wordCount = 1;
          wordCount <= tokens.length && selected == null;
          wordCount++) {
        final List<List<_LabelToken>> candidates = <List<_LabelToken>>[
          for (int start = 0; start + wordCount <= tokens.length; start++)
            tokens.sublist(start, start + wordCount),
        ]..sort((List<_LabelToken> left, List<_LabelToken> right) {
            final int byLength = left
                .map((_LabelToken token) => token.normalized)
                .join(' ')
                .length
                .compareTo(right
                    .map((_LabelToken token) => token.normalized)
                    .join(' ')
                    .length);
            return byLength != 0
                ? byLength
                : left.first.start.compareTo(right.first.start);
          });
        for (final List<_LabelToken> candidate in candidates) {
          selected = tryCandidate(candidate);
          if (selected != null) break;
        }
      }
      if (selected == null) {
        issues.add(VoiceHintValidationIssue(
          itemId: item.id,
          reason: 'no_unique_meaningful_phrase',
        ));
      } else {
        hints[item.id] = selected;
      }
    }
    return VoiceHintSet(
      revision: snapshot.revision,
      hintsByItemId: Map<String, VoiceHint>.unmodifiable(hints),
      itemIdByPhrase: Map<String, String>.unmodifiable(
        <String, String>{
          for (final VoiceHint hint in hints.values) hint.phrase: hint.itemId,
        },
      ),
      issues: List<VoiceHintValidationIssue>.unmodifiable(issues),
    );
  }

  static bool _isValid(List<_LabelToken> tokens) {
    if (tokens.isEmpty) return false;
    return tokens.any((_LabelToken token) {
      final String word = token.normalized;
      return _isMeaningful(word);
    });
  }

  static bool _isMeaningful(String word) =>
      word.length > 1 &&
      !_stopWords.contains(word) &&
      !RegExp(r'^\d+$').hasMatch(word);

  static Map<String, Set<String>> _phraseOwners(
    List<VoiceDynamicItem> items,
  ) {
    final Map<String, Set<String>> owners = <String, Set<String>>{};
    for (final VoiceDynamicItem item in items) {
      for (final String searchable in <String>[
        item.label,
        ...item.voiceAliases,
      ]) {
        final List<String> words = VoiceListMatcher.normalize(searchable)
            .split(' ')
            .where((String word) => word.isNotEmpty)
            .toList(growable: false);
        for (int start = 0; start < words.length; start++) {
          final StringBuffer phrase = StringBuffer();
          for (int end = start; end < words.length; end++) {
            if (phrase.isNotEmpty) phrase.write(' ');
            phrase.write(words[end]);
            owners
                .putIfAbsent(phrase.toString(), () => <String>{})
                .add(item.id);
          }
        }
      }
    }
    return owners;
  }

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
