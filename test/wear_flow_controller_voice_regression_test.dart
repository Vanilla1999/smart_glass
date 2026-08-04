import 'package:flutter_test/flutter_test.dart';
import 'package:smart_glasses/modules/wear/application/ports/wear_glasses_output.dart';
import 'package:smart_glasses/modules/wear/application/ports/wear_navigation_output.dart';
import 'package:smart_glasses/modules/wear/application/voice_clarification_args.dart';
import 'package:smart_glasses/modules/wear/application/wear_flow_controller.dart';
import 'package:smart_glasses/modules/wear/application/wear_navigation_entry.dart';
import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/application/wear_ui_lifecycle.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/voice_utterance_coordinator.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/wear_voice_command.dart';
import 'package:smart_glasses/modules/wear/presentation/glasses/wear_glasses_payload.dart';

void main() {
  group('voice regression hardening', () {
    test('stopword-only phrase does not open clarification', () async {
      final WearFlowController controller = _controller();
      controller.setUiLifecycle(WearUiLifecycle.active);
      controller.enterScreen(WearScreenId.availabilityProduct);
      controller.registerScreenActions(
        WearScreenId.availabilityProduct,
        WearScreenActionHandler(
          dynamicVoiceItems: () => const VoiceDynamicItemsSnapshot(
            revision: 1,
            items: <VoiceDynamicItem>[
              VoiceDynamicItem(id: '1', label: 'Молоко и сливки'),
              VoiceDynamicItem(id: '2', label: 'Йогурт и фрукты'),
            ],
          ),
        ),
      );

      await controller.handleVoicePhrase('и');

      expect(controller.state.screen, WearScreenId.availabilityProduct);
      expect(controller.state.pendingNavigation, isNull);
    });

    test('inactive clarification owns down and page navigation', () async {
      final WearFlowController controller = _controller();
      final VoiceClarificationArgs args = _clarificationArgs();
      controller.setUiLifecycle(WearUiLifecycle.inactive);
      controller.enterScreen(WearScreenId.voiceClarification, extra: args);

      expect(
        controller.canHandleVoiceCommand(
          WearScreenId.voiceClarification,
          WearVoiceCommand.down,
        ),
        isTrue,
      );

      await controller.handleVoiceCommand(WearVoiceCommand.down);
      expect(controller.state.voiceClarificationFocusedIndex, 1);

      await controller.handleVoiceCommand(WearVoiceCommand.nextPage);
      expect(controller.state.voiceClarificationFocusedIndex, 4);

      await controller.handleVoiceCommand(WearVoiceCommand.previousPage);
      expect(controller.state.voiceClarificationFocusedIndex, 0);
    });

    test('active pending clarification handles down before widget mounts',
        () async {
      final WearFlowController controller = _controller();
      final VoiceClarificationArgs args = _clarificationArgs();
      controller.setUiLifecycle(WearUiLifecycle.active);
      controller.enterScreen(WearScreenId.voiceClarification, extra: args);

      await controller.handleVoiceCommand(WearVoiceCommand.down);

      expect(controller.state.voiceClarificationFocusedIndex, 1);
      expect(controller.state.focusedIndex, 1);
    });

    test('mounting the same clarification preserves background focus', () async {
      final WearFlowController controller = _controller();
      final VoiceClarificationArgs args = _clarificationArgs();
      controller.setUiLifecycle(WearUiLifecycle.inactive);
      controller.enterScreen(WearScreenId.voiceClarification, extra: args);
      await controller.handleVoiceCommand(WearVoiceCommand.down);
      await controller.handleVoiceCommand(WearVoiceCommand.down);

      controller.enterScreen(WearScreenId.voiceClarification, extra: args);

      expect(controller.state.voiceClarificationFocusedIndex, 2);
      expect(controller.state.focusedIndex, 2);
    });

    test('home and yes confirm while UI is inactive', () async {
      for (final WearVoiceCommand command in <WearVoiceCommand>[
        WearVoiceCommand.home,
        WearVoiceCommand.yes,
      ]) {
        final _FakeNavigationOutput navigation = _FakeNavigationOutput();
        final WearFlowController controller = _controller(navigation);
        controller.setUiLifecycle(WearUiLifecycle.inactive);
        controller.enterScreen(WearScreenId.printerSelect);
        await controller.handleVoiceCommand(WearVoiceCommand.home);

        await controller.handleVoiceCommand(command);

        expect(controller.state.screen, WearScreenId.menu, reason: '$command');
        expect(
          controller.state.pendingNavigation?.replaceCurrent,
          isTrue,
          reason: '$command',
        );
      }
    });

    test('cancel and no restore the previous screen while UI is inactive',
        () async {
      for (final WearVoiceCommand command in <WearVoiceCommand>[
        WearVoiceCommand.cancel,
        WearVoiceCommand.no,
      ]) {
        final WearFlowController controller = _controller();
        controller.setUiLifecycle(WearUiLifecycle.inactive);
        controller.enterScreen(WearScreenId.printerSelect, extra: 'printer');
        await controller.handleVoiceCommand(WearVoiceCommand.home);

        await controller.handleVoiceCommand(command);

        expect(
          controller.state.screen,
          WearScreenId.printerSelect,
          reason: '$command',
        );
        expect(
          controller.state.pendingNavigation?.popCurrent,
          isTrue,
          reason: '$command',
        );
        expect(controller.state.navigationHistory.last.extra, 'printer');
      }
    });
  });
}

VoiceClarificationArgs _clarificationArgs() {
  return const VoiceClarificationArgs(
    sourceScreen: WearScreenId.availabilityProduct,
    phrase: 'чудо',
    matches: <VoiceDynamicItem>[
      VoiceDynamicItem(id: '0', label: 'Чудо ноль'),
      VoiceDynamicItem(id: '1', label: 'Чудо один'),
      VoiceDynamicItem(id: '2', label: 'Чудо два'),
      VoiceDynamicItem(id: '3', label: 'Чудо три'),
      VoiceDynamicItem(id: '4', label: 'Чудо четыре'),
      VoiceDynamicItem(id: '5', label: 'Чудо пять'),
    ],
    sourceListRevision: 1,
  );
}

WearFlowController _controller([_FakeNavigationOutput? navigation]) {
  return WearFlowController(
    glassesOutput: _FakeGlassesOutput(),
    navigationOutput: navigation ?? _FakeNavigationOutput(),
  );
}

class _FakeGlassesOutput implements WearGlassesOutput {
  @override
  Future<void> send(WearGlassesPayload payload) async {}
}

class _FakeNavigationOutput implements WearNavigationOutput {
  @override
  Future<void> back() async {}

  @override
  Future<void> goTo(WearScreenId screen, {Object? extra}) async {}

  @override
  Future<void> home() async {}

  @override
  Future<void> replace(WearScreenId screen, {Object? extra}) async {}

  @override
  Future<void> synchronize(List<WearNavigationEntry> history) async {}
}
