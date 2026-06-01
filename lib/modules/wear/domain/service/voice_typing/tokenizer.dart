enum NumberTokenType { unit, teen, tens, hundred, scale, digitNoun }

class NumberToken {
  const NumberToken(this.type, this.value);

  final NumberTokenType type;
  final int value;

  String toDbg() {
    switch (type) {
      case NumberTokenType.unit:
        return 'UNIT($value)';
      case NumberTokenType.teen:
        return 'TEEN($value)';
      case NumberTokenType.tens:
        return 'TENS($value)';
      case NumberTokenType.hundred:
        return 'HUNDRED($value)';
      case NumberTokenType.scale:
        return 'SCALE($value)';
      case NumberTokenType.digitNoun:
        return 'DIGIT_NOUN($value)';
    }
  }
}

class NumberTokenizer {
  const NumberTokenizer();

  List<NumberToken> tokenize(String input) {
    final normalized = _normalize(input);
    final words = normalized.isEmpty ? const <String>[] : normalized.split(' ');

    final tokens = <NumberToken>[];
    for (final word in words) {
      final token = _dictionary[word];
      if (token != null) {
        tokens.add(token);
      }
    }

    print('TOKENS: ${tokens.map((token) => token.toDbg()).join(' ')}');
    return tokens;
  }

  String _normalize(String input) {
    return input
        .toLowerCase()
        .replaceAll('ё', 'е')
        .replaceAll(RegExp(r'[-–—_/]'), ' ')
        .replaceAll(RegExp(r'[^0-9a-zа-я\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static final Map<String, NumberToken> _dictionary = _buildDictionary();

  static Map<String, NumberToken> _buildDictionary() {
    final map = <String, NumberToken>{};

    void add(NumberToken token, List<String> forms) {
      for (final form in forms) {
        map[form] = token;
      }
    }

    add(const NumberToken(NumberTokenType.unit, 0), <String>[
      'ноль',
      'нуль',
    ]);
    add(const NumberToken(NumberTokenType.unit, 1), <String>[
      'один',
      'одна',
      'одно',
      'одну',
      'одного',
      'одной',
      'одному',
      'одним',
      'одном',
      'одни',
      'одних',
      'одними',
    ]);
    add(const NumberToken(NumberTokenType.unit, 2), <String>[
      'два',
      'две',
      'двух',
      'двум',
      'двумя',
    ]);
    add(const NumberToken(NumberTokenType.unit, 3), <String>[
      'три',
      'трех',
      'трем',
      'тремя',
    ]);
    add(const NumberToken(NumberTokenType.unit, 4), <String>[
      'четыре',
      'четырех',
      'четырем',
      'четырьмя',
    ]);
    add(const NumberToken(NumberTokenType.unit, 5), <String>[
      'пять',
      'пяти',
      'пятью',
    ]);
    add(const NumberToken(NumberTokenType.unit, 6), <String>[
      'шесть',
      'шести',
      'шестью',
    ]);
    add(const NumberToken(NumberTokenType.unit, 7), <String>[
      'семь',
      'семи',
      'семью',
    ]);
    add(const NumberToken(NumberTokenType.unit, 8), <String>[
      'восемь',
      'восьми',
      'восемью',
    ]);
    add(const NumberToken(NumberTokenType.unit, 9), <String>[
      'девять',
      'девяти',
      'девятью',
    ]);

    add(const NumberToken(NumberTokenType.teen, 10), <String>[
      'десять',
      'десяти',
      'десятью',
    ]);
    add(const NumberToken(NumberTokenType.teen, 11), <String>[
      'одиннадцать',
      'одиннадцати',
      'одиннадцатью',
      'одинадцать',
      'одинадцати',
      'одинадцатью',
    ]);
    add(const NumberToken(NumberTokenType.teen, 12), <String>[
      'двенадцать',
      'двенадцати',
      'двенадцатью',
    ]);
    add(const NumberToken(NumberTokenType.teen, 13), <String>[
      'тринадцать',
      'тринадцати',
      'тринадцатью',
    ]);
    add(const NumberToken(NumberTokenType.teen, 14), <String>[
      'четырнадцать',
      'четырнадцати',
      'четырнадцатью',
    ]);
    add(const NumberToken(NumberTokenType.teen, 15), <String>[
      'пятнадцать',
      'пятнадцати',
      'пятнадцатью',
    ]);
    add(const NumberToken(NumberTokenType.teen, 16), <String>[
      'шестнадцать',
      'шестнадцати',
      'шестнадцатью',
    ]);
    add(const NumberToken(NumberTokenType.teen, 17), <String>[
      'семнадцать',
      'семнадцати',
      'семнадцатью',
    ]);
    add(const NumberToken(NumberTokenType.teen, 18), <String>[
      'восемнадцать',
      'восемнадцати',
      'восемнадцатью',
    ]);
    add(const NumberToken(NumberTokenType.teen, 19), <String>[
      'девятнадцать',
      'девятнадцати',
      'девятнадцатью',
    ]);

    add(const NumberToken(NumberTokenType.tens, 20), <String>[
      'двадцать',
      'двадцати',
      'двадцатью',
    ]);
    add(const NumberToken(NumberTokenType.tens, 30), <String>[
      'тридцать',
      'тридцати',
      'тридцатью',
    ]);
    add(const NumberToken(NumberTokenType.tens, 40), <String>[
      'сорок',
      'сорока',
    ]);
    add(const NumberToken(NumberTokenType.tens, 50), <String>[
      'пятьдесят',
      'пятидесяти',
      'пятьюдесятью',
    ]);
    add(const NumberToken(NumberTokenType.tens, 60), <String>[
      'шестьдесят',
      'шестидесяти',
      'шестьюдесятью',
    ]);
    add(const NumberToken(NumberTokenType.tens, 70), <String>[
      'семьдесят',
      'семидесяти',
      'семьюдесятью',
    ]);
    add(const NumberToken(NumberTokenType.tens, 80), <String>[
      'восемьдесят',
      'восьмидесяти',
      'восемьюдесятью',
    ]);
    add(const NumberToken(NumberTokenType.tens, 90), <String>[
      'девяносто',
      'девяноста',
    ]);

    add(const NumberToken(NumberTokenType.hundred, 100), <String>[
      'сто',
      'ста',
    ]);
    add(const NumberToken(NumberTokenType.hundred, 200), <String>[
      'двести',
      'двухсот',
      'двумстам',
      'двумястами',
      'двухстах',
    ]);
    add(const NumberToken(NumberTokenType.hundred, 300), <String>[
      'триста',
      'трехсот',
      'тремстам',
      'тремястами',
      'трехстах',
    ]);
    add(const NumberToken(NumberTokenType.hundred, 400), <String>[
      'четыреста',
      'четырехсот',
      'четыремстам',
      'четырьмястами',
      'четырехстах',
    ]);
    add(const NumberToken(NumberTokenType.hundred, 500), <String>[
      'пятьсот',
      'пятисот',
      'пятистам',
      'пятьюстами',
      'пятистах',
    ]);
    add(const NumberToken(NumberTokenType.hundred, 600), <String>[
      'шестьсот',
      'шестисот',
      'шестистам',
      'шестьюстами',
      'шестистах',
    ]);
    add(const NumberToken(NumberTokenType.hundred, 700), <String>[
      'семьсот',
      'семисот',
      'семистам',
      'семьюстами',
      'семистах',
    ]);
    add(const NumberToken(NumberTokenType.hundred, 800), <String>[
      'восемьсот',
      'восьмисот',
      'восьмистам',
      'восемьюстами',
      'восьмистах',
    ]);
    add(const NumberToken(NumberTokenType.hundred, 900), <String>[
      'девятьсот',
      'девятисот',
      'девятистам',
      'девятьюстами',
      'девятистах',
    ]);

    add(const NumberToken(NumberTokenType.scale, 1000), <String>[
      'тысяча',
      'тысячи',
      'тысяч',
      'тысячу',
      'тысячей',
      'тысячью',
      'тысяче',
      'тысячами',
      'тысячах',
      'тыща',
      'тыщи',
      'тыщ',
      'тыщу',
      'тыщей',
      'тыще',
    ]);
    add(const NumberToken(NumberTokenType.scale, 1000000), <String>[
      'миллион',
      'миллиона',
      'миллионов',
      'миллиону',
      'миллионом',
      'миллионе',
      'миллионами',
      'миллионах',
      'лям',
      'ляма',
      'лямов',
      'ляму',
      'лямом',
      'ляме',
    ]);
    add(const NumberToken(NumberTokenType.scale, 1000000000), <String>[
      'миллиард',
      'миллиарда',
      'миллиардов',
      'миллиарду',
      'миллиардом',
      'миллиарде',
      'миллиардами',
      'миллиардах',
      'ярд',
      'ярда',
      'ярдов',
      'ярду',
      'ярдом',
      'ярде',
    ]);
    add(const NumberToken(NumberTokenType.scale, 1000000000000), <String>[
      'триллион',
      'триллиона',
      'триллионов',
      'триллиону',
      'триллионом',
      'триллионе',
      'триллионами',
      'триллионах',
    ]);

    add(const NumberToken(NumberTokenType.digitNoun, 0), <String>[
      'нуля',
      'нулю',
      'нулем',
      'нуле',
      'нули',
      'нулей',
      'нулями',
      'нулях',
      'ноля',
      'нолю',
      'нолем',
      'ноли',
      'нолей',
      'нолями',
      'нолях',
      'налей' // да, и так распознает
    ]);
    add(const NumberToken(NumberTokenType.digitNoun, 1), <String>[
      'единица',
      'единицы',
      'единиц',
      'единицу',
      'единицей',
      'единице',
      'единицами',
      'единицах',
    ]);
    add(const NumberToken(NumberTokenType.digitNoun, 2), <String>[
      'двойка',
      'двойки',
      'двоек',
      'двойку',
      'двойкой',
      'двойке',
      'двойками',
      'двойках',
    ]);
    add(const NumberToken(NumberTokenType.digitNoun, 3), <String>[
      'тройка',
      'тройки',
      'троек',
      'тройку',
      'тройкой',
      'тройке',
      'тройками',
      'тройках',
    ]);
    add(const NumberToken(NumberTokenType.digitNoun, 4), <String>[
      'четверка',
      'четверки',
      'четверок',
      'четверку',
      'четверкой',
      'четверке',
      'четверками',
      'четверках',
    ]);
    add(const NumberToken(NumberTokenType.digitNoun, 5), <String>[
      'пятерка',
      'пятерки',
      'пятерок',
      'пятерку',
      'пятеркой',
      'пятерке',
      'пятерками',
      'пятерках',
    ]);
    add(const NumberToken(NumberTokenType.digitNoun, 6), <String>[
      'шестерка',
      'шестерки',
      'шестерок',
      'шестерку',
      'шестеркой',
      'шестерке',
      'шестерками',
      'шестерках',
    ]);
    add(const NumberToken(NumberTokenType.digitNoun, 7), <String>[
      'семерка',
      'семерки',
      'семерок',
      'семерку',
      'семеркой',
      'семерке',
      'семерками',
      'семерках',
    ]);
    add(const NumberToken(NumberTokenType.digitNoun, 8), <String>[
      'восьмерка',
      'восьмерки',
      'восьмерок',
      'восьмерку',
      'восьмеркой',
      'восьмерке',
      'восьмерками',
      'восьмерках',
    ]);
    add(const NumberToken(NumberTokenType.digitNoun, 9), <String>[
      'девятка',
      'девятки',
      'девяток',
      'девятку',
      'девяткой',
      'девятке',
      'девятками',
      'девятках',
    ]);

    return map;
  }
}
