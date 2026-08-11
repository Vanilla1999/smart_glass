import 'package:flutter_test/flutter_test.dart';
import 'package:smart_glasses/modules/wear/application/ports/wear_glasses_output.dart';
import 'package:smart_glasses/modules/wear/application/wear_flow_controller.dart';
import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/application/wear_ui_lifecycle.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/wear_voice_delay_event.dart';
import 'package:smart_glasses/modules/wear/infrastructure/noop_wear_navigation_output.dart';
import 'package:smart_glasses/modules/wear/presentation/glasses/wear_glasses_payload.dart';

void main() {
  test('voice status survives rerenders and restores the newest payload',
      () async {
    final _RecordingGlassesOutput glasses = _RecordingGlassesOutput();
    final WearFlowController flow = WearFlowController(
      glassesOutput: glasses,
      navigationOutput: NoopWearNavigationOutput(),
    );
    flow.setUiLifecycle(WearUiLifecycle.active);
    flow.enterScreen(WearScreenId.menu);
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

    await flow.dispose();
  });

  test('voice status is cleared when the logical screen changes', () async {
    final _RecordingGlassesOutput glasses = _RecordingGlassesOutput();
    final WearFlowController flow = WearFlowController(
      glassesOutput: glasses,
      navigationOutput: NoopWearNavigationOutput(),
    );
    flow.setUiLifecycle(WearUiLifecycle.active);
    flow.enterScreen(WearScreenId.menu);

    await flow.setRecognitionDelayVisible(
      WearScreenId.menu,
      true,
      null,
      kind: WearVoiceDelayKind.processing,
      statusText: 'Распознаю...',
    );
    expect(glasses.last.statusText, 'Распознаю...');

    flow.enterScreen(WearScreenId.help);
    await flow.renderCurrentGlasses();

    expect(glasses.last.statusText, isNull);
    await flow.dispose();
  });

  test('voice feedback preserves scan loading base payload', () async {
    final _RecordingGlassesOutput glasses = _RecordingGlassesOutput();
    final WearFlowController flow = WearFlowController(
      glassesOutput: glasses,
      navigationOutput: NoopWearNavigationOutput(),
    );
    flow.setUiLifecycle(WearUiLifecycle.active);
    flow.enterScreen(WearScreenId.scanIdle);
    await flow.publishScreenPayload(
      WearScreenId.scanIdle,
      WearGlassesPayload.scanLoading(),
    );

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
    expect(flow.basePayloadRevision, 1);

    await flow.dispose();
  });

  test('voice feedback preserves printing base payload', () async {
    final _RecordingGlassesOutput glasses = _RecordingGlassesOutput();
    final WearFlowController flow = WearFlowController(
      glassesOutput: glasses,
      navigationOutput: NoopWearNavigationOutput(),
    );
    flow.setUiLifecycle(WearUiLifecycle.active);
    flow.enterScreen(WearScreenId.scanIdle);
    await flow.publishScreenPayload(
      WearScreenId.scanIdle,
      WearGlassesPayload.printing(productName: 'Молоко'),
    );

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
    await flow.dispose();
  });

  test('transient payload restores canonical base without becoming state',
      () async {
    final _RecordingGlassesOutput glasses = _RecordingGlassesOutput();
    final WearFlowController flow = WearFlowController(
      glassesOutput: glasses,
      navigationOutput: NoopWearNavigationOutput(),
    );
    flow.setUiLifecycle(WearUiLifecycle.active);
    flow.enterScreen(WearScreenId.menu);
    flow.setMenuFocusedIndex(2);
    await flow.publishScreenPayload(
      WearScreenId.menu,
      WearGlassesPayload.menu(selectedIndex: 2),
    );
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
    await flow.dispose();
  });

  test('main and availability fill render their canonical payloads', () async {
    final _RecordingGlassesOutput glasses = _RecordingGlassesOutput();
    final WearFlowController flow = WearFlowController(
      glassesOutput: glasses,
      navigationOutput: NoopWearNavigationOutput(),
    );
    flow.setUiLifecycle(WearUiLifecycle.active);

    flow.enterScreen(WearScreenId.main);
    await flow.publishScreenPayload(
      WearScreenId.main,
      WearGlassesPayload.authLoading(),
    );
    expect(glasses.last.phase, WearGlassesPhase.loading);
    expect(glasses.last.statusText, 'Авторизуемся...');

    flow.enterScreen(WearScreenId.availabilityFill);
    await flow.publishScreenPayload(
      WearScreenId.availabilityFill,
      const WearGlassesPayload(
        screenType: WearGlassesScreenType.availability,
        phase: WearGlassesPhase.idle,
        title: 'Наполнение базы',
        statusText: 'Добавлено',
        bodyLines: <String>['Добавлено: 3'],
      ),
    );
    expect(glasses.last.statusText, 'Добавлено');
    expect(glasses.last.bodyLines, <String>['Добавлено: 3']);
    await flow.dispose();
  });

  test('production transient output is separate from canonical output',
      () async {
    final _SplitRecordingGlassesOutput glasses = _SplitRecordingGlassesOutput();
    final WearFlowController flow = WearFlowController(
      glassesOutput: glasses,
      navigationOutput: NoopWearNavigationOutput(),
    );
    flow.setUiLifecycle(WearUiLifecycle.active);
    flow.enterScreen(WearScreenId.menu);
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
    await flow.dispose();
  });
}

void _expectScanLoading(
  WearGlassesPayload payload, {
  required String statusText,
}) {
  expect(payload.screenType, WearGlassesScreenType.scan);
  expect(payload.phase, WearGlassesPhase.loading);
  expect(payload.isLoading, isTrue);
  expect(payload.title, 'Сканирование');
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
