enum VoiceListMatchType {
  none,
  unique,
  ambiguous,
}

class VoiceListMatch<T> {
  const VoiceListMatch._({
    required this.type,
    this.item,
    required this.matches,
  });

  factory VoiceListMatch.none() {
    return VoiceListMatch<T>._(
      type: VoiceListMatchType.none,
      matches: <T>[],
    );
  }

  factory VoiceListMatch.unique(T item) {
    return VoiceListMatch<T>._(
      type: VoiceListMatchType.unique,
      item: item,
      matches: <T>[item],
    );
  }

  factory VoiceListMatch.ambiguous(List<T> matches) {
    return VoiceListMatch<T>._(
      type: VoiceListMatchType.ambiguous,
      matches: matches,
    );
  }

  final VoiceListMatchType type;
  final T? item;
  final List<T> matches;
}

class VoiceListMatcher {
  const VoiceListMatcher._();

  static const int _minFuzzyPrefixLength = 6;
  static const double _minFuzzyPrefixRatio = 0.7;
  static const int minPartialMatchLength = 8;

  static bool canMatchPartial(String phrase) {
    return normalize(phrase).length >= minPartialMatchLength;
  }

  static VoiceListMatch<T> matchExactWord<T>(
    String phrase,
    List<T> items,
    String Function(T item) labelOf, {
    int minLength = 1,
  }) {
    final String query = normalize(phrase);
    if (query.length < minLength || query.contains(' ') || items.isEmpty) {
      return VoiceListMatch<T>.none();
    }

    final List<T> matches = items.where((T item) {
      final List<String> words = normalize(labelOf(item)).split(' ');
      return words.contains(query);
    }).toList(growable: false);

    if (matches.isEmpty) {
      return VoiceListMatch<T>.none();
    }
    if (matches.length == 1) {
      return VoiceListMatch<T>.unique(matches.single);
    }
    return VoiceListMatch<T>.ambiguous(matches);
  }

  static VoiceListMatch<T> match<T>(
    String phrase,
    List<T> items,
    String Function(T item) labelOf, {
    Iterable<String> Function(T item)? aliasesOf,
  }) {
    final String query = normalize(phrase);
    if (query.isEmpty || items.isEmpty) {
      return VoiceListMatch<T>.none();
    }

    final List<String> queryWords = query.split(' ');
    final List<T> matches = items.where((T item) {
      final List<String> searchable = <String>[
        normalize(labelOf(item)),
        ...?aliasesOf?.call(item).map(normalize),
      ].where((String value) => value.isNotEmpty).toList(growable: false);
      if (searchable.any((String value) => _containsPhrase(value, query))) {
        return true;
      }
      final List<String> words = searchable
          .expand((value) => value.split(' '))
          .toList(growable: false);
      return _allQueryWordsMatch(queryWords, words);
    }).toList(growable: false);

    if (matches.isEmpty) {
      return VoiceListMatch<T>.none();
    }
    if (matches.length == 1) {
      return VoiceListMatch<T>.unique(matches.single);
    }
    return VoiceListMatch<T>.ambiguous(matches);
  }

  static VoiceListMatch<T> matchExactPhrase<T>(
    String phrase,
    List<T> items,
    String Function(T item) labelOf, {
    Iterable<String> Function(T item)? aliasesOf,
  }) {
    final String query = normalize(phrase);
    if (query.isEmpty || items.isEmpty) return VoiceListMatch<T>.none();
    final List<T> matches = items.where((T item) {
      return <String>[
        normalize(labelOf(item)),
        ...?aliasesOf?.call(item).map(normalize),
      ].any(
          (String value) => value.isNotEmpty && _containsPhrase(value, query));
    }).toList(growable: false);
    if (matches.isEmpty) return VoiceListMatch<T>.none();
    if (matches.length == 1) return VoiceListMatch<T>.unique(matches.single);
    return VoiceListMatch<T>.ambiguous(matches);
  }

  static String normalize(String value) {
    return value
        .toLowerCase()
        .replaceAll('ё', 'е')
        .replaceAll(RegExp(r'[^0-9a-zа-я\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static bool _allQueryWordsMatch(
    List<String> queryWords,
    List<String> labelWords,
  ) {
    return queryWords.every((String queryWord) {
      return labelWords.any((String labelWord) {
        return _wordMatches(queryWord, labelWord);
      });
    });
  }

  static bool _wordMatches(String queryWord, String labelWord) {
    if (labelWord == queryWord) {
      return true;
    }
    final int shorterLength = queryWord.length < labelWord.length
        ? queryWord.length
        : labelWord.length;
    if (shorterLength < _minFuzzyPrefixLength) {
      return false;
    }

    final int commonPrefix = _commonPrefixLength(queryWord, labelWord);
    if (commonPrefix < _minFuzzyPrefixLength) {
      return false;
    }
    return commonPrefix / shorterLength >= _minFuzzyPrefixRatio;
  }

  static bool _containsPhrase(String label, String query) {
    return label == query ||
        label.startsWith('$query ') ||
        label.endsWith(' $query') ||
        label.contains(' $query ');
  }

  static int _commonPrefixLength(String left, String right) {
    final int length = left.length < right.length ? left.length : right.length;
    var index = 0;
    while (
        index < length && left.codeUnitAt(index) == right.codeUnitAt(index)) {
      index++;
    }
    return index;
  }
}
