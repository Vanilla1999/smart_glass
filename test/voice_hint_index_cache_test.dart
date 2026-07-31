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
    expect(prepared.itemIdByPhrase['молочная'], '1');
    expect(prepared.itemIdByPhrase['напитки'], '2');
  });

  test('concurrent prepare calls share one generation', () async {
    final Completer<VoiceHintSet> completer = Completer<VoiceHintSet>();
    int buildCount = 0;
    final VoiceHintIndexCache cache = VoiceHintIndexCache(
      builder: (snapshot, reserved, excluded) {
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

  test('reserved phrases use a separate cache entry', () async {
    int buildCount = 0;
    final VoiceHintIndexCache cache = VoiceHintIndexCache(
      builder: (snapshot, reserved, excluded) async {
        buildCount++;
        return VoiceHintGenerator.generate(
          snapshot,
          reservedPhrases: reserved,
          excludedWords: excluded,
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
      builder: (snapshot, reserved, excluded) async {
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
      builder: (snapshot, reserved, excluded) async {
        buildCount++;
        return VoiceHintGenerator.generate(snapshot);
      },
    );

    await cache.prepare(snapshot: snapshot);
    await cache.prepare(
      snapshot: snapshot,
      excludedWords: const <String>{'молочная'},
    );

    expect(buildCount, 2);
  });

  test('failed generation can be retried', () async {
    int buildCount = 0;
    final VoiceHintIndexCache cache = VoiceHintIndexCache(
      builder: (snapshot, reserved, excluded) async {
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
