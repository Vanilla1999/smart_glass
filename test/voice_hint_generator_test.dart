import 'package:flutter_test/flutter_test.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/voice_hint_generator.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/voice_list_matcher.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/voice_utterance_coordinator.dart';

void main() {
  test('selects a unique word when the leading word is shared', () {
    final VoiceDynamicItemsSnapshot snapshot = _snapshot(<VoiceDynamicItem>[
      const VoiceDynamicItem(id: '1', label: 'Молоко Простоквашино'),
      const VoiceDynamicItem(id: '2', label: 'Молоко Домик'),
    ]);

    final VoiceHintSet hints = VoiceHintGenerator.generate(snapshot);

    expect(hints.hintsByItemId['1']?.phrase, 'простоквашино');
    expect(hints.hintsByItemId['2']?.phrase, 'домик');
    expect(
      hints.advertisedPhrases,
      containsAll(<String>['простоквашино', 'домик']),
    );
    expect(hints.issues, isEmpty);
  });

  test('prefers the first word over a shorter later word', () {
    final VoiceHintSet hints = VoiceHintGenerator.generate(_snapshot(
      <VoiceDynamicItem>[
        const VoiceDynamicItem(
          id: '1',
          label: 'Простоквашино Чай',
        ),
        const VoiceDynamicItem(id: '2', label: 'Фермерское Молоко'),
      ],
    ));

    expect(hints.hintsByItemId['1']?.phrase, 'простоквашино');
  });

  test('combines shared words when their order makes a unique phrase', () {
    final VoiceDynamicItemsSnapshot snapshot = _snapshot(<VoiceDynamicItem>[
      const VoiceDynamicItem(id: '1', label: 'Молоко Домик'),
      const VoiceDynamicItem(id: '2', label: 'Домик Молоко'),
    ]);

    final VoiceHintSet hints = VoiceHintGenerator.generate(snapshot);

    expect(hints.hintsByItemId['1']?.phrase, 'молоко домик');
    expect(hints.hintsByItemId['2']?.phrase, 'домик молоко');
    expect(hints.hintsByItemId.values.every((hint) => hint.ranges.length == 1),
        isTrue);
    expect(
      hints.hintsByItemId.values.every((hint) => hint.phrase.contains(' ')),
      isTrue,
    );
  });

  test('rejects one-letter stop-word and number-only labels', () {
    final VoiceDynamicItemsSnapshot snapshot = _snapshot(<VoiceDynamicItem>[
      const VoiceDynamicItem(id: 'letter', label: 'Я'),
      const VoiceDynamicItem(id: 'stop', label: 'В'),
      const VoiceDynamicItem(id: 'number', label: '123'),
    ]);

    final VoiceHintSet hints = VoiceHintGenerator.generate(snapshot);

    expect(hints.hintsByItemId, isEmpty);
    expect(hints.issues.map((issue) => issue.itemId),
        containsAll(<String>['letter', 'stop', 'number']));
  });

  test('allows meaningful three-character words and preserves label range', () {
    final VoiceDynamicItemsSnapshot snapshot = _snapshot(<VoiceDynamicItem>[
      const VoiceDynamicItem(id: 'cheese', label: 'Сыр фермерский'),
      const VoiceDynamicItem(id: 'tea', label: 'Чай зелёный'),
    ]);

    final VoiceHintSet hints = VoiceHintGenerator.generate(snapshot);
    final VoiceHint cheese = hints.hintsByItemId['cheese']!;

    expect(cheese.phrase, 'сыр');
    expect(cheese.ranges.single.start, 0);
    expect(cheese.ranges.single.end, 3);
    expect(
      VoiceListMatcher.match<VoiceDynamicItem>(
        cheese.phrase,
        snapshot.items,
        (VoiceDynamicItem item) => item.label,
      ).item?.id,
      'cheese',
    );
  });

  test('does not advertise indistinguishable duplicate labels', () {
    final VoiceHintSet hints = VoiceHintGenerator.generate(_snapshot(
      <VoiceDynamicItem>[
        const VoiceDynamicItem(id: '1', label: 'Белый принтер'),
        const VoiceDynamicItem(id: '2', label: 'Белый принтер'),
      ],
    ));

    expect(hints.hintsByItemId, isEmpty);
    expect(hints.advertisedPhrases, isEmpty);
    expect(hints.issues, hasLength(2));
    expect(
      hints.issues.every(
        (VoiceHintValidationIssue issue) =>
            issue.reason == 'no_unique_voice_hint',
      ),
      isTrue,
    );
  });

  test('does not advertise a fixed command as a voice hint', () {
    final VoiceHintSet hints = VoiceHintGenerator.generate(
      _snapshot(<VoiceDynamicItem>[
        const VoiceDynamicItem(id: 'back', label: 'Назад'),
        const VoiceDynamicItem(id: 'milk', label: 'Молоко'),
      ]),
      reservedPhrases: const <String>{'назад'},
    );

    expect(hints.hintsByItemId.containsKey('back'), isFalse);
    expect(hints.hintsByItemId['milk']?.phrase, 'молоко');
  });

  test('alias metadata participates in snapshot identity', () {
    const VoiceDynamicItem first = VoiceDynamicItem(
      id: 'milk',
      label: 'Молоко',
      voiceAliases: <String>['пакет'],
    );
    const VoiceDynamicItem second = VoiceDynamicItem(
      id: 'milk',
      label: 'Молоко',
      voiceAliases: <String>['бутылка'],
    );

    expect(first.revisionHash, isNot(second.revisionHash));
  });

  test('aliases do not override the first visible label word', () {
    final VoiceHintSet hints = VoiceHintGenerator.generate(_snapshot(
      <VoiceDynamicItem>[
        const VoiceDynamicItem(
          id: 'milk',
          label: 'Молоко Домик',
          voiceAliases: <String>['домик'],
        ),
        const VoiceDynamicItem(id: 'other', label: 'Молоко Фермерское'),
      ],
    ));

    expect(hints.hintsByItemId['milk']?.phrase, 'домик');
  });

  test('skips Latin mixed and numeric tokens', () {
    final VoiceHintSet hints = VoiceHintGenerator.generate(_snapshot(
      <VoiceDynamicItem>[
        const VoiceDynamicItem(id: 'latin', label: 'Coca Cola'),
        const VoiceDynamicItem(id: 'drink', label: 'Coca Cola напиток'),
        const VoiceDynamicItem(id: 'shoes', label: 'Adidas кроссовки мужские'),
        const VoiceDynamicItem(id: 'milk', label: 'A12 Товар12 Молоко'),
        const VoiceDynamicItem(id: 'numeric', label: '123 456'),
      ],
    ));

    expect(hints.hintsByItemId.containsKey('latin'), isFalse);
    expect(hints.hintsByItemId['drink']?.phrase, 'напиток');
    expect(hints.hintsByItemId['shoes']?.phrase, 'кроссовки');
    expect(hints.hintsByItemId['milk']?.phrase, 'молоко');
    expect(hints.hintsByItemId.containsKey('numeric'), isFalse);
    expect(hints.hintsByItemId['drink']?.ranges.single.start, 10);
  });

  test('skips excluded and reserved words from left to right', () {
    final VoiceHintSet hints = VoiceHintGenerator.generate(
      _snapshot(<VoiceDynamicItem>[
        const VoiceDynamicItem(id: '1', label: 'Назад Молоко Домик'),
      ]),
      reservedPhrases: const <String>{'назад'},
      excludedWords: const <String>{'молоко'},
    );

    expect(hints.hintsByItemId['1']?.phrase, 'домик');
  });

  test('excludes inflected words using matcher semantics', () {
    final VoiceHintSet hints = VoiceHintGenerator.generate(
      _snapshot(<VoiceDynamicItem>[
        const VoiceDynamicItem(id: '1', label: 'Жёлтый принтер Альфа'),
        const VoiceDynamicItem(id: '2', label: 'Жёлтого принтера Бета'),
      ]),
      excludedWords: const <String>{'жёлтый'},
    );

    expect(hints.hintsByItemId['1']?.phrase, 'альфа');
    expect(hints.hintsByItemId['2']?.phrase, 'бета');
  });

  test('indexes a large availability catalog without pairwise scans', () {
    final List<VoiceDynamicItem> items = List<VoiceDynamicItem>.generate(
      1063,
      (int index) => VoiceDynamicItem(
        id: '$index',
        label: 'Напиток уникальный${_russianSuffix(index)} газированный',
      ),
      growable: false,
    );

    final Stopwatch stopwatch = Stopwatch()..start();
    final VoiceHintSet hints = VoiceHintGenerator.generate(_snapshot(items));
    stopwatch.stop();

    expect(hints.hintsByItemId, hasLength(items.length));
    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 2)));
  });

  test('indexes a large catalog with unique first words', () {
    final List<VoiceDynamicItem> items = List<VoiceDynamicItem>.generate(
      2000,
      (int index) => VoiceDynamicItem(
        id: '$index',
        label: 'Товар${_russianSuffix(index)} газированный',
      ),
      growable: false,
    );

    final Stopwatch stopwatch = Stopwatch()..start();
    final VoiceHintSet hints = VoiceHintGenerator.generate(_snapshot(items));
    stopwatch.stop();

    expect(hints.hintsByItemId, hasLength(items.length));
    expect(hints.advertisedPhrases, hasLength(items.length));
    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 2)));
  });
}

String _russianSuffix(int value) {
  const String alphabet = 'абвгдежзиклмнопрстуфхцчшщэюя';
  final StringBuffer result = StringBuffer();
  var current = value;
  do {
    result.write(alphabet[current % alphabet.length]);
    current ~/= alphabet.length;
  } while (current > 0);
  return result.toString();
}

VoiceDynamicItemsSnapshot _snapshot(List<VoiceDynamicItem> items) {
  return VoiceDynamicItemsSnapshot(
    revision: Object.hashAll(
      items.map((VoiceDynamicItem item) => item.revisionHash),
    ),
    items: items,
  );
}
