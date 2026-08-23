import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_glasses/modules/wear/application/ports/wear_glasses_output.dart';
import 'package:smart_glasses/modules/wear/application/wear_flow_controller.dart';
import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/wear_voice_delay_event.dart';
import 'package:smart_glasses/modules/wear/domain/price_tag_print/model/barcode_product_info.dart';
import 'package:smart_glasses/modules/wear/infrastructure/noop_wear_navigation_output.dart';
import 'package:smart_glasses/modules/wear/models/wear_printer.dart';
import 'package:smart_glasses/modules/wear/models/wear_printer_selection.dart';
import 'package:smart_glasses/modules/wear/presentation/glasses/wear_glasses_payload.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_authority.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_scan_effects.dart';

import 'support/wear_runtime_test_helper.dart';

void main() {
  test('voice status survives rerenders and restores the newest payload',
      () async {
    final _RecordingGlassesOutput glasses = _RecordingGlassesOutput();
    final WearRuntimeAuthority authority =
        await createActiveWearRuntimeAuthority();
    final WearFlowController flow = createWearFlowController(
      authority: authority,
      glassesOutput: glasses,
      navigationOutput: NoopWearNavigationOutput(),
    );
    addTearDown(() async {
      await flow.dispose();
      await authority.dispose();
    });
    await flow.requestNavigation(WearScreenId.menu);
    await flow.renderCurrentGlasses();

    await flow.setRecognitionDelayVisible(
      WearScreenId.menu,
      true,
      null,
      kind: WearVoiceDelayKind.processing,
      statusText: 'Распознаю...',
    );
    flow.setMenuFocusedIndex(2);
    await flow.renderCurrentGlasses();

    expect(glasses.last.selectedIndex, 2);
    expect(glasses.last.statusText, 'Распознаю...');

    await flow.setRecognitionDelayVisible(
      WearScreenId.menu,
      true,
      'Доступность',
      kind: WearVoiceDelayKind.preview,
    );
    expect(glasses.last.statusText, 'Распознаю...');

    await flow.setRecognitionDelayVisible(
      WearScreenId.menu,
      false,
      null,
      kind: WearVoiceDelayKind.processing,
    );
    expect(glasses.last.selectedIndex, 2);
    expect(glasses.last.statusText, 'Похоже: Доступность');

    await flow.setRecognitionDelayVisible(
      WearScreenId.menu,
      false,
      null,
      kind: WearVoiceDelayKind.preview,
    );
    expect(glasses.last.selectedIndex, 2);
    expect(glasses.last.statusText, isNull);
  });

  test('voice status is cleared when the logical screen changes', () async {
    final _RecordingGlassesOutput glasses = _RecordingGlassesOutput();
    final WearRuntimeAuthority authority =
        await createActiveWearRuntimeAuthority();
    final WearFlowController flow = createWearFlowController(
      authority: authority,
      glassesOutput: glasses,
      navigationOutput: NoopWearNavigationOutput(),
    );
    addTearDown(() async {
      await flow.dispose();
      await authority.dispose();
    });
    await flow.requestNavigation(WearScreenId.menu);

    await flow.setRecognitionDelayVisible(
      WearScreenId.menu,
      true,
      null,
      kind: WearVoiceDelayKind.processing,
      statusText: 'Распознаю...',
    );
    expect(glasses.last.statusText, 'Распознаю...');

    await flow.requestNavigation(WearScreenId.help);
    await flow.renderCurrentGlasses();

    expect(glasses.last.statusText, isNull);
  });

  test('voice feedback preserves scan loading base payload', () async {
    final _RecordingGlassesOutput glasses = _RecordingGlassesOutput();
    final WearRuntimeAuthority authority =
        await createActiveWearRuntimeAuthority();
    final WearFlowController flow = createWearFlowController(
      authority: authority,
      glassesOutput: glasses,
      navigationOutput: NoopWearNavigationOutput(),
    );
    addTearDown(() async {
      await flow.dispose();
      await authority.dispose();
    });
    await authority.importPrinterSelection(
      const WearPrinterSelection(
        whitePrinter: WearPrinter(id: 'white', name: 'White'),
        yellowPrinter: WearPrinter(id: 'yellow', name: 'Yellow'),
      ),
    );
    final Completer<List<BarcodeProductInfo>> lookup =
        Completer<List<BarcodeProductInfo>>();
    authority.registerEffectExecutor(
      WearScanEffectExecutor(
        lookup: (_) => lookup.future,
        print: (_, __) async => 'unused',
        navigate: (_, {extra, replaceCurrent = false}) async {},
        presentStatus: (_, {required completion}) async {},
        delay: (_) async {},
      ),
    );
    await flow.requestNavigation(WearScreenId.scanIdle);
    await authority.enterScanScreen(WearScreenId.scanIdle);
    await authority.submitScanBarcode('4600000000001');
    await _flushEffects();
    await flow.renderCurrentGlasses();

    await flow.setRecognitionDelayVisible(
      WearScreenId.scanIdle,
      true,
      null,
      kind: WearVoiceDelayKind.processing,
      statusText: 'Распознаю...',
    );
    _expectScanLoading(glasses.last, statusText: 'Распознаю...');

    await flow.setRecognitionDelayVisible(
      WearScreenId.scanIdle,
      true,
      null,
      kind: WearVoiceDelayKind.processing,
      statusText: 'Не распознано',
    );
    _expectScanLoading(glasses.last, statusText: 'Не распознано');

    await flow.setRecognitionDelayVisible(
      WearScreenId.scanIdle,
      false,
      null,
      kind: WearVoiceDelayKind.processing,
    );
    _expectScanLoading(
      glasses.last,
      statusText: 'ШК отсканирован, распознаю...',
    );
    expect(authority.scanTask.phase, WearScanTaskPhase.lookingUp);
    lookup.complete(const <BarcodeProductInfo>[]);
  });

  test('voice feedback preserves printing base payload', () async {
    final _RecordingGlassesOutput glasses = _RecordingGlassesOutput();
    final WearRuntimeAuthority authority =
        await createActiveWearRuntimeAuthority();
    final WearFlowController flow = createWearFlowController(
      authority: authority,
      glassesOutput: glasses,
      navigationOutput: NoopWearNavigationOutput(),
    );
    addTearDown(() async {
      await flow.dispose();
      await authority.dispose();
    });
    await authority.importPrinterSelection(
      const WearPrinterSelection(
        whitePrinter: WearPrinter(id: 'white', name: 'White'),
        yellowPrinter: WearPrinter(id: 'yellow', name: 'Yellow'),
      ),
    );
    final Completer<String> print = Completer<String>();
    authority.registerEffectExecutor(
      WearScanEffectExecutor(
        lookup: (_) async => <BarcodeProductInfo>[
          BarcodeProductInfo(id: 1, name: 'Молоко'),
        ],
        print: (_, __) => print.future,
        navigate: (_, {extra, replaceCurrent = false}) async {},
        presentStatus: (_, {required completion}) async {},
        delay: (_) async {},
      ),
    );
    await flow.requestNavigation(WearScreenId.scanIdle);
    await authority.enterScanScreen(WearScreenId.scanIdle);
    await authority.submitScanBarcode('4600000000002');
    await _flushEffects();

    await flow.setRecognitionDelayVisible(
      WearScreenId.scanIdle,
      true,
      null,
      kind: WearVoiceDelayKind.processing,
      statusText: 'Распознаю...',
    );

    expect(glasses.last.screenType, WearGlassesScreenType.printing);
    expect(glasses.last.phase, WearGlassesPhase.loading);
    expect(glasses.last.isLoading, isTrue);
    expect(glasses.last.title, 'Печать ценника');
    expect(glasses.last.statusText, 'Распознаю...');
    print.complete('Молоко');
  });

  test('transient payload restores canonical base without becoming state',
      () async {
    final _RecordingGlassesOutput glasses = _RecordingGlassesOutput();
    final WearRuntimeAuthority authority =
        await createActiveWearRuntimeAuthority();
    final WearFlowController flow = createWearFlowController(
      authority: authority,
      glassesOutput: glasses,
      navigationOutput: NoopWearNavigationOutput(),
    );
    addTearDown(() async {
      await flow.dispose();
      await authority.dispose();
    });
    await flow.requestNavigation(WearScreenId.menu);
    flow.setMenuFocusedIndex(2);
    await flow.renderCurrentGlasses();
    final int revision = flow.basePayloadRevision;

    await flow.publishTransientStatusText(
      WearScreenId.menu,
      'Ничего не найдено',
      duration: const Duration(milliseconds: 10),
    );
    expect(glasses.last.statusText, 'Ничего не найдено');
    expect(flow.basePayloadRevision, revision);

    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(glasses.last.statusText, isNull);
    expect(glasses.last.selectedIndex, 2);
  });

  test('main and availability fill render aggregate projections', () async {
    final _RecordingGlassesOutput glasses = _RecordingGlassesOutput();
    final WearRuntimeAuthority authority =
        await createActiveWearRuntimeAuthority();
    final WearFlowController flow = createWearFlowController(
      authority: authority,
      glassesOutput: glasses,
      navigationOutput: NoopWearNavigationOutput(),
    );
    addTearDown(() async {
      await flow.dispose();
      await authority.dispose();
    });

    await flow.requestNavigation(WearScreenId.main);
    await flow.renderCurrentGlasses();
    expect(glasses.last.phase, WearGlassesPhase.scanning);
    expect(glasses.last.statusText, 'Поиск ШК...');

    await authority.enterAvailabilityScreen(WearScreenId.availabilityFill);
    await flow.requestNavigation(WearScreenId.availabilityFill);
    await flow.renderCurrentGlasses();
    expect(glasses.last.statusText, 'Сканируйте товары с полки');
    expect(glasses.last.bodyLines, <String>['Добавлено: 0']);
  });

  test('production transient output is separate from canonical output',
      () async {
    final _SplitRecordingGlassesOutput glasses = _SplitRecordingGlassesOutput();
    final WearRuntimeAuthority authority =
        await createActiveWearRuntimeAuthority();
    final WearFlowController flow = createWearFlowController(
      authority: authority,
      glassesOutput: glasses,
      navigationOutput: NoopWearNavigationOutput(),
    );
    addTearDown(() async {
      await flow.dispose();
      await authority.dispose();
    });
    await flow.requestNavigation(WearScreenId.menu);
    await flow.renderCurrentGlasses();
    final int canonicalCount = glasses.canonical.length;

    await flow.publishTransientStatusText(
      WearScreenId.menu,
      'Ничего не найдено',
      duration: const Duration(milliseconds: 10),
    );

    expect(glasses.canonical, hasLength(canonicalCount));
    expect(glasses.transient.single.statusText, 'Ничего не найдено');
    await flow.renderCurrentGlasses();
    expect(glasses.canonical, hasLength(canonicalCount));
    expect(glasses.transient, hasLength(2));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(glasses.canonical.last.statusText, isNull);
  });
}

Future<void> _flushEffects() async {
  for (int index = 0; index < 4; index++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void _expectScanLoading(
  WearGlassesPayload payload, {
  required String statusText,
}) {
  expect(payload.screenType, WearGlassesScreenType.scan);
  expect(payload.phase, WearGlassesPhase.loading);
  expect(payload.isLoading, isTrue);
  expect(payload.title, 'Сканирование товара');
  expect(payload.statusText, statusText);
}

class _RecordingGlassesOutput implements WearGlassesOutput {
  final List<WearGlassesPayload> payloads = <WearGlassesPayload>[];

  WearGlassesPayload get last => payloads.last;

  @override
  Future<void> send(WearGlassesPayload payload) async {
    payloads.add(payload);
  }
}

class _SplitRecordingGlassesOutput
    implements WearGlassesOutput, WearTransientGlassesOutput {
  final List<WearGlassesPayload> canonical = <WearGlassesPayload>[];
  final List<WearGlassesPayload> transient = <WearGlassesPayload>[];

  @override
  Future<void> send(WearGlassesPayload payload) async {
    canonical.add(payload);
  }

  @override
  Future<void> sendTransient(WearGlassesPayload payload) async {
    transient.add(payload);
  }
}
