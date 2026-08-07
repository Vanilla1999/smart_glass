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
}

class _RecordingGlassesOutput implements WearGlassesOutput {
  final List<WearGlassesPayload> payloads = <WearGlassesPayload>[];

  WearGlassesPayload get last => payloads.last;

  @override
  Future<void> send(WearGlassesPayload payload) async {
    payloads.add(payload);
  }
}
