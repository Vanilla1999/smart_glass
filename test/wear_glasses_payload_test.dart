import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/domain/availability/model/wear_availability_product.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/voice_action_catalog.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/voice_hint_generator.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/voice_hint_index_cache.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/voice_utterance_coordinator.dart';
import 'package:smart_glasses/modules/wear/presentation/glasses/wear_availability_glasses_payloads.dart';
import 'package:smart_glasses/modules/wear/presentation/glasses/wear_glasses_payload.dart';
import 'package:smart_glasses/modules/wear/presentation/glasses/wear_glasses_voice_hints.dart';

void main() {
  setUp(() {
    WearGlassesVoiceHints.configureVoiceHintIndexCache(VoiceHintIndexCache());
  });

  test('runtime command phrase cannot be advertised as a voice hint', () {
    WearGlassesVoiceHints.configureActionCatalog(VoiceActionCatalog(
      capabilities: VoiceScreenCapabilities(
        runtimeResolver: (WearScreenId screen, command) =>
            screen == WearScreenId.productSelect,
      ),
    ));
    addTearDown(
      () => WearGlassesVoiceHints.configureActionCatalog(VoiceActionCatalog()),
    );

    final hints = WearGlassesVoiceHints.forVisibleItems(
      screen: WearScreenId.productSelect,
      snapshot: const VoiceDynamicItemsSnapshot(
        revision: 1,
        items: <VoiceDynamicItem>[
          VoiceDynamicItem(id: 'cancel-item', label: 'Отмена'),
        ],
      ),
      visibleItemIds: const <String>['cancel-item'],
    );

    expect(hints.single.phrase, isEmpty);
  });

  test('auth waiting payload matches bridge contract', () {
    final Map<String, dynamic> json =
        WearGlassesPayload.authWaitingBarcode().toJson();

    expect(json['screenType'], 'auth');
    expect(json['phase'], 'scanning');
    expect(json['title'], 'Авторизация');
    expect(json['statusText'], 'Поиск ШК...');
    expect(json['isLoading'], isFalse);
    expect(json['isError'], isFalse);
    expect(json['items'], isEmpty);
  });

  test('menu payload contains wear menu items', () {
    final Map<String, dynamic> json = WearGlassesPayload.menu().toJson();

    expect(json['screenType'], 'menu');
    expect(json['phase'], 'idle');
    expect(
      json['items'],
      <String>[
        'Печать ценников',
        'Доступность',
        'Справка',
        'Настройки',
      ],
    );
    expect(json['selectedIndex'], 0);
  });

  test('performance trace survives bridge serialization', () {
    final Map<String, dynamic> json = WearGlassesPayload.menu()
        .copyWithPerformanceTrace(
          traceId: '7:3:1',
          command: 'up',
          recognizedAtMillis: 1000,
          asrMillis: 125,
          sentAtMillis: 1040,
        )
        .toJson();

    expect(json['performanceTraceId'], '7:3:1');
    expect(json['performanceCommand'], 'up');
    expect(json['performanceRecognizedAtMillis'], 1000);
    expect(json['performanceAsrMillis'], 125);
    expect(json['performanceSentAtMillis'], 1040);
  });

  test('structured voice hint survives bridge serialization', () {
    final Map<String, dynamic> json = const WearGlassesPayload(
      screenType: WearGlassesScreenType.printer,
      phase: WearGlassesPhase.idle,
      title: 'Принтеры',
      items: <String>['MOCK Белый 1'],
      voiceHints: <WearGlassesVoiceHint>[
        WearGlassesVoiceHint(
          itemId: 'printer-1',
          phrase: 'белый',
          start: 5,
          end: 10,
        ),
      ],
    ).toJson();

    expect(json['voiceHints'], <Map<String, dynamic>>[
      <String, dynamic>{
        'itemId': 'printer-1',
        'phrase': 'белый',
        'start': 5,
        'end': 10,
      },
    ]);
  });

  test('availability duplicate rows receive dynamic voice hints', () {
    const List<WearAvailabilityProduct> products = <WearAvailabilityProduct>[
      WearAvailabilityProduct(
        id: 1,
        groupId: 1,
        name: 'Молоко Альфа',
        code: '1',
        barcodes: <String>[],
        priceTagBarcodes: <String>[],
        price: 1,
        rest: 1,
        checkPrice: false,
        photoControl: false,
        unpackaged: false,
        priceTagActual: true,
      ),
      WearAvailabilityProduct(
        id: 2,
        groupId: 1,
        name: 'Молоко Бета',
        code: '2',
        barcodes: <String>[],
        priceTagBarcodes: <String>[],
        price: 1,
        rest: 1,
        checkPrice: false,
        photoControl: false,
        unpackaged: false,
        priceTagActual: true,
      ),
    ];
    final WearGlassesPayload payload =
        WearAvailabilityGlassesPayloads.duplicates(products);

    expect(payload.voiceHints.map((hint) => hint.itemId), <String>['1', '2']);
    expect(payload.voiceHints.map((hint) => hint.phrase),
        <String>['молоко', 'молоко']);
  });

  test('large list refreshes visible hints after async preparation', () async {
    final Completer<VoiceHintSet> build = Completer<VoiceHintSet>();
    final VoiceHintIndexCache cache = VoiceHintIndexCache(
      builder: (snapshot, reserved) => build.future,
    );
    WearGlassesVoiceHints.configureVoiceHintIndexCache(cache);
    final List<VoiceDynamicItem> items = <VoiceDynamicItem>[
      const VoiceDynamicItem(id: 'yellow', label: 'Жёлтый товар'),
      for (int index = 0; index < 32; index++)
        VoiceDynamicItem(id: 'item-$index', label: 'Позиция номер $index'),
    ];
    final VoiceDynamicItemsSnapshot snapshot = VoiceDynamicItemsSnapshot(
      revision: 33,
      items: items,
    );
    final Completer<void> prepared = Completer<void>();

    final List<WearGlassesVoiceHint> pending =
        WearGlassesVoiceHints.forVisibleItems(
      screen: WearScreenId.productSelect,
      snapshot: snapshot,
      visibleItemIds: const <String>['yellow'],
      onPrepared: prepared.complete,
    );
    expect(pending.single.phrase, isEmpty);

    final Future<VoiceHintSet> preparing = cache.prepare(
      snapshot: snapshot,
      screen: WearScreenId.productSelect.name,
      reservedPhrases:
          VoiceActionCatalog().phrasesFor(WearScreenId.productSelect),
    );
    build.complete(VoiceHintGenerator.generate(
      snapshot,
      reservedPhrases:
          VoiceActionCatalog().phrasesFor(WearScreenId.productSelect),
    ));
    await preparing;
    await prepared.future;

    final List<WearGlassesVoiceHint> ready =
        WearGlassesVoiceHints.forVisibleItems(
      screen: WearScreenId.productSelect,
      snapshot: snapshot,
      visibleItemIds: const <String>['yellow'],
    );
    expect(ready.single.phrase, isNotEmpty);
  });
}
