import 'package:flutter_test/flutter_test.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/voice_hint_generator.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/voice_list_matcher.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/voice_utterance_coordinator.dart';

void main() {
  test('selects the shortest unique meaningful word', () {
    final VoiceDynamicItemsSnapshot snapshot = _snapshot(<VoiceDynamicItem>[
      const VoiceDynamicItem(id: '1', label: 'Молоко Простоквашино'),
      const VoiceDynamicItem(id: '2', label: 'Молоко Домик'),
    ]);

    final VoiceHintSet hints = VoiceHintGenerator.generate(snapshot);

    expect(hints.hintsByItemId['1']?.phrase, 'простоквашино');
    expect(hints.hintsByItemId['2']?.phrase, 'домик');
    expect(hints.issues, isEmpty);
  });

  test('prefers the shortest of multiple unique words', () {
    final VoiceHintSet hints = VoiceHintGenerator.generate(_snapshot(
      <VoiceDynamicItem>[
        const VoiceDynamicItem(
          id: '1',
          label: 'Простоквашино Чай',
        ),
        const VoiceDynamicItem(id: '2', label: 'Фермерское Молоко'),
      ],
    ));

    expect(hints.hintsByItemId['1']?.phrase, 'чай');
  });

  test('uses a unique contiguous phrase when single words are shared', () {
    final VoiceDynamicItemsSnapshot snapshot = _snapshot(<VoiceDynamicItem>[
      const VoiceDynamicItem(id: '1', label: 'Молоко Домик'),
      const VoiceDynamicItem(id: '2', label: 'Домик Молоко'),
    ]);

    final VoiceHintSet hints = VoiceHintGenerator.generate(snapshot);

    expect(hints.hintsByItemId['1']?.phrase, 'молоко домик');
    expect(hints.hintsByItemId['2']?.phrase, 'домик молоко');
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

  test('reports indistinguishable duplicate labels', () {
    final VoiceHintSet hints = VoiceHintGenerator.generate(_snapshot(
      <VoiceDynamicItem>[
        const VoiceDynamicItem(id: '1', label: 'Белый принтер'),
        const VoiceDynamicItem(id: '2', label: 'Белый принтер'),
      ],
    ));

    expect(hints.hintsByItemId, isEmpty);
    expect(hints.issues, hasLength(2));
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

  test('prefers an explicit alias that is visible in the label', () {
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

  test('indexes a large availability catalog without pairwise scans', () {
    final List<VoiceDynamicItem> items = List<VoiceDynamicItem>.generate(
      1063,
      (int index) => VoiceDynamicItem(
        id: '$index',
        label: 'Напиток уникальный$index газированный',
      ),
      growable: false,
    );

    final Stopwatch stopwatch = Stopwatch()..start();
    final VoiceHintSet hints = VoiceHintGenerator.generate(_snapshot(items));
    stopwatch.stop();

    expect(hints.hintsByItemId, hasLength(items.length));
    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 2)));
  });
}

VoiceDynamicItemsSnapshot _snapshot(List<VoiceDynamicItem> items) {
  return VoiceDynamicItemsSnapshot(
    revision: Object.hashAll(
      items.map((VoiceDynamicItem item) => item.revisionHash),
    ),
    items: items,
  );
}
