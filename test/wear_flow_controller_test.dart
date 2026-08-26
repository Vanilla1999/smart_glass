import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_glasses/modules/wear/application/ports/wear_glasses_output.dart';
import 'package:smart_glasses/modules/wear/application/ports/wear_navigation_output.dart';
import 'package:smart_glasses/modules/wear/application/wear_flow_controller.dart';
import 'package:smart_glasses/modules/wear/application/wear_flow_state.dart';
import 'package:smart_glasses/modules/wear/application/wear_navigation_entry.dart';
import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/application/voice_clarification_args.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/voice_utterance_coordinator.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/wear_voice_command.dart';
import 'package:smart_glasses/modules/wear/presentation/glasses/wear_glasses_payload.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_authority.dart';

import 'support/wear_runtime_test_helper.dart';

void main() {
  group('WearFlowController', () {
    late WearRuntimeAuthority authority;
    final List<WearFlowController> flows = <WearFlowController>[];

    setUp(() async {
      authority = await createActiveWearRuntimeAuthority();
      flows.clear();
    });

    tearDown(() async {
      for (final WearFlowController flow in flows) {
        await flow.dispose();
      }
    });

    WearFlowController createFlow({
      required WearGlassesOutput glassesOutput,
      required WearNavigationOutput navigationOutput,
      WearFlashlightToggle? flashlightToggle,
      WearPhotoCapture? photoCapture,
    }) {
      final WearFlowController flow = WearFlowController(
        authority: authority,
        glassesOutput: glassesOutput,
        navigationOutput: navigationOutput,
        flashlightToggle: flashlightToggle,
        photoCapture: photoCapture,
      );
      flows.add(flow);
      return flow;
    }

    test('adopts and delivers an existing matching navigation request once',
        () async {
      final _FakeNavigationOutput navigation = _FakeNavigationOutput();
      final WearFlowController controller = createFlow(
        glassesOutput: _FakeGlassesOutput(),
        navigationOutput: navigation,
      );
      await authority.requestNavigation(WearScreenId.help);
      final int requestId = authority.payload.navigation.pending!.requestId;

      await controller.requestNavigation(WearScreenId.help);

      expect(controller.state.pendingNavigation?.requestId, requestId);
      expect(navigation.goToCalls, <WearScreenId>[WearScreenId.help]);
    });

    test('accepts current logical target without a pending request', () async {
      final _FakeNavigationOutput navigation = _FakeNavigationOutput();
      await authority.requestNavigation(WearScreenId.help);
      final pending = authority.payload.navigation.pending!;
      await authority.acknowledgeNavigationAtEpoch(
        sessionEpoch: authority.state.sessionEpoch,
        requestId: pending.requestId,
        screen: pending.screen,
      );
      final WearFlowController controller = createFlow(
        glassesOutput: _FakeGlassesOutput(),
        navigationOutput: navigation,
      );

      await expectLater(
        controller.requestNavigation(WearScreenId.help),
        completes,
      );

      expect(authority.payload.navigation.pending, isNull);
      expect(navigation.goToCalls, isEmpty);
    });

    test('stores pending navigation while UI is inactive', () async {
      final _FakeNavigationOutput navigation = _FakeNavigationOutput();
      final WearFlowController controller = createFlow(
        glassesOutput: _FakeGlassesOutput(),
        navigationOutput: navigation,
      );

      await authority.setPhoneUiActive(false);
      await controller.requestNavigation(WearScreenId.menu);
      controller.setMenuFocusedIndex(1);

      await controller.handleVoiceCommand(WearVoiceCommand.select);

      expect(navigation.goToCalls, isEmpty);
      expect(
        controller.state.pendingNavigation?.screen,
        WearScreenId.availabilityInteraction,
      );
    });

    test('does not deliver a request again before its route acknowledgement',
        () async {
      final _FakeNavigationOutput navigation = _FakeNavigationOutput();
      final WearFlowController controller = createFlow(
        glassesOutput: _FakeGlassesOutput(),
        navigationOutput: navigation,
      );

      await authority.setPhoneUiActive(false);
      await controller.requestNavigation(WearScreenId.help);

      await authority.setPhoneUiActive(true);
      await Future<void>.delayed(Duration.zero);
      await controller.flushPendingNavigation();

      expect(navigation.goToCalls, <WearScreenId>[WearScreenId.help]);
      final int requestId = controller.state.pendingNavigation!.requestId;
      expect(
        controller.acknowledgeNavigation(
          requestId: requestId,
          screen: WearScreenId.menu,
        ),
        isFalse,
      );
      expect(controller.state.pendingNavigation, isNotNull);
    });

    test('acknowledges only the latest pending navigation request', () async {
      final WearFlowController controller = createFlow(
        glassesOutput: _FakeGlassesOutput(),
        navigationOutput: _FakeNavigationOutput(),
      );

      await authority.setPhoneUiActive(false);
      await controller.requestNavigation(WearScreenId.help);
      final int firstRequestId = controller.state.pendingNavigation!.requestId;
      await controller.requestNavigation(WearScreenId.settings);
      final int secondRequestId = controller.state.pendingNavigation!.requestId;

      expect(secondRequestId, greaterThan(firstRequestId));
      expect(
        controller.acknowledgeNavigation(
          requestId: firstRequestId,
          screen: WearScreenId.help,
        ),
        isFalse,
      );
      expect(
        controller.acknowledgeNavigation(
          requestId: secondRequestId,
          screen: WearScreenId.settings,
        ),
        isTrue,
      );
    });

    test('handles availability interaction focus without widget callbacks',
        () async {
      final _FakeNavigationOutput navigation = _FakeNavigationOutput();
      final WearFlowController controller = createFlow(
        glassesOutput: _FakeGlassesOutput(),
        navigationOutput: navigation,
      );

      await authority.setPhoneUiActive(false);
      await controller.requestNavigation(WearScreenId.availabilityInteraction);
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
      final WearFlowController controller = createFlow(
        glassesOutput: _FakeGlassesOutput(),
        navigationOutput: _FakeNavigationOutput(),
      );

      await controller.requestNavigation(WearScreenId.printerSelect);
      final WearScreenActionRegistration registration =
          controller.registerScreenActions(
        WearScreenId.printerSelect,
        const WearScreenActionHandler(),
      );
      controller.registerScreenActions(
        WearScreenId.settings,
        const WearScreenActionHandler(),
      );

      controller.unregisterScreenActions(registration);

      expect(controller.state.screen, WearScreenId.printerSelect);
    });

    test('stale screen disposal keeps the newer handler registered', () async {
      final WearFlowController controller = createFlow(
        glassesOutput: _FakeGlassesOutput(),
        navigationOutput: _FakeNavigationOutput(),
      );
      final List<WearScreenId> changed = <WearScreenId>[];
      final StreamSubscription<WearScreenId> subscription =
          controller.screenActionsChanged.listen(changed.add);
      addTearDown(subscription.cancel);
      int firstCalls = 0;
      int secondCalls = 0;
      await authority.setPhoneUiActive(true);
      await controller.requestNavigation(WearScreenId.availabilityCheck);
      final WearScreenActionRegistration first =
          controller.registerScreenActions(
        WearScreenId.availabilityCheck,
        WearScreenActionHandler(onManualInput: () => firstCalls++),
      );
      final WearScreenActionRegistration second =
          controller.registerScreenActions(
        WearScreenId.availabilityCheck,
        WearScreenActionHandler(onManualInput: () => secondCalls++),
      );

      controller.unregisterScreenActions(first);
      await controller.handleVoiceCommand(WearVoiceCommand.manualInput);
      await Future<void>.delayed(Duration.zero);

      expect(firstCalls, 0);
      expect(secondCalls, 1);
      expect(
        controller.canHandleVoiceCommand(
          WearScreenId.availabilityCheck,
          WearVoiceCommand.manualInput,
        ),
        isTrue,
      );
      expect(
        changed,
        <WearScreenId>[
          WearScreenId.availabilityCheck,
          WearScreenId.availabilityCheck,
        ],
      );

      controller.unregisterScreenActions(second);
      await Future<void>.delayed(Duration.zero);

      expect(
        controller.canHandleVoiceCommand(
          WearScreenId.availabilityCheck,
          WearVoiceCommand.manualInput,
        ),
        isFalse,
      );
      expect(changed, hasLength(3));
    });

    test('closing the newer screen restores the older live handler', () async {
      final WearFlowController controller = createFlow(
        glassesOutput: _FakeGlassesOutput(),
        navigationOutput: _FakeNavigationOutput(),
      );
      int firstCalls = 0;
      int secondCalls = 0;
      await authority.setPhoneUiActive(true);
      await controller.requestNavigation(WearScreenId.availabilityCheck);
      final WearScreenActionRegistration first =
          controller.registerScreenActions(
        WearScreenId.availabilityCheck,
        WearScreenActionHandler(onManualInput: () => firstCalls++),
      );
      final WearScreenActionRegistration second =
          controller.registerScreenActions(
        WearScreenId.availabilityCheck,
        WearScreenActionHandler(onManualInput: () => secondCalls++),
      );

      controller.unregisterScreenActions(second);
      await controller.handleVoiceCommand(WearVoiceCommand.manualInput);

      expect(firstCalls, 1);
      expect(secondCalls, 0);

      controller.unregisterScreenActions(first);
    });

    test('does not route commands to another screen handler', () async {
      int wrongHandlerCalls = 0;
      final WearFlowController controller = createFlow(
        glassesOutput: _FakeGlassesOutput(),
        navigationOutput: _FakeNavigationOutput(),
      );

      await authority.setPhoneUiActive(true);
      await controller.requestNavigation(WearScreenId.printerSelect);
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

    test(
        'controller commands do not invoke widget handlers while UI is inactive',
        () async {
      int upCalls = 0;
      int selectCalls = 0;
      final WearFlowController controller = createFlow(
        glassesOutput: _FakeGlassesOutput(),
        navigationOutput: _FakeNavigationOutput(),
      );
      await authority.setPhoneUiActive(false);
      await controller.requestNavigation(WearScreenId.printerSelect);
      controller.registerScreenActions(
        WearScreenId.printerSelect,
        WearScreenActionHandler(
          onUp: () => upCalls++,
          onSelect: () async => selectCalls++,
        ),
      );

      await controller.handleControllerCommand(WearVoiceCommand.up);
      await controller.handleControllerCommand(WearVoiceCommand.select);

      expect(upCalls, 0);
      expect(selectCalls, 0);
    });

    test('runtime stop blocks commands independently from UI lifecycle',
        () async {
      final WearFlowController controller = createFlow(
        glassesOutput: _FakeGlassesOutput(),
        navigationOutput: _FakeNavigationOutput(),
      );
      await authority.setPhoneUiActive(true);
      await controller.requestNavigation(WearScreenId.menu);
      await authority.setRuntimeActive(false);

      await controller.handleVoiceCommand(WearVoiceCommand.down);
      await controller.handleControllerCommand(WearVoiceCommand.down);

      expect(controller.state.menuFocusedIndex, 0);
    });

    test('voice commands remain blocked while UI is inactive', () async {
      int upCalls = 0;
      final WearFlowController controller = createFlow(
        glassesOutput: _FakeGlassesOutput(),
        navigationOutput: _FakeNavigationOutput(),
      );
      await authority.setPhoneUiActive(false);
      await controller.requestNavigation(WearScreenId.printerSelect);
      controller.registerScreenActions(
        WearScreenId.printerSelect,
        WearScreenActionHandler(onUp: () => upCalls++),
      );

      await controller.handleVoiceCommand(WearVoiceCommand.up);

      expect(upCalls, 0);
    });

    test('routes free phrase to current screen handler', () async {
      String? handledPhrase;
      final WearFlowController controller = createFlow(
        glassesOutput: _FakeGlassesOutput(),
        navigationOutput: _FakeNavigationOutput(),
      );

      await authority.setPhoneUiActive(true);
      await controller.requestNavigation(WearScreenId.printerSelect);
      controller.registerScreenActions(
        WearScreenId.printerSelect,
        WearScreenActionHandler(
          onPhrase: (String phrase) {
            handledPhrase = phrase;
          },
        ),
      );

      await controller.handleVoicePhrase('чудо творожок');

      expect(handledPhrase, 'чудо творожок');
    });

    test('routes partial phrase to current screen handler', () async {
      String? handledPhrase;
      final WearFlowController controller = createFlow(
        glassesOutput: _FakeGlassesOutput(),
        navigationOutput: _FakeNavigationOutput(),
      );

      await authority.setPhoneUiActive(true);
      await controller.requestNavigation(WearScreenId.printerSelect);
      controller.registerScreenActions(
        WearScreenId.printerSelect,
        WearScreenActionHandler(
          onPartialPhrase: (String phrase) {
            handledPhrase = phrase;
            return true;
          },
        ),
      );

      final bool consumed =
          await controller.handleVoicePartialPhrase('безалкогольное');

      expect(consumed, isTrue);
      expect(handledPhrase, 'безалкогольное');
    });

    test('partial phrase returns false without screen handler', () async {
      final WearFlowController controller = createFlow(
        glassesOutput: _FakeGlassesOutput(),
        navigationOutput: _FakeNavigationOutput(),
      );

      await authority.setPhoneUiActive(true);
      await controller.requestNavigation(WearScreenId.printerSelect);

      final bool consumed =
          await controller.handleVoicePartialPhrase('безалкогольное');

      expect(consumed, isFalse);
    });

    test('routes next page command to current screen handler', () async {
      var calls = 0;
      final WearFlowController controller = createFlow(
        glassesOutput: _FakeGlassesOutput(),
        navigationOutput: _FakeNavigationOutput(),
      );

      await authority.setPhoneUiActive(true);
      await controller.requestNavigation(WearScreenId.printerSelect);
      controller.registerScreenActions(
        WearScreenId.printerSelect,
        WearScreenActionHandler(
          onNextPage: () {
            calls++;
          },
        ),
      );

      await controller.handleVoiceCommand(WearVoiceCommand.nextPage);

      expect(calls, 1);
    });

    test('routes previous page command to current screen handler', () async {
      var calls = 0;
      final WearFlowController controller = createFlow(
        glassesOutput: _FakeGlassesOutput(),
        navigationOutput: _FakeNavigationOutput(),
      );

      await authority.setPhoneUiActive(true);
      await controller.requestNavigation(WearScreenId.printerSelect);
      controller.registerScreenActions(
        WearScreenId.printerSelect,
        WearScreenActionHandler(
          onPreviousPage: () {
            calls++;
          },
        ),
      );

      await controller.handleVoiceCommand(WearVoiceCommand.previousPage);

      expect(calls, 1);
    });

    test('rapid down preserves intermediate focusedIndex in stateStream',
        () async {
      final List<WearFlowState> states = <WearFlowState>[];
      final WearFlowController controller = createFlow(
        glassesOutput: _FakeGlassesOutput(),
        navigationOutput: _FakeNavigationOutput(),
      );
      controller.stateStream.listen(states.add);

      await authority.setPhoneUiActive(true);
      await controller.requestNavigation(WearScreenId.menu);

      for (int i = 0; i < 3; i++) {
        await controller.handleVoiceCommand(WearVoiceCommand.down);
      }

      await Future<void>.delayed(Duration.zero);

      expect(controller.state.menuFocusedIndex, 3);
      expect(
        states
            .where((s) => s.screen == WearScreenId.menu)
            .map((s) => s.menuFocusedIndex),
        containsAllInOrder(<int>[0, 1, 2, 3]),
      );
    });

    test('rapid up at top boundary stays at 0', () async {
      final List<WearFlowState> states = <WearFlowState>[];
      final WearFlowController controller = createFlow(
        glassesOutput: _FakeGlassesOutput(),
        navigationOutput: _FakeNavigationOutput(),
      );
      controller.stateStream.listen(states.add);

      await authority.setPhoneUiActive(true);
      await controller.requestNavigation(WearScreenId.menu);
      // move to 2 then try to go up 3 times past 0
      await controller.handleVoiceCommand(WearVoiceCommand.down);
      await controller.handleVoiceCommand(WearVoiceCommand.down);
      await controller.handleVoiceCommand(WearVoiceCommand.up);
      await controller.handleVoiceCommand(WearVoiceCommand.up);
      await controller.handleVoiceCommand(WearVoiceCommand.up);

      expect(controller.state.menuFocusedIndex, 0);
    });

    test('back while active calls navigationOutput.back when no handler',
        () async {
      final _FakeNavigationOutput navigation = _FakeNavigationOutput();
      final WearFlowController controller = createFlow(
        glassesOutput: _FakeGlassesOutput(),
        navigationOutput: navigation,
      );

      await authority.setPhoneUiActive(true);
      await controller.requestNavigation(WearScreenId.printerSelect);
      await controller.handleVoiceCommand(WearVoiceCommand.back);

      expect(navigation.backCalls, 1);
    });

    test('home while inactive stores pending menu navigation', () async {
      final _FakeNavigationOutput navigation = _FakeNavigationOutput();
      final WearFlowController controller = createFlow(
        glassesOutput: _FakeGlassesOutput(),
        navigationOutput: navigation,
      );

      await authority.setPhoneUiActive(false);
      await controller.requestNavigation(WearScreenId.printerSelect);
      await controller.handleVoiceCommand(WearVoiceCommand.home);

      expect(
        controller.state.pendingNavigation?.screen,
        WearScreenId.menu,
      );
      expect(controller.state.screen, WearScreenId.menu);
      expect(navigation.homeCalls, 0);
    });

    test('home navigates directly to menu', () async {
      final _FakeNavigationOutput navigation = _FakeNavigationOutput();
      final WearFlowController controller = createFlow(
        glassesOutput: _FakeGlassesOutput(),
        navigationOutput: navigation,
      );

      await authority.setPhoneUiActive(true);
      await controller.requestNavigation(WearScreenId.printerSelect);
      await controller.handleVoiceCommand(WearVoiceCommand.home);

      expect(controller.state.screen, WearScreenId.menu);
      expect(navigation.replaceCalls, <WearScreenId>[WearScreenId.menu]);
    });

    test('stateStream emits count matches handleVoiceCommand calls', () async {
      final List<WearFlowState> states = <WearFlowState>[];
      final WearFlowController controller = createFlow(
        glassesOutput: _FakeGlassesOutput(),
        navigationOutput: _FakeNavigationOutput(),
      );
      controller.stateStream.listen(states.add);

      await authority.setPhoneUiActive(true);
      await controller.requestNavigation(WearScreenId.menu);

      final int commands = 5;
      for (int i = 0; i < commands; i++) {
        await controller.handleVoiceCommand(WearVoiceCommand.down);
      }

      await Future<void>.delayed(Duration.zero);

      expect(states.length, greaterThanOrEqualTo(commands));
    });

    test('down from index 0 sends payload with selectedIndex=1', () async {
      final glasses = _FakeGlassesOutput();
      final controller = createFlow(
        glassesOutput: glasses,
        navigationOutput: _FakeNavigationOutput(),
      );
      await authority.setPhoneUiActive(true);
      await controller.requestNavigation(WearScreenId.menu);

      await controller.handleVoiceCommand(WearVoiceCommand.down);

      expect(glasses.payloads.last.selectedIndex, 1);
      expect(glasses.payloads.last.screenType, WearGlassesScreenType.menu);
      expect(glasses.payloads.last.phase, WearGlassesPhase.idle);
    });

    test('down at menu bottom stays at 3', () async {
      final glasses = _FakeGlassesOutput();
      final controller = createFlow(
        glassesOutput: glasses,
        navigationOutput: _FakeNavigationOutput(),
      );
      await authority.setPhoneUiActive(true);
      await controller.requestNavigation(WearScreenId.menu);

      for (int i = 0; i < 6; i++) {
        await controller.handleVoiceCommand(WearVoiceCommand.down);
      }

      expect(controller.state.menuFocusedIndex, 3);
      expect(glasses.payloads.last.selectedIndex, 3);
    });

    test('up at menu top stays at 0', () async {
      final glasses = _FakeGlassesOutput();
      final controller = createFlow(
        glassesOutput: glasses,
        navigationOutput: _FakeNavigationOutput(),
      );
      await authority.setPhoneUiActive(true);
      await controller.requestNavigation(WearScreenId.menu);

      await controller.handleVoiceCommand(WearVoiceCommand.down);
      await controller.handleVoiceCommand(WearVoiceCommand.down);
      for (int i = 0; i < 5; i++) {
        await controller.handleVoiceCommand(WearVoiceCommand.up);
      }

      expect(controller.state.menuFocusedIndex, 0);
      expect(glasses.payloads.last.selectedIndex, 0);
    });

    test('menu items payload contains correct item names', () async {
      final glasses = _FakeGlassesOutput();
      final controller = createFlow(
        glassesOutput: glasses,
        navigationOutput: _FakeNavigationOutput(),
      );
      await authority.setPhoneUiActive(true);
      await controller.requestNavigation(WearScreenId.menu);

      await controller.handleVoiceCommand(WearVoiceCommand.down);

      expect(
        glasses.payloads.last.items,
        <String>[
          'Печать ценников',
          'Доступность',
          'Справка',
          'Настройки',
        ],
      );
    });

    test('payload selectedIndex matches menuFocusedIndex after each command',
        () async {
      final glasses = _FakeGlassesOutput();
      final controller = createFlow(
        glassesOutput: glasses,
        navigationOutput: _FakeNavigationOutput(),
      );
      await authority.setPhoneUiActive(true);
      await controller.requestNavigation(WearScreenId.menu);

      await controller.handleVoiceCommand(WearVoiceCommand.down);
      expect(glasses.payloads.last.selectedIndex, 1);
      expect(
        glasses.payloads.last.selectedIndex,
        controller.state.menuFocusedIndex,
      );

      await controller.handleVoiceCommand(WearVoiceCommand.down);
      expect(glasses.payloads.last.selectedIndex, 2);
      expect(
        glasses.payloads.last.selectedIndex,
        controller.state.menuFocusedIndex,
      );

      await controller.handleVoiceCommand(WearVoiceCommand.up);
      expect(glasses.payloads.last.selectedIndex, 1);
      expect(
        glasses.payloads.last.selectedIndex,
        controller.state.menuFocusedIndex,
      );

      await controller.handleVoiceCommand(WearVoiceCommand.up);
      expect(glasses.payloads.last.selectedIndex, 0);
      expect(
        glasses.payloads.last.selectedIndex,
        controller.state.menuFocusedIndex,
      );
    });

    test(
        'back from scanIdle and enterScreen(printerSelect) fixes state for next back',
        () async {
      final nav = _FakeNavigationOutput();
      final controller = createFlow(
        glassesOutput: _FakeGlassesOutput(),
        navigationOutput: nav,
      );
      await authority.setPhoneUiActive(true);
      await controller.requestNavigation(WearScreenId.scanIdle);

      // First back: GoRouter pops to printerSelect.
      await controller.handleVoiceCommand(WearVoiceCommand.back);
      expect(nav.backCalls, 1);

      // Simulate GoRouter pop → enterScreen(printerSelect).
      await controller.requestNavigation(WearScreenId.printerSelect);
      expect(controller.state.screen, WearScreenId.printerSelect);

      // Second back: printerSelect has no back handler → calls back().
      await controller.handleVoiceCommand(WearVoiceCommand.back);
      expect(nav.backCalls, 2);
    });

    test('queued voice command is dropped after the first changes screen',
        () async {
      final WearFlowController controller = createFlow(
        glassesOutput: _FakeGlassesOutput(),
        navigationOutput: _FakeNavigationOutput(),
      );
      await authority.setPhoneUiActive(true);
      await controller.requestNavigation(WearScreenId.menu);

      final Future<void> select =
          controller.handleVoiceCommand(WearVoiceCommand.select);
      final Future<void> stale =
          controller.handleVoiceCommand(WearVoiceCommand.home);
      await Future.wait<void>(<Future<void>>[select, stale]);

      expect(controller.state.screen, WearScreenId.printerSelect);
    });

    test('menu down does not await a blocking glasses render', () async {
      final _BlockingGlassesOutput glasses = _BlockingGlassesOutput();
      final WearFlowController controller = createFlow(
        glassesOutput: glasses,
        navigationOutput: _FakeNavigationOutput(),
      );

      await authority.setPhoneUiActive(true);
      await controller.requestNavigation(WearScreenId.menu);

      await controller.handleVoiceCommand(WearVoiceCommand.down);

      expect(controller.state.menuFocusedIndex, 1);
      expect(glasses.payloads.length, greaterThanOrEqualTo(1));
    });

    test('flashlight command toggles scanner flashlight action', () async {
      int flashlightCalls = 0;
      final WearFlowController controller = createFlow(
        glassesOutput: _FakeGlassesOutput(),
        navigationOutput: _FakeNavigationOutput(),
        flashlightToggle: () async {
          flashlightCalls++;
        },
      );

      await controller.handleVoiceCommand(WearVoiceCommand.flashlight);
      await controller.handleVoiceCommand(WearVoiceCommand.flashlight);

      expect(flashlightCalls, 2);
    });

    test('finish command does not fall back to select action', () async {
      int selectCalls = 0;
      final WearFlowController controller = createFlow(
        glassesOutput: _FakeGlassesOutput(),
        navigationOutput: _FakeNavigationOutput(),
      );
      await authority.setPhoneUiActive(true);
      await controller.requestNavigation(WearScreenId.availabilityCheck);
      controller.registerScreenActions(
        WearScreenId.availabilityCheck,
        WearScreenActionHandler(
          onSelect: () {
            selectCalls++;
          },
        ),
      );

      await controller.handleVoiceCommand(WearVoiceCommand.finish);

      expect(selectCalls, 0);
    });

    test('continue and finish invoke semantic continue-scan actions', () async {
      int continueCalls = 0;
      int finishCalls = 0;
      final WearFlowController controller = createFlow(
        glassesOutput: _FakeGlassesOutput(),
        navigationOutput: _FakeNavigationOutput(),
      );
      await authority.setPhoneUiActive(true);
      await controller.requestNavigation(WearScreenId.continueScan);
      controller.registerScreenActions(
        WearScreenId.continueScan,
        WearScreenActionHandler(
          onContinue: () => continueCalls++,
          onFinish: () => finishCalls++,
        ),
      );

      await controller.handleVoiceCommand(WearVoiceCommand.finish);
      await controller.handleVoiceCommand(WearVoiceCommand.continueScan);

      expect(finishCalls, 1);
      expect(continueCalls, 1);
    });

    test('replace navigation preserves target screen and extra', () async {
      final _FakeNavigationOutput navigation = _FakeNavigationOutput();
      final WearFlowController controller = createFlow(
        glassesOutput: _FakeGlassesOutput(),
        navigationOutput: navigation,
      );
      final Object extra = Object();

      await controller.requestNavigation(
        WearScreenId.continueScan,
        extra: extra,
        replaceCurrent: true,
      );
      await authority.setPhoneUiActive(true);
      await Future<void>.delayed(Duration.zero);

      expect(
        navigation.replaceCalls,
        <WearScreenId>[WearScreenId.continueScan],
      );
      expect(navigation.replaceExtras, <Object?>[extra]);
      expect(navigation.homeCalls, 0);
    });

    test('active barcode is dispatched to the current screen handler',
        () async {
      final WearFlowController controller = createFlow(
        glassesOutput: _FakeGlassesOutput(),
        navigationOutput: _FakeNavigationOutput(),
      );
      String? received;
      await authority.setPhoneUiActive(true);
      await controller.requestNavigation(WearScreenId.scanIdle);
      controller.registerScreenActions(
        WearScreenId.scanIdle,
        WearScreenActionHandler(
          onBarcode: (String barcode) => received = barcode,
        ),
      );

      expect(await controller.handleBarcode('4600000000001'), isTrue);
      expect(received, '4600000000001');
    });

    test('legacy barcode callback cannot open aggregate admission', () async {
      final WearFlowController controller = createFlow(
        glassesOutput: _FakeGlassesOutput(),
        navigationOutput: _FakeNavigationOutput(),
      );
      int calls = 0;
      await authority.setPhoneUiActive(true);
      await controller.requestNavigation(WearScreenId.availabilityCheck);
      controller.registerScreenActions(
        WearScreenId.availabilityCheck,
        WearScreenActionHandler(
          onBarcode: (_) => calls++,
          barcodeEnabled: () => true,
        ),
      );

      expect(controller.currentScreenAcceptsBarcode, isFalse);
      expect(await controller.handleBarcode('product'), isFalse);
      expect(calls, 0);
    });

    test('yes and no commands invoke semantic screen actions', () async {
      int yesCalls = 0;
      int noCalls = 0;
      final WearFlowController controller = createFlow(
        glassesOutput: _FakeGlassesOutput(),
        navigationOutput: _FakeNavigationOutput(),
      );
      await authority.setPhoneUiActive(true);
      await controller.requestNavigation(WearScreenId.availabilityCheck);
      controller.registerScreenActions(
        WearScreenId.availabilityCheck,
        WearScreenActionHandler(
          onYes: () {
            yesCalls++;
          },
          onNo: () {
            noCalls++;
          },
        ),
      );

      await controller.handleVoiceCommand(WearVoiceCommand.yes);
      await controller.handleVoiceCommand(WearVoiceCommand.no);

      expect(yesCalls, 1);
      expect(noCalls, 1);
    });

    test('photo command invokes only the current photo screen action',
        () async {
      var photoCalls = 0;
      final WearFlowController controller = createFlow(
        glassesOutput: _FakeGlassesOutput(),
        navigationOutput: _FakeNavigationOutput(),
      );
      await authority.setPhoneUiActive(true);
      controller.registerScreenActions(
        WearScreenId.availabilityCheck,
        WearScreenActionHandler(onPhoto: () => photoCalls++),
      );

      await controller.requestNavigation(WearScreenId.menu);
      await controller.handleVoiceCommand(WearVoiceCommand.takePhoto);
      expect(photoCalls, 0);

      await controller.requestNavigation(WearScreenId.availabilityCheck);
      await controller.handleVoiceCommand(WearVoiceCommand.takePhoto);
      expect(photoCalls, 1);
    });

    test('test photo command captures a photo on every screen', () async {
      var photoCaptures = 0;
      final WearFlowController controller = createFlow(
        glassesOutput: _FakeGlassesOutput(),
        navigationOutput: _FakeNavigationOutput(),
        photoCapture: () async => photoCaptures++,
      );
      await authority.setPhoneUiActive(true);

      await controller.requestNavigation(WearScreenId.menu);
      await controller.handleVoiceCommand(WearVoiceCommand.testPhoto);
      await controller.requestNavigation(WearScreenId.help);
      await controller.handleVoiceCommand(WearVoiceCommand.testPhoto);

      expect(photoCaptures, 2);
    });

    test('yes command falls back to select when screen has no yes action',
        () async {
      int selectCalls = 0;
      final WearFlowController controller = createFlow(
        glassesOutput: _FakeGlassesOutput(),
        navigationOutput: _FakeNavigationOutput(),
      );
      await authority.setPhoneUiActive(true);
      await controller.requestNavigation(WearScreenId.availabilityCheck);
      controller.registerScreenActions(
        WearScreenId.availabilityCheck,
        WearScreenActionHandler(
          onSelect: () {
            selectCalls++;
          },
        ),
      );

      await controller.handleVoiceCommand(WearVoiceCommand.yes);

      expect(selectCalls, 1);
    });
    test('clarification selection returns and invokes source item by id',
        () async {
      final _FakeNavigationOutput navigation = _FakeNavigationOutput();
      final WearFlowController controller = createFlow(
        glassesOutput: _FakeGlassesOutput(),
        navigationOutput: navigation,
      );
      String? selectedId;
      await authority.setPhoneUiActive(true);
      controller.registerScreenActions(
        WearScreenId.availabilityProduct,
        WearScreenActionHandler(
          onDynamicItem: (String itemId) => selectedId = itemId,
          dynamicVoiceItems: () => const VoiceDynamicItemsSnapshot(
            revision: 1,
            items: <VoiceDynamicItem>[
              VoiceDynamicItem(id: '1', label: 'Коровка из Кореновки пломбир'),
              VoiceDynamicItem(id: '2', label: 'Коровка из Кореновки стакан'),
            ],
          ),
        ),
      );
      const VoiceClarificationArgs args = VoiceClarificationArgs(
        sourceScreen: WearScreenId.availabilityProduct,
        phrase: 'коровка из кореновки',
        sourceListRevision: 1,
        matches: <VoiceDynamicItem>[
          VoiceDynamicItem(id: '1', label: 'Коровка из Кореновки пломбир'),
          VoiceDynamicItem(id: '2', label: 'Коровка из Кореновки стакан'),
        ],
      );
      await controller.requestNavigation(WearScreenId.voiceClarification,
          extra: args);

      await controller.selectVoiceClarificationItem(args, '2');

      expect(navigation.backCalls, 1);
      expect(controller.state.screen, WearScreenId.availabilityProduct);
      expect(selectedId, '2');
    });

    test('clarification selection accepts the frozen aggregate context',
        () async {
      final WearFlowController controller = createFlow(
        glassesOutput: _FakeGlassesOutput(),
        navigationOutput: _FakeNavigationOutput(),
      );
      String? selectedId;
      await authority.setPhoneUiActive(true);
      controller.registerScreenActions(
        WearScreenId.availabilityProduct,
        WearScreenActionHandler(
          onDynamicItem: (String itemId) => selectedId = itemId,
          dynamicVoiceItems: () => const VoiceDynamicItemsSnapshot(
            revision: 1,
            items: <VoiceDynamicItem>[
              VoiceDynamicItem(id: '1', label: 'Первый товар'),
            ],
          ),
        ),
      );
      const VoiceClarificationArgs args = VoiceClarificationArgs(
        sourceScreen: WearScreenId.availabilityProduct,
        phrase: 'товар',
        sourceListRevision: 1,
        matches: <VoiceDynamicItem>[
          VoiceDynamicItem(id: '1', label: 'Первый товар'),
        ],
      );
      await controller.requestNavigation(
        WearScreenId.voiceClarification,
        extra: args,
      );
      final VoiceClarificationArgs frozen = VoiceClarificationArgs(
        sourceScreen: WearScreenId.availabilityProduct,
        phrase: 'товар',
        sourceListRevision: 1,
        matches: List<VoiceDynamicItem>.unmodifiable(
          const <VoiceDynamicItem>[
            VoiceDynamicItem(id: '1', label: 'Первый товар'),
          ],
        ),
      );

      expect(identical(frozen, args), isFalse);
      expect(
        await controller.selectVoiceClarificationItem(frozen, '1'),
        isTrue,
      );
      expect(selectedId, '1');
    });

    test('does not leave clarification when selected item became stale',
        () async {
      final _FakeNavigationOutput navigation = _FakeNavigationOutput();
      final WearFlowController controller = createFlow(
        glassesOutput: _FakeGlassesOutput(),
        navigationOutput: navigation,
      );
      await authority.setPhoneUiActive(true);
      controller.registerScreenActions(
        WearScreenId.availabilityProduct,
        WearScreenActionHandler(
          onDynamicItem: (String itemId) {},
          dynamicVoiceItems: () => const VoiceDynamicItemsSnapshot(
            revision: 2,
            items: <VoiceDynamicItem>[
              VoiceDynamicItem(id: '1', label: 'Первый товар'),
            ],
          ),
        ),
      );
      const VoiceClarificationArgs args = VoiceClarificationArgs(
        sourceScreen: WearScreenId.availabilityProduct,
        phrase: 'товар',
        sourceListRevision: 1,
        matches: <VoiceDynamicItem>[
          VoiceDynamicItem(id: '2', label: 'Исчезнувший товар'),
        ],
      );
      await controller.requestNavigation(WearScreenId.voiceClarification,
          extra: args);

      final bool selected =
          await controller.selectVoiceClarificationItem(args, '2');

      expect(selected, isFalse);
      expect(navigation.backCalls, 0);
      expect(controller.state.screen, WearScreenId.voiceClarification);
    });

    test('rejects clarification selection after source revision changes',
        () async {
      final _FakeNavigationOutput navigation = _FakeNavigationOutput();
      final WearFlowController controller = createFlow(
        glassesOutput: _FakeGlassesOutput(),
        navigationOutput: navigation,
      );
      await authority.setPhoneUiActive(true);
      controller.registerScreenActions(
        WearScreenId.availabilityProduct,
        WearScreenActionHandler(
          onDynamicItem: (String itemId) {},
          dynamicVoiceItems: () => const VoiceDynamicItemsSnapshot(
            revision: 2,
            items: <VoiceDynamicItem>[
              VoiceDynamicItem(id: '1', label: 'Товар обновленный'),
            ],
          ),
        ),
      );
      const VoiceClarificationArgs args = VoiceClarificationArgs(
        sourceScreen: WearScreenId.availabilityProduct,
        sourceListRevision: 1,
        phrase: 'товар',
        matches: <VoiceDynamicItem>[
          VoiceDynamicItem(id: '1', label: 'Товар исходный'),
        ],
      );
      await controller.requestNavigation(WearScreenId.voiceClarification,
          extra: args);

      final bool selected =
          await controller.selectVoiceClarificationItem(args, '1');

      expect(selected, isFalse);
      expect(navigation.backCalls, 0);
    });

    test('clarification grammar follows the visible candidate page', () async {
      final WearFlowController controller = createFlow(
        glassesOutput: _FakeGlassesOutput(),
        navigationOutput: _FakeNavigationOutput(),
      );
      const VoiceClarificationArgs args = VoiceClarificationArgs(
        sourceScreen: WearScreenId.availabilityProduct,
        sourceListRevision: 1,
        phrase: 'молоко',
        matches: <VoiceDynamicItem>[
          VoiceDynamicItem(id: '1', label: 'Молоко Альфа'),
          VoiceDynamicItem(id: '2', label: 'Молоко Бета'),
          VoiceDynamicItem(id: '3', label: 'Молоко Гамма'),
          VoiceDynamicItem(id: '4', label: 'Молоко Дельта'),
          VoiceDynamicItem(id: '5', label: 'Молоко Омега'),
        ],
        excludedWords: <String>{'молоко'},
      );
      final List<WearScreenId> changed = <WearScreenId>[];
      controller.screenActionsChanged.listen(changed.add);
      await controller.requestNavigation(WearScreenId.voiceClarification,
          extra: args);
      final List<String> firstPage = controller.voiceGrammarPhrasesFor(
        WearScreenId.voiceClarification,
      );

      controller.setVoiceClarificationFocusedIndex(4, 5);
      await Future<void>.delayed(Duration.zero);
      final List<String> secondPage = controller.voiceGrammarPhrasesFor(
        WearScreenId.voiceClarification,
      );

      expect(
          firstPage, containsAll(<String>['альфа', 'бета', 'гамма', 'дельта']));
      expect(firstPage, isNot(contains('омега')));
      expect(secondPage, <String>['омега']);
      expect(changed, contains(WearScreenId.voiceClarification));
    });

    test('ignores a repeated clarification selection in flight', () async {
      final _FakeNavigationOutput navigation = _FakeNavigationOutput();
      final WearFlowController controller = createFlow(
        glassesOutput: _FakeGlassesOutput(),
        navigationOutput: navigation,
      );
      int selectCalls = 0;
      await authority.setPhoneUiActive(true);
      controller.registerScreenActions(
        WearScreenId.availabilityProduct,
        WearScreenActionHandler(
          onDynamicItem: (String itemId) async {
            selectCalls++;
            await Future<void>.delayed(const Duration(milliseconds: 10));
          },
          dynamicVoiceItems: () => const VoiceDynamicItemsSnapshot(
            revision: 1,
            items: <VoiceDynamicItem>[
              VoiceDynamicItem(id: '2', label: 'Второй товар'),
            ],
          ),
        ),
      );
      const VoiceClarificationArgs args = VoiceClarificationArgs(
        sourceScreen: WearScreenId.availabilityProduct,
        phrase: 'товар',
        sourceListRevision: 1,
        matches: <VoiceDynamicItem>[
          VoiceDynamicItem(id: '2', label: 'Второй товар'),
        ],
      );
      await controller.requestNavigation(WearScreenId.voiceClarification,
          extra: args);

      final Future<bool> first =
          controller.selectVoiceClarificationItem(args, '2');
      await Future<void>.delayed(Duration.zero);
      final bool second =
          await controller.selectVoiceClarificationItem(args, '2');

      expect(second, isFalse);
      expect(await first, isTrue);
      expect(selectCalls, 1);
      expect(navigation.backCalls, 1);
    });

    test('keeps refined clarification after cancelling home confirmation',
        () async {
      final WearFlowController controller = createFlow(
        glassesOutput: _FakeGlassesOutput(),
        navigationOutput: _FakeNavigationOutput(),
      );
      const VoiceClarificationArgs root = VoiceClarificationArgs(
        sourceScreen: WearScreenId.availabilityProduct,
        phrase: 'коровка',
        sourceListRevision: 1,
        matches: <VoiceDynamicItem>[
          VoiceDynamicItem(id: '1', label: 'Коровка пломбир'),
          VoiceDynamicItem(id: '2', label: 'Коровка стакан'),
          VoiceDynamicItem(id: '3', label: 'Коровка эскимо'),
        ],
      );
      const VoiceClarificationArgs refined = VoiceClarificationArgs(
        sourceScreen: WearScreenId.availabilityProduct,
        phrase: 'пломбир',
        sourceListRevision: 1,
        matches: <VoiceDynamicItem>[
          VoiceDynamicItem(id: '1', label: 'Коровка пломбир'),
          VoiceDynamicItem(id: '2', label: 'Коровка стакан'),
        ],
        previous: root,
      );
      await controller.requestNavigation(
        WearScreenId.voiceClarification,
        extra: refined,
      );
      controller.setVoiceClarificationFocusedIndex(1, 2);

      await controller.requestNavigation(WearScreenId.homeConfirm);
      await controller.requestNavigation(
        WearScreenId.voiceClarification,
        extra: root,
      );

      expect(controller.state.currentVoiceClarificationArgs, same(refined));
      expect(controller.state.voiceClarificationFocusedIndex, 1);
    });

    test('shows clarification notice without replacing matches', () async {
      final _FakeGlassesOutput glasses = _FakeGlassesOutput();
      final WearFlowController controller = createFlow(
        glassesOutput: glasses,
        navigationOutput: _FakeNavigationOutput(),
      );
      const VoiceClarificationArgs args = VoiceClarificationArgs(
        sourceScreen: WearScreenId.availabilityProduct,
        phrase: 'коровка',
        sourceListRevision: 1,
        matches: <VoiceDynamicItem>[
          VoiceDynamicItem(id: '1', label: 'Коровка пломбир'),
          VoiceDynamicItem(id: '2', label: 'Коровка стакан'),
        ],
      );
      await controller.requestNavigation(WearScreenId.voiceClarification,
          extra: args);

      controller.setVoiceClarificationNotice('Назовите точнее');
      await controller.renderCurrentGlasses();

      expect(glasses.payloads.last.statusText, 'Назовите точнее');
      expect(glasses.payloads.last.items, <String>[
        'Коровка пломбир',
        'Коровка стакан',
      ]);

      await controller.setRecognitionDelayVisible(
        WearScreenId.voiceClarification,
        true,
        'Коровка пломбир',
      );
      expect(
        glasses.payloads.last.statusText,
        'Похоже: Коровка пломбир',
      );
      expect(glasses.payloads.last.items, <String>[
        'Коровка пломбир',
        'Коровка стакан',
      ]);

      controller.setVoiceClarificationNotice(null);
      expect(controller.state.voiceClarificationNotice, isNull);
    });

    test('clears clarification arguments after leaving the flow', () async {
      final WearFlowController controller = createFlow(
        glassesOutput: _FakeGlassesOutput(),
        navigationOutput: _FakeNavigationOutput(),
      );
      const VoiceClarificationArgs args = VoiceClarificationArgs(
        sourceScreen: WearScreenId.availabilityProduct,
        phrase: 'товар',
        sourceListRevision: 1,
        matches: <VoiceDynamicItem>[],
      );
      await controller.requestNavigation(WearScreenId.voiceClarification,
          extra: args);

      await controller.requestNavigation(WearScreenId.menu);

      expect(controller.state.currentVoiceClarificationArgs, isNull);
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

class _BlockingGlassesOutput implements WearGlassesOutput {
  final List<WearGlassesPayload> payloads = <WearGlassesPayload>[];

  @override
  Future<void> send(WearGlassesPayload payload) async {
    payloads.add(payload);
    await Future<void>.delayed(const Duration(seconds: 10));
  }
}

class _FakeNavigationOutput implements WearNavigationOutput {
  final List<WearScreenId> goToCalls = <WearScreenId>[];
  final List<Object?> goToExtras = <Object?>[];
  final List<WearScreenId> replaceCalls = <WearScreenId>[];
  final List<Object?> replaceExtras = <Object?>[];
  int backCalls = 0;
  int homeCalls = 0;
  final List<List<WearNavigationEntry>> synchronizedHistories =
      <List<WearNavigationEntry>>[];

  @override
  Future<void> goTo(WearScreenId screen, {Object? extra}) async {
    goToCalls.add(screen);
    goToExtras.add(extra);
  }

  @override
  Future<void> replace(WearScreenId screen, {Object? extra}) async {
    replaceCalls.add(screen);
    replaceExtras.add(extra);
  }

  @override
  Future<void> back() async {
    backCalls++;
  }

  @override
  Future<void> home() async {
    homeCalls++;
  }

  @override
  Future<void> synchronize(List<WearNavigationEntry> history) async {
    synchronizedHistories.add(List<WearNavigationEntry>.of(history));
  }
}
