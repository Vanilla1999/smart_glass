import 'package:flutter_test/flutter_test.dart';
import 'package:smart_glasses/modules/wear/application/ports/wear_glasses_output.dart';
import 'package:smart_glasses/modules/wear/application/ports/wear_navigation_output.dart';
import 'package:smart_glasses/modules/wear/application/wear_flow_controller.dart';
import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/application/wear_ui_lifecycle.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/wear_voice_command.dart';
import 'package:smart_glasses/modules/wear/presentation/glasses/wear_glasses_payload.dart';

void main() {
  group('WearFlowController', () {
    test('stores pending navigation while UI is inactive', () async {
      final _FakeNavigationOutput navigation = _FakeNavigationOutput();
      final WearFlowController controller = WearFlowController(
        glassesOutput: _FakeGlassesOutput(),
        navigationOutput: navigation,
      );

      controller.setUiLifecycle(WearUiLifecycle.inactive);
      controller.enterScreen(WearScreenId.menu);
      controller.setMenuFocusedIndex(1);

      await controller.handleVoiceCommand(WearVoiceCommand.select);

      expect(navigation.goToCalls, isEmpty);
      expect(
        controller.state.pendingNavigation?.screen,
        WearScreenId.availabilityInteraction,
      );
    });

    test('flushes pending navigation once when UI becomes active', () async {
      final _FakeNavigationOutput navigation = _FakeNavigationOutput();
      final WearFlowController controller = WearFlowController(
        glassesOutput: _FakeGlassesOutput(),
        navigationOutput: navigation,
      );

      controller.setUiLifecycle(WearUiLifecycle.inactive);
      controller.enterScreen(WearScreenId.menu);
      controller.setMenuFocusedIndex(2);
      await controller.handleVoiceCommand(WearVoiceCommand.select);

      controller.setUiLifecycle(WearUiLifecycle.active);
      await Future<void>.delayed(Duration.zero);
      await controller.flushPendingNavigation();

      expect(navigation.goToCalls, <WearScreenId>[WearScreenId.help]);
      expect(controller.state.pendingNavigation, isNull);
    });

    test('handles availability interaction focus without widget callbacks',
        () async {
      final _FakeNavigationOutput navigation = _FakeNavigationOutput();
      final WearFlowController controller = WearFlowController(
        glassesOutput: _FakeGlassesOutput(),
        navigationOutput: navigation,
      );

      controller.setUiLifecycle(WearUiLifecycle.inactive);
      controller.enterScreen(WearScreenId.availabilityInteraction);
      await controller.handleVoiceCommand(WearVoiceCommand.down);
      await controller.handleVoiceCommand(WearVoiceCommand.select);

      expect(controller.state.availabilityInteractionFocusedIndex, 1);
      expect(navigation.goToCalls, isEmpty);
      expect(
        controller.state.pendingNavigation?.screen,
        WearScreenId.availabilityDirectScan,
      );
    });

    test('unregistering current screen does not switch to another handler',
        () async {
      final WearFlowController controller = WearFlowController(
        glassesOutput: _FakeGlassesOutput(),
        navigationOutput: _FakeNavigationOutput(),
      );

      controller.enterScreen(WearScreenId.printerSelect);
      controller.registerScreenActions(
        WearScreenId.printerSelect,
        const WearScreenActionHandler(),
      );
      controller.registerScreenActions(
        WearScreenId.settings,
        const WearScreenActionHandler(),
      );

      controller.unregisterScreenActions(WearScreenId.printerSelect);

      expect(controller.state.screen, WearScreenId.printerSelect);
    });

    test('does not route commands to another screen handler', () async {
      int wrongHandlerCalls = 0;
      final WearFlowController controller = WearFlowController(
        glassesOutput: _FakeGlassesOutput(),
        navigationOutput: _FakeNavigationOutput(),
      );

      controller.setUiLifecycle(WearUiLifecycle.active);
      controller.enterScreen(WearScreenId.printerSelect);
      controller.registerScreenActions(
        WearScreenId.settings,
        WearScreenActionHandler(
          onUp: () {
            wrongHandlerCalls++;
          },
        ),
      );

      await controller.handleVoiceCommand(WearVoiceCommand.up);

      expect(wrongHandlerCalls, 0);
      expect(controller.state.screen, WearScreenId.printerSelect);
    });
  });
}

class _FakeGlassesOutput implements WearGlassesOutput {
  final List<WearGlassesPayload> payloads = <WearGlassesPayload>[];

  @override
  Future<void> send(WearGlassesPayload payload) async {
    payloads.add(payload);
  }
}

class _FakeNavigationOutput implements WearNavigationOutput {
  final List<WearScreenId> goToCalls = <WearScreenId>[];
  int backCalls = 0;
  int homeCalls = 0;

  @override
  Future<void> goTo(WearScreenId screen, {Object? extra}) async {
    goToCalls.add(screen);
  }

  @override
  Future<void> back() async {
    backCalls++;
  }

  @override
  Future<void> home() async {
    homeCalls++;
  }
}
