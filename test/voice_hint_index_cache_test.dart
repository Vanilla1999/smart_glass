import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/voice_hint_generator.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/voice_hint_index_cache.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/voice_utterance_coordinator.dart';

void main() {
  const VoiceDynamicItemsSnapshot snapshot = VoiceDynamicItemsSnapshot(
    revision: 1,
    items: <VoiceDynamicItem>[
      VoiceDynamicItem(id: '1', label: 'Молочная продукция'),
      VoiceDynamicItem(id: '2', label: 'Безалкогольные напитки'),
    ],
  );

  test('cold lookup is non-blocking and prepare caches the result', () async {
    final VoiceHintIndexCache cache = VoiceHintIndexCache();

    expect(cache.getIfReady(snapshot: snapshot), isNull);

    final VoiceHintSet prepared = await cache.prepare(snapshot: snapshot);

    expect(cache.getIfReady(snapshot: snapshot), same(prepared));
    expect(prepared.advertisedPhrases,
        containsAll(<String>['молочная', 'безалкогольные']));
  });

  test('concurrent prepare calls share one generation', () async {
    final Completer<VoiceHintSet> completer = Completer<VoiceHintSet>();
    int buildCount = 0;
    final VoiceHintIndexCache cache = VoiceHintIndexCache(
      builder: (snapshot, reserved) {
        buildCount++;
        return completer.future;
      },
    );

    final Future<VoiceHintSet> first = cache.prepare(snapshot: snapshot);
    final Future<VoiceHintSet> second = cache.prepare(snapshot: snapshot);

    expect(buildCount, 1);
    expect(identical(first, second), isTrue);
    completer.complete(VoiceHintGenerator.generate(snapshot));
    await Future.wait(<Future<VoiceHintSet>>[first, second]);
  });

  test('cold whenReady starts and shares generation', () async {
    final Completer<VoiceHintSet> completer = Completer<VoiceHintSet>();
    int buildCount = 0;
    final VoiceHintIndexCache cache = VoiceHintIndexCache(
      builder: (snapshot, reserved) {
        buildCount++;
        return completer.future;
      },
    );

    final Future<VoiceHintSet> first = cache.whenReady(snapshot: snapshot);
    final Future<VoiceHintSet> second = cache.whenReady(snapshot: snapshot);

    expect(buildCount, 1);
    expect(identical(first, second), isTrue);
    completer.complete(VoiceHintGenerator.generate(snapshot));
    await Future.wait(<Future<VoiceHintSet>>[first, second]);
  });

  test('reserved phrases use a separate cache entry', () async {
    int buildCount = 0;
    final VoiceHintIndexCache cache = VoiceHintIndexCache(
      builder: (snapshot, reserved) async {
        buildCount++;
        return VoiceHintGenerator.generate(
          snapshot,
          reservedPhrases: reserved,
          excludedWords: snapshot.excludedWords,
        );
      },
    );

    await cache.prepare(snapshot: snapshot);
    await cache.prepare(
      snapshot: snapshot,
      reservedPhrases: const <String>{'молочная'},
    );

    expect(buildCount, 2);
  });

  test('screens use separate cache entries', () async {
    int buildCount = 0;
    final VoiceHintIndexCache cache = VoiceHintIndexCache(
      builder: (snapshot, reserved) async {
        buildCount++;
        return VoiceHintGenerator.generate(snapshot);
      },
    );

    await cache.prepare(snapshot: snapshot, screen: 'group');
    await cache.prepare(snapshot: snapshot, screen: 'product');

    expect(buildCount, 2);
  });

  test('excluded words use a separate cache entry', () async {
    int buildCount = 0;
    final VoiceHintIndexCache cache = VoiceHintIndexCache(
      builder: (snapshot, reserved) async {
        buildCount++;
        return VoiceHintGenerator.generate(snapshot);
      },
    );

    await cache.prepare(snapshot: snapshot);
    await cache.prepare(
        snapshot: _withExcluded(snapshot, <String>{'молочная'}));

    expect(buildCount, 2);
  });

  test('normalized equivalent exclusions share a cache entry', () async {
    int buildCount = 0;
    final VoiceHintIndexCache cache = VoiceHintIndexCache(
      builder: (snapshot, reserved) async {
        buildCount++;
        return VoiceHintGenerator.generate(
          snapshot,
          excludedWords: snapshot.excludedWords,
        );
      },
    );

    final VoiceHintSet first = await cache.prepare(
      snapshot: _withExcluded(snapshot, <String>{'МОЛОЧНАЯ'}),
    );
    final VoiceHintSet second = await cache.prepare(
      snapshot: _withExcluded(snapshot, <String>{'молочная'}),
    );

    expect(buildCount, 1);
    expect(second, same(first));
  });

  test('snapshot exclusions change generated hints', () async {
    final VoiceHintIndexCache cache = VoiceHintIndexCache();
    const VoiceDynamicItemsSnapshot original = VoiceDynamicItemsSnapshot(
      revision: 2,
      items: <VoiceDynamicItem>[
        VoiceDynamicItem(id: '1', label: 'Молочная продукция'),
      ],
    );

    final VoiceHintSet first = await cache.prepare(snapshot: original);
    final VoiceHintSet second = await cache.prepare(
      snapshot: _withExcluded(original, <String>{'молочная'}),
    );

    expect(first.hintsByItemId['1']?.phrase, 'молочная');
    expect(second.hintsByItemId['1']?.phrase, 'продукция');
  });

  test('failed generation can be retried', () async {
    int buildCount = 0;
    final VoiceHintIndexCache cache = VoiceHintIndexCache(
      builder: (snapshot, reserved) async {
        buildCount++;
        if (buildCount == 1) throw StateError('failed');
        return VoiceHintGenerator.generate(snapshot);
      },
    );

    await expectLater(cache.prepare(snapshot: snapshot), throwsStateError);
    await cache.prepare(snapshot: snapshot);

    expect(buildCount, 2);
    expect(cache.getIfReady(snapshot: snapshot), isNotNull);
  });
}

VoiceDynamicItemsSnapshot _withExcluded(
  VoiceDynamicItemsSnapshot snapshot,
  Set<String> excludedWords,
) {
  return VoiceDynamicItemsSnapshot(
    revision: snapshot.revision,
    items: snapshot.items,
    excludedWords: excludedWords,
  );
}
