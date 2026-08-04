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

  static const int _maxHintWords = 4;
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
    final Map<String, List<_HintCandidate>> candidatesByItemId =
        <String, List<_HintCandidate>>{};
    final Map<String, String?> uniqueOwners = <String, String?>{};
    for (final VoiceDynamicItem item in snapshot.items) {
      final List<_HintCandidate> labelCandidates = _candidatesForText(
        item.label,
        normalizedReserved: normalizedReserved,
        normalizedExcluded: normalizedExcluded,
      );
      candidatesByItemId[item.id] = labelCandidates;
      _registerCandidateOwners(uniqueOwners, item.id, labelCandidates);
      for (final String alias in item.voiceAliases) {
        _registerCandidateOwners(
          uniqueOwners,
          item.id,
          _candidatesForText(
            alias,
            normalizedReserved: normalizedReserved,
            normalizedExcluded: normalizedExcluded,
          ),
        );
      }
    }

    final Map<String, VoiceHint> hints = <String, VoiceHint>{};
    final List<VoiceHintValidationIssue> issues = <VoiceHintValidationIssue>[];
    for (final VoiceDynamicItem item in snapshot.items) {
      final List<_HintCandidate> candidates =
          candidatesByItemId[item.id] ?? const <_HintCandidate>[];
      _HintCandidate? selected;
      for (final _HintCandidate candidate in candidates) {
        if (uniqueOwners.containsKey(candidate.phrase) &&
            uniqueOwners[candidate.phrase] == item.id) {
          selected = candidate;
          break;
        }
      }
      if (selected == null) {
        issues.add(VoiceHintValidationIssue(
          itemId: item.id,
          reason: candidates.isEmpty
              ? 'no_valid_cyrillic_word'
              : 'no_unique_voice_hint',
        ));
      } else {
        hints[item.id] = VoiceHint(
          itemId: item.id,
          phrase: selected.phrase,
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

  static void _registerCandidateOwners(
    Map<String, String?> owners,
    String itemId,
    List<_HintCandidate> candidates,
  ) {
    for (final _HintCandidate candidate in candidates) {
      if (!owners.containsKey(candidate.phrase)) {
        owners[candidate.phrase] = itemId;
      } else if (owners[candidate.phrase] != itemId) {
        owners[candidate.phrase] = null;
      }
    }
  }

  static List<_HintCandidate> _candidatesForText(
    String text, {
    required Set<String> normalizedReserved,
    required Set<String> normalizedExcluded,
  }) {
    final List<_LabelToken> tokens = _tokens(text);
    final Map<String, _HintCandidate> candidates = <String, _HintCandidate>{};
    for (int start = 0; start < tokens.length; start++) {
      if (!_isEligibleToken(
        tokens[start],
        normalizedReserved: normalizedReserved,
        normalizedExcluded: normalizedExcluded,
      )) {
        continue;
      }
      final List<_LabelToken> phraseTokens = <_LabelToken>[];
      for (int end = start;
          end < tokens.length && phraseTokens.length < _maxHintWords;
          end++) {
        final _LabelToken token = tokens[end];
        if (!_isEligibleToken(
          token,
          normalizedReserved: normalizedReserved,
          normalizedExcluded: normalizedExcluded,
        )) {
          break;
        }
        phraseTokens.add(token);
        final String phrase =
            phraseTokens.map((token) => token.normalized).join(' ');
        if (normalizedReserved.contains(phrase)) continue;
        candidates.putIfAbsent(
          phrase,
          () => _HintCandidate(
            phrase: phrase,
            start: phraseTokens.first.start,
            end: phraseTokens.last.end,
            wordCount: phraseTokens.length,
          ),
        );
      }
    }
    final List<_HintCandidate> result = candidates.values.toList();
    result.sort((_HintCandidate left, _HintCandidate right) {
      final int words = left.wordCount.compareTo(right.wordCount);
      if (words != 0) return words;
      final int position = left.start.compareTo(right.start);
      if (position != 0) return position;
      return left.phrase.length.compareTo(right.phrase.length);
    });
    return List<_HintCandidate>.unmodifiable(result);
  }

  static bool _isEligibleToken(
    _LabelToken token, {
    required Set<String> normalizedReserved,
    required Set<String> normalizedExcluded,
  }) {
    return _isMeaningful(token.normalized) &&
        !normalizedReserved.contains(token.normalized) &&
        !normalizedExcluded.any(
          (String excluded) =>
              VoiceListMatcher.wordsMatch(token.normalized, excluded),
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

class _HintCandidate {
  const _HintCandidate({
    required this.phrase,
    required this.start,
    required this.end,
    required this.wordCount,
  });

  final String phrase;
  final int start;
  final int end;
  final int wordCount;
}
