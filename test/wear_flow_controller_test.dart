import 'package:flutter_test/flutter_test.dart';
import 'package:smart_glasses/modules/wear/application/ports/wear_glasses_output.dart';
import 'package:smart_glasses/modules/wear/application/ports/wear_navigation_output.dart';
import 'package:smart_glasses/modules/wear/application/wear_flow_controller.dart';
import 'package:smart_glasses/modules/wear/application/wear_flow_state.dart';
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
      controller.setMenuFocusedIndex(2);

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
      controller.setMenuFocusedIndex(3);
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

    test('printer select clears remembered payload on re-enter', () async {
      final _FakeGlassesOutput glasses = _FakeGlassesOutput();
      final WearFlowController controller = WearFlowController(
        glassesOutput: glasses,
        navigationOutput: _FakeNavigationOutput(),
      );
      const WearGlassesPayload printerPayload = WearGlassesPayload(
        screenType: WearGlassesScreenType.printer,
        phase: WearGlassesPhase.idle,
        title: 'Выбор принтера',
        subtitle: 'Жёлтые ценники',
        items: <String>['MOCK Желтый 1'],
      );

      controller.rememberScreenPayload(
        WearScreenId.printerSelect,
        printerPayload,
      );
      controller.enterScreen(WearScreenId.printerSelect);
      await Future<void>.delayed(Duration.zero);

      expect(glasses.payloads.last.title, 'Принтеры');
      expect(glasses.payloads.last.isLoading, isTrue);
    });

    test('returning from home confirmation restores printer payload', () async {
      final _FakeGlassesOutput glasses = _FakeGlassesOutput();
      final WearFlowController controller = WearFlowController(
        glassesOutput: glasses,
        navigationOutput: _FakeNavigationOutput(),
      );
      const WearGlassesPayload printerPayload = WearGlassesPayload(
        screenType: WearGlassesScreenType.printer,
        phase: WearGlassesPhase.idle,
        title: 'Выбор принтера',
        items: <String>['Белый 1', 'Жёлтый 1'],
      );
      controller.setUiLifecycle(WearUiLifecycle.active);
      controller.enterScreen(WearScreenId.printerSelect);
      controller.rememberScreenPayload(
        WearScreenId.printerSelect,
        printerPayload,
      );

      await controller.handleVoiceCommand(WearVoiceCommand.home);
      controller.enterScreen(WearScreenId.printerSelect);
      await Future<void>.delayed(Duration.zero);

      expect(glasses.payloads.last, printerPayload);
    });

    test('routes free phrase to current screen handler', () async {
      String? handledPhrase;
      final WearFlowController controller = WearFlowController(
        glassesOutput: _FakeGlassesOutput(),
        navigationOutput: _FakeNavigationOutput(),
      );

      controller.setUiLifecycle(WearUiLifecycle.active);
      controller.enterScreen(WearScreenId.printerSelect);
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
      final WearFlowController controller = WearFlowController(
        glassesOutput: _FakeGlassesOutput(),
        navigationOutput: _FakeNavigationOutput(),
      );

      controller.setUiLifecycle(WearUiLifecycle.active);
      controller.enterScreen(WearScreenId.printerSelect);
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
      final WearFlowController controller = WearFlowController(
        glassesOutput: _FakeGlassesOutput(),
        navigationOutput: _FakeNavigationOutput(),
      );

      controller.setUiLifecycle(WearUiLifecycle.active);
      controller.enterScreen(WearScreenId.printerSelect);

      final bool consumed =
          await controller.handleVoicePartialPhrase('безалкогольное');

      expect(consumed, isFalse);
    });

    test('routes next page command to current screen handler', () async {
      var calls = 0;
      final WearFlowController controller = WearFlowController(
        glassesOutput: _FakeGlassesOutput(),
        navigationOutput: _FakeNavigationOutput(),
      );

      controller.setUiLifecycle(WearUiLifecycle.active);
      controller.enterScreen(WearScreenId.printerSelect);
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
      final WearFlowController controller = WearFlowController(
        glassesOutput: _FakeGlassesOutput(),
        navigationOutput: _FakeNavigationOutput(),
      );

      controller.setUiLifecycle(WearUiLifecycle.active);
      controller.enterScreen(WearScreenId.printerSelect);
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
      final WearFlowController controller = WearFlowController(
        glassesOutput: _FakeGlassesOutput(),
        navigationOutput: _FakeNavigationOutput(),
      );
      controller.stateStream.listen(states.add);

      controller.setUiLifecycle(WearUiLifecycle.active);
      controller.enterScreen(WearScreenId.menu);

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
      final WearFlowController controller = WearFlowController(
        glassesOutput: _FakeGlassesOutput(),
        navigationOutput: _FakeNavigationOutput(),
      );
      controller.stateStream.listen(states.add);

      controller.setUiLifecycle(WearUiLifecycle.active);
      controller.enterScreen(WearScreenId.menu);
      // move to 2 then try to go up 3 times past 0
      await controller.handleVoiceCommand(WearVoiceCommand.down);
      await controller.handleVoiceCommand(WearVoiceCommand.down);
      await controller.handleVoiceCommand(WearVoiceCommand.up);
      await controller.handleVoiceCommand(WearVoiceCommand.up);
      await controller.handleVoiceCommand(WearVoiceCommand.up);

      expect(controller.state.menuFocusedIndex, 0);
    });

    test('back-to-back select while inactive keeps only last pendingNavigation',
        () async {
      final _FakeNavigationOutput navigation = _FakeNavigationOutput();
      final WearFlowController controller = WearFlowController(
        glassesOutput: _FakeGlassesOutput(),
        navigationOutput: navigation,
      );

      controller.setUiLifecycle(WearUiLifecycle.inactive);
      controller.enterScreen(WearScreenId.menu);
      controller.setMenuFocusedIndex(1);
      await controller.handleVoiceCommand(WearVoiceCommand.select);
      final firstPending = controller.state.pendingNavigation;

      controller.setMenuFocusedIndex(2);
      await controller.handleVoiceCommand(WearVoiceCommand.select);
      final secondPending = controller.state.pendingNavigation;

      expect(firstPending?.screen, WearScreenId.printerSelect);
      expect(secondPending?.screen, WearScreenId.availabilityInteraction);
      expect(navigation.goToCalls, isEmpty);
    });

    test('back while active calls navigationOutput.back when no handler',
        () async {
      final _FakeNavigationOutput navigation = _FakeNavigationOutput();
      final WearFlowController controller = WearFlowController(
        glassesOutput: _FakeGlassesOutput(),
        navigationOutput: navigation,
      );

      controller.setUiLifecycle(WearUiLifecycle.active);
      controller.enterScreen(WearScreenId.printerSelect);
      await controller.handleVoiceCommand(WearVoiceCommand.back);

      expect(navigation.backCalls, 1);
    });

    test('back while inactive stores pending menu navigation', () async {
      final _FakeNavigationOutput navigation = _FakeNavigationOutput();
      final WearFlowController controller = WearFlowController(
        glassesOutput: _FakeGlassesOutput(),
        navigationOutput: navigation,
      );

      controller.setUiLifecycle(WearUiLifecycle.inactive);
      controller.enterScreen(WearScreenId.printerSelect);
      await controller.handleVoiceCommand(WearVoiceCommand.back);

      expect(controller.state.pendingNavigation?.screen, WearScreenId.menu);
      expect(navigation.backCalls, 0);
    });

    test('home while inactive stores pending confirm navigation', () async {
      final _FakeNavigationOutput navigation = _FakeNavigationOutput();
      final WearFlowController controller = WearFlowController(
        glassesOutput: _FakeGlassesOutput(),
        navigationOutput: navigation,
      );

      controller.setUiLifecycle(WearUiLifecycle.inactive);
      controller.enterScreen(WearScreenId.printerSelect);
      await controller.handleVoiceCommand(WearVoiceCommand.home);

      expect(
        controller.state.pendingNavigation?.screen,
        WearScreenId.homeConfirm,
      );
      expect(controller.state.screen, WearScreenId.homeConfirm);
      expect(navigation.homeCalls, 0);
    });

    test('repeated home on home confirm still requires confirmation', () async {
      final _FakeNavigationOutput navigation = _FakeNavigationOutput();
      final WearFlowController controller = WearFlowController(
        glassesOutput: _FakeGlassesOutput(),
        navigationOutput: navigation,
      );

      controller.setUiLifecycle(WearUiLifecycle.active);
      controller.enterScreen(WearScreenId.printerSelect);
      await controller.handleVoiceCommand(WearVoiceCommand.home);
      await controller.handleVoiceCommand(WearVoiceCommand.home);

      expect(controller.state.screen, WearScreenId.homeConfirm);
      expect(navigation.goToCalls, <WearScreenId>[WearScreenId.homeConfirm]);
      expect(navigation.homeCalls, 0);
    });

    test('home confirm selects home with replace navigation', () async {
      final _FakeNavigationOutput navigation = _FakeNavigationOutput();
      final WearFlowController controller = WearFlowController(
        glassesOutput: _FakeGlassesOutput(),
        navigationOutput: navigation,
      );

      controller.setUiLifecycle(WearUiLifecycle.active);
      controller.enterScreen(WearScreenId.printerSelect);
      await controller.handleVoiceCommand(WearVoiceCommand.home);
      await controller.handleVoiceCommand(WearVoiceCommand.select);

      expect(controller.state.screen, WearScreenId.menu);
      expect(navigation.homeCalls, 1);
    });

    test('home confirm cancel while inactive restores return screen', () async {
      final _FakeNavigationOutput navigation = _FakeNavigationOutput();
      final WearFlowController controller = WearFlowController(
        glassesOutput: _FakeGlassesOutput(),
        navigationOutput: navigation,
      );

      controller.setUiLifecycle(WearUiLifecycle.inactive);
      controller.enterScreen(WearScreenId.printerSelect);
      await controller.handleVoiceCommand(WearVoiceCommand.home);
      await controller.handleVoiceCommand(WearVoiceCommand.down);
      await controller.handleVoiceCommand(WearVoiceCommand.select);

      expect(controller.state.screen, WearScreenId.printerSelect);
      expect(
        controller.state.pendingNavigation?.screen,
        WearScreenId.printerSelect,
      );
      expect(navigation.backCalls, 0);
    });

    test('mixed up/down/select sequence reaches correct final state', () async {
      final _FakeNavigationOutput navigation = _FakeNavigationOutput();
      final WearFlowController controller = WearFlowController(
        glassesOutput: _FakeGlassesOutput(),
        navigationOutput: navigation,
      );

      controller.setUiLifecycle(WearUiLifecycle.active);
      controller.enterScreen(WearScreenId.menu);

      await controller.handleVoiceCommand(WearVoiceCommand.down);
      await controller.handleVoiceCommand(WearVoiceCommand.down);
      await controller.handleVoiceCommand(WearVoiceCommand.down);
      await controller.handleVoiceCommand(WearVoiceCommand.up);
      await controller.handleVoiceCommand(WearVoiceCommand.select);

      expect(controller.state.menuFocusedIndex, 2);
      expect(
        controller.state.screen,
        WearScreenId.availabilityInteraction,
      );
      expect(
        navigation.goToCalls,
        <WearScreenId>[WearScreenId.availabilityInteraction],
      );
    });

    test('stateStream emits count matches handleVoiceCommand calls', () async {
      final List<WearFlowState> states = <WearFlowState>[];
      final WearFlowController controller = WearFlowController(
        glassesOutput: _FakeGlassesOutput(),
        navigationOutput: _FakeNavigationOutput(),
      );
      controller.stateStream.listen(states.add);

      controller.setUiLifecycle(WearUiLifecycle.active);
      controller.enterScreen(WearScreenId.menu);

      final int commands = 5;
      for (int i = 0; i < commands; i++) {
        await controller.handleVoiceCommand(WearVoiceCommand.down);
      }

      await Future<void>.delayed(Duration.zero);

      expect(states.length, greaterThanOrEqualTo(commands));
    });

    test('sequential queue processes commands in order even without await',
        () async {
      final List<WearFlowState> states = <WearFlowState>[];
      final _FakeNavigationOutput navigation = _FakeNavigationOutput();
      final WearFlowController controller = WearFlowController(
        glassesOutput: _FakeGlassesOutput(),
        navigationOutput: navigation,
      );
      controller.stateStream.listen(states.add);

      controller.setUiLifecycle(WearUiLifecycle.active);
      controller.enterScreen(WearScreenId.menu);

      controller.handleVoiceCommand(WearVoiceCommand.down);
      controller.handleVoiceCommand(WearVoiceCommand.down);
      controller.handleVoiceCommand(WearVoiceCommand.down);
      controller.handleVoiceCommand(WearVoiceCommand.up);
      controller.handleVoiceCommand(WearVoiceCommand.select);

      await Future<void>.delayed(Duration.zero);

      expect(controller.state.menuFocusedIndex, 2);
      expect(
        controller.state.screen,
        WearScreenId.availabilityInteraction,
      );
      expect(
        navigation.goToCalls,
        <WearScreenId>[WearScreenId.availabilityInteraction],
      );
    });

    test('down from index 0 sends payload with selectedIndex=1', () async {
      final glasses = _FakeGlassesOutput();
      final controller = WearFlowController(
        glassesOutput: glasses,
        navigationOutput: _FakeNavigationOutput(),
      );
      controller.setUiLifecycle(WearUiLifecycle.active);
      controller.enterScreen(WearScreenId.menu);

      await controller.handleVoiceCommand(WearVoiceCommand.down);

      expect(glasses.payloads.last.selectedIndex, 1);
      expect(glasses.payloads.last.screenType, WearGlassesScreenType.menu);
      expect(glasses.payloads.last.phase, WearGlassesPhase.idle);
    });

    test('down at menu bottom stays at 4', () async {
      final glasses = _FakeGlassesOutput();
      final controller = WearFlowController(
        glassesOutput: glasses,
        navigationOutput: _FakeNavigationOutput(),
      );
      controller.setUiLifecycle(WearUiLifecycle.active);
      controller.enterScreen(WearScreenId.menu);

      for (int i = 0; i < 6; i++) {
        await controller.handleVoiceCommand(WearVoiceCommand.down);
      }

      expect(controller.state.menuFocusedIndex, 4);
      expect(glasses.payloads.last.selectedIndex, 4);
    });

    test('up at menu top stays at 0', () async {
      final glasses = _FakeGlassesOutput();
      final controller = WearFlowController(
        glassesOutput: glasses,
        navigationOutput: _FakeNavigationOutput(),
      );
      controller.setUiLifecycle(WearUiLifecycle.active);
      controller.enterScreen(WearScreenId.menu);

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
      final controller = WearFlowController(
        glassesOutput: glasses,
        navigationOutput: _FakeNavigationOutput(),
      );
      controller.setUiLifecycle(WearUiLifecycle.active);
      controller.enterScreen(WearScreenId.menu);

      await controller.handleVoiceCommand(WearVoiceCommand.down);

      expect(
        glasses.payloads.last.items,
        <String>[
          'Последнее фото',
          'Печать ценников',
          'Доступность',
          'Справка',
          'Настройки',
        ],
      );
    });

    test('menu item 0 select navigates to latestPhoto', () async {
      final glasses = _FakeGlassesOutput();
      final nav = _FakeNavigationOutput();
      final controller = WearFlowController(
        glassesOutput: glasses,
        navigationOutput: nav,
      );
      controller.setUiLifecycle(WearUiLifecycle.active);
      controller.enterScreen(WearScreenId.menu);

      await controller.handleVoiceCommand(WearVoiceCommand.select);

      expect(controller.state.screen, WearScreenId.latestPhoto);
      expect(glasses.payloads.last.screenType, WearGlassesScreenType.status);
      expect(glasses.payloads.last.title, 'Последнее фото');
      expect(nav.goToCalls, <WearScreenId>[WearScreenId.latestPhoto]);
    });

    test('direct print price tag command navigates from menu to printerSelect',
        () async {
      final nav = _FakeNavigationOutput();
      final controller = WearFlowController(
        glassesOutput: _FakeGlassesOutput(),
        navigationOutput: nav,
      );
      controller.setUiLifecycle(WearUiLifecycle.active);
      controller.enterScreen(WearScreenId.menu);
      await controller.handleVoiceCommand(WearVoiceCommand.down);

      await controller.handleVoiceCommand(WearVoiceCommand.openPrintPriceTag);

      expect(controller.state.screen, WearScreenId.printerSelect);
      expect(controller.state.menuFocusedIndex, 1);
      expect(nav.goToCalls, <WearScreenId>[WearScreenId.printerSelect]);
    });

    test('short print command also navigates from menu to printerSelect',
        () async {
      final nav = _FakeNavigationOutput();
      final controller = WearFlowController(
        glassesOutput: _FakeGlassesOutput(),
        navigationOutput: nav,
      );
      controller.setUiLifecycle(WearUiLifecycle.active);
      controller.enterScreen(WearScreenId.menu);

      await controller.handleVoiceCommand(WearVoiceCommand.print);

      expect(controller.state.screen, WearScreenId.printerSelect);
      expect(nav.goToCalls, <WearScreenId>[WearScreenId.printerSelect]);
    });

    test('direct availability command navigates from menu to availability',
        () async {
      final nav = _FakeNavigationOutput();
      final controller = WearFlowController(
        glassesOutput: _FakeGlassesOutput(),
        navigationOutput: nav,
      );
      controller.setUiLifecycle(WearUiLifecycle.active);
      controller.enterScreen(WearScreenId.menu);

      await controller.handleVoiceCommand(WearVoiceCommand.openAvailability);

      expect(controller.state.screen, WearScreenId.availabilityInteraction);
      expect(controller.state.menuFocusedIndex, 2);
      expect(
          nav.goToCalls, <WearScreenId>[WearScreenId.availabilityInteraction]);
    });

    test('direct list command chooses list in availability interaction',
        () async {
      final nav = _FakeNavigationOutput();
      final controller = WearFlowController(
        glassesOutput: _FakeGlassesOutput(),
        navigationOutput: nav,
      );
      controller.setUiLifecycle(WearUiLifecycle.active);
      controller.enterScreen(WearScreenId.availabilityInteraction);
      await controller.handleVoiceCommand(WearVoiceCommand.down);

      await controller.handleVoiceCommand(WearVoiceCommand.openList);

      expect(controller.state.availabilityInteractionFocusedIndex, 0);
      expect(nav.goToCalls, <WearScreenId>[WearScreenId.availabilityGroup]);
    });

    test('direct scan command chooses direct scan in availability interaction',
        () async {
      final nav = _FakeNavigationOutput();
      final controller = WearFlowController(
        glassesOutput: _FakeGlassesOutput(),
        navigationOutput: nav,
      );
      controller.setUiLifecycle(WearUiLifecycle.active);
      controller.enterScreen(WearScreenId.availabilityInteraction);

      await controller.handleVoiceCommand(WearVoiceCommand.openDirectScan);

      expect(controller.state.availabilityInteractionFocusedIndex, 1);
      expect(
          nav.goToCalls, <WearScreenId>[WearScreenId.availabilityDirectScan]);
    });

    test('menu item 2 select navigates to availabilityInteraction', () async {
      final glasses = _FakeGlassesOutput();
      final nav = _FakeNavigationOutput();
      final controller = WearFlowController(
        glassesOutput: glasses,
        navigationOutput: nav,
      );
      controller.setUiLifecycle(WearUiLifecycle.active);
      controller.enterScreen(WearScreenId.menu);

      await controller.handleVoiceCommand(WearVoiceCommand.down);
      await controller.handleVoiceCommand(WearVoiceCommand.down);
      await controller.handleVoiceCommand(WearVoiceCommand.select);

      expect(controller.state.screen, WearScreenId.availabilityInteraction);
      expect(
        glasses.payloads.last.screenType,
        WearGlassesScreenType.availability,
      );
      expect(
        nav.goToCalls,
        <WearScreenId>[WearScreenId.availabilityInteraction],
      );
    });

    test('menu item 3 select navigates to help', () async {
      final glasses = _FakeGlassesOutput();
      final nav = _FakeNavigationOutput();
      final controller = WearFlowController(
        glassesOutput: glasses,
        navigationOutput: nav,
      );
      controller.setUiLifecycle(WearUiLifecycle.active);
      controller.enterScreen(WearScreenId.menu);

      await controller.handleVoiceCommand(WearVoiceCommand.down);
      await controller.handleVoiceCommand(WearVoiceCommand.down);
      await controller.handleVoiceCommand(WearVoiceCommand.down);
      await controller.handleVoiceCommand(WearVoiceCommand.select);

      expect(controller.state.screen, WearScreenId.help);
      expect(glasses.payloads.last.screenType, WearGlassesScreenType.help);
      expect(nav.goToCalls, <WearScreenId>[WearScreenId.help]);
    });

    test('menu item 4 select navigates to settings', () async {
      final glasses = _FakeGlassesOutput();
      final nav = _FakeNavigationOutput();
      final controller = WearFlowController(
        glassesOutput: glasses,
        navigationOutput: nav,
      );
      controller.setUiLifecycle(WearUiLifecycle.active);
      controller.enterScreen(WearScreenId.menu);

      for (int i = 0; i < 4; i++) {
        await controller.handleVoiceCommand(WearVoiceCommand.down);
      }
      await controller.handleVoiceCommand(WearVoiceCommand.select);

      expect(controller.state.screen, WearScreenId.settings);
      expect(glasses.payloads.last.screenType, WearGlassesScreenType.status);
      expect(nav.goToCalls, <WearScreenId>[WearScreenId.settings]);
    });

    test('payload selectedIndex matches menuFocusedIndex after each command',
        () async {
      final glasses = _FakeGlassesOutput();
      final controller = WearFlowController(
        glassesOutput: glasses,
        navigationOutput: _FakeNavigationOutput(),
      );
      controller.setUiLifecycle(WearUiLifecycle.active);
      controller.enterScreen(WearScreenId.menu);

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
        'back from help delegates to navigation and menu is restored on enterScreen',
        () async {
      final glasses = _FakeGlassesOutput();
      final nav = _FakeNavigationOutput();
      final controller = WearFlowController(
        glassesOutput: glasses,
        navigationOutput: nav,
      );
      controller.setUiLifecycle(WearUiLifecycle.active);
      controller.enterScreen(WearScreenId.help);

      await controller.handleVoiceCommand(WearVoiceCommand.back);

      expect(nav.backCalls, 1);
      // State stays at help until GoRouter pops and calls enterScreen(menu).
      expect(controller.state.screen, WearScreenId.help);

      // Simulate GoRouter pop → menu re-entry.
      controller.enterScreen(WearScreenId.menu);

      expect(glasses.payloads.last.screenType, WearGlassesScreenType.menu);
      expect(controller.state.screen, WearScreenId.menu);
    });

    test(
        'back from scanIdle without enterScreen after pop causes double-pop bug',
        () async {
      final nav = _FakeNavigationOutput();
      final controller = WearFlowController(
        glassesOutput: _FakeGlassesOutput(),
        navigationOutput: nav,
      );
      controller.setUiLifecycle(WearUiLifecycle.active);
      controller.enterScreen(WearScreenId.scanIdle);

      // First back: GoRouter pops to printerSelect.
      await controller.handleVoiceCommand(WearVoiceCommand.back);

      // Without enterScreen(printerSelect), state is still scanIdle.
      expect(nav.backCalls, 1);
      expect(controller.state.screen, WearScreenId.scanIdle);

      // Second back: scanIdle has no back handler → calls back() again.
      await controller.handleVoiceCommand(WearVoiceCommand.back);

      // BUG: second back() popped past printerSelect → landed on menu.
      expect(nav.backCalls, 2);
    });

    test(
        'back from scanIdle and enterScreen(printerSelect) fixes state for next back',
        () async {
      final nav = _FakeNavigationOutput();
      final controller = WearFlowController(
        glassesOutput: _FakeGlassesOutput(),
        navigationOutput: nav,
      );
      controller.setUiLifecycle(WearUiLifecycle.active);
      controller.enterScreen(WearScreenId.scanIdle);

      // First back: GoRouter pops to printerSelect.
      await controller.handleVoiceCommand(WearVoiceCommand.back);
      expect(nav.backCalls, 1);

      // Simulate GoRouter pop → enterScreen(printerSelect).
      controller.enterScreen(WearScreenId.printerSelect);
      expect(controller.state.screen, WearScreenId.printerSelect);

      // Second back: printerSelect has no back handler → calls back().
      await controller.handleVoiceCommand(WearVoiceCommand.back);
      expect(nav.backCalls, 2);
    });

    test('queue does not block when goTo is pending after menu select',
        () async {
      final _BlockingNavigationOutput navigation = _BlockingNavigationOutput();
      final WearFlowController controller = WearFlowController(
        glassesOutput: _FakeGlassesOutput(),
        navigationOutput: navigation,
      );

      controller.setUiLifecycle(WearUiLifecycle.active);
      controller.enterScreen(WearScreenId.menu);
      controller.setMenuFocusedIndex(1);

      controller.handleVoiceCommand(WearVoiceCommand.select);
      await Future<void>.delayed(Duration.zero);

      expect(controller.state.screen, WearScreenId.printerSelect);
      expect(
        navigation.goToCalls,
        <WearScreenId>[WearScreenId.printerSelect],
      );

      controller.handleVoiceCommand(WearVoiceCommand.home);
      await Future<void>.delayed(Duration.zero);

      expect(controller.state.screen, WearScreenId.homeConfirm);
      expect(navigation.goToCalls.last, WearScreenId.homeConfirm);
    });

    test('flashlight command toggles scanner flashlight action', () async {
      int flashlightCalls = 0;
      final WearFlowController controller = WearFlowController(
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
      final WearFlowController controller = WearFlowController(
        glassesOutput: _FakeGlassesOutput(),
        navigationOutput: _FakeNavigationOutput(),
      );
      controller.setUiLifecycle(WearUiLifecycle.active);
      controller.enterScreen(WearScreenId.availabilityCheck);
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
      final WearFlowController controller = WearFlowController(
        glassesOutput: _FakeGlassesOutput(),
        navigationOutput: _FakeNavigationOutput(),
      );
      controller.setUiLifecycle(WearUiLifecycle.active);
      controller.enterScreen(WearScreenId.continueScan);
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

    test('inactive continue returns to scan with printer selection', () async {
      final _FakeNavigationOutput navigation = _FakeNavigationOutput();
      final WearFlowController controller = WearFlowController(
        glassesOutput: _FakeGlassesOutput(),
        navigationOutput: navigation,
      );
      final Object printerSelection = Object();
      controller.enterScreen(
        WearScreenId.scanIdle,
        extra: printerSelection,
      );
      controller.enterScreen(WearScreenId.continueScan);

      await controller.handleVoiceCommand(WearVoiceCommand.continueScan);

      expect(controller.state.screen, WearScreenId.scanIdle);
      expect(controller.state.currentPrinterSelection, same(printerSelection));
      expect(controller.state.pendingNavigation?.popCurrent, isTrue);
      expect(controller.state.pendingNavigation?.extra, same(printerSelection));

      controller.setUiLifecycle(WearUiLifecycle.active);
      await Future<void>.delayed(Duration.zero);

      expect(navigation.backCalls, 1);
      expect(navigation.goToCalls, isEmpty);
    });

    test('inactive finish replaces continue screen with menu', () async {
      final _FakeNavigationOutput navigation = _FakeNavigationOutput();
      final WearFlowController controller = WearFlowController(
        glassesOutput: _FakeGlassesOutput(),
        navigationOutput: navigation,
      );
      controller.enterScreen(WearScreenId.continueScan);

      await controller.handleVoiceCommand(WearVoiceCommand.finish);

      expect(controller.state.screen, WearScreenId.menu);
      expect(controller.state.pendingNavigation?.replaceCurrent, isTrue);

      controller.setUiLifecycle(WearUiLifecycle.active);
      await Future<void>.delayed(Duration.zero);

      expect(navigation.homeCalls, 1);
    });

    test('glasses failure does not block phone navigation', () async {
      final _FakeNavigationOutput navigation = _FakeNavigationOutput();
      final WearFlowController controller = WearFlowController(
        glassesOutput: _ThrowingGlassesOutput(),
        navigationOutput: navigation,
      );
      controller.setUiLifecycle(WearUiLifecycle.active);
      controller.enterScreen(WearScreenId.menu);
      controller.setMenuFocusedIndex(1);

      await controller.handleVoiceCommand(WearVoiceCommand.select);

      expect(controller.state.screen, WearScreenId.printerSelect);
      expect(navigation.goToCalls, <WearScreenId>[WearScreenId.printerSelect]);
    });

    test('inactive lifecycle does not invoke widget callbacks or phrases',
        () async {
      int actionCalls = 0;
      int phraseCalls = 0;
      final WearFlowController controller = WearFlowController(
        glassesOutput: _FakeGlassesOutput(),
        navigationOutput: _FakeNavigationOutput(),
      );
      controller.enterScreen(WearScreenId.availabilityCheck);
      controller.registerScreenActions(
        WearScreenId.availabilityCheck,
        WearScreenActionHandler(
          onManualInput: () => actionCalls++,
          onPhrase: (_) => phraseCalls++,
        ),
      );

      await controller.handleVoiceCommand(WearVoiceCommand.manualInput);
      await controller.handleVoicePhrase('товар');

      expect(actionCalls, 0);
      expect(phraseCalls, 0);
    });

    test('new product selection clears payload cached for previous args',
        () async {
      final _FakeGlassesOutput glasses = _FakeGlassesOutput();
      final WearFlowController controller = WearFlowController(
        glassesOutput: glasses,
        navigationOutput: _FakeNavigationOutput(),
      );
      final Object firstArgs = Object();
      final Object secondArgs = Object();
      const WearGlassesPayload firstPayload = WearGlassesPayload(
        screenType: WearGlassesScreenType.productSelect,
        phase: WearGlassesPhase.idle,
        title: 'Первый список',
      );

      controller.enterScreen(WearScreenId.productSelect, extra: firstArgs);
      controller.rememberScreenPayload(
        WearScreenId.productSelect,
        firstPayload,
      );
      await controller.renderCurrentGlasses();
      expect(glasses.payloads.last.title, 'Первый список');

      controller.enterScreen(WearScreenId.productSelect, extra: secondArgs);
      await Future<void>.delayed(Duration.zero);

      expect(glasses.payloads.last.title, 'Выбор товара');
      expect(glasses.payloads.last.phase, WearGlassesPhase.loading);
    });

    test('new availability context clears payload cached for previous item',
        () async {
      final _FakeGlassesOutput glasses = _FakeGlassesOutput();
      final WearFlowController controller = WearFlowController(
        glassesOutput: glasses,
        navigationOutput: _FakeNavigationOutput(),
      );
      final Object firstGroup = Object();
      final Object secondGroup = Object();
      const WearGlassesPayload firstPayload = WearGlassesPayload(
        screenType: WearGlassesScreenType.availability,
        phase: WearGlassesPhase.idle,
        title: 'Старый список',
      );

      controller.enterScreen(
        WearScreenId.availabilityProduct,
        extra: firstGroup,
      );
      controller.rememberScreenPayload(
        WearScreenId.availabilityProduct,
        firstPayload,
      );
      await controller.renderCurrentGlasses();
      expect(glasses.payloads.last.title, 'Старый список');

      controller.enterScreen(
        WearScreenId.availabilityProduct,
        extra: secondGroup,
      );
      await Future<void>.delayed(Duration.zero);

      expect(glasses.payloads.last.title, 'Товарная позиция');
      expect(glasses.payloads.last.phase, WearGlassesPhase.loading);
    });

    test('returning from availability products restores groups payload',
        () async {
      final _FakeGlassesOutput glasses = _FakeGlassesOutput();
      final WearFlowController controller = WearFlowController(
        glassesOutput: glasses,
        navigationOutput: _FakeNavigationOutput(),
      );
      const WearGlassesPayload groupsPayload = WearGlassesPayload(
        screenType: WearGlassesScreenType.availability,
        phase: WearGlassesPhase.idle,
        title: 'Товарная группа',
        items: <String>['Молочная продукция', 'Хлеб'],
      );

      controller.enterScreen(WearScreenId.availabilityGroup);
      controller.rememberScreenPayload(
        WearScreenId.availabilityGroup,
        groupsPayload,
      );
      controller.enterScreen(
        WearScreenId.availabilityProduct,
        extra: Object(),
      );

      controller.enterScreen(WearScreenId.availabilityGroup);
      await Future<void>.delayed(Duration.zero);

      expect(glasses.payloads.last, groupsPayload);
    });

    test('yes and no commands invoke semantic screen actions', () async {
      int yesCalls = 0;
      int noCalls = 0;
      final WearFlowController controller = WearFlowController(
        glassesOutput: _FakeGlassesOutput(),
        navigationOutput: _FakeNavigationOutput(),
      );
      controller.setUiLifecycle(WearUiLifecycle.active);
      controller.enterScreen(WearScreenId.availabilityCheck);
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
      final WearFlowController controller = WearFlowController(
        glassesOutput: _FakeGlassesOutput(),
        navigationOutput: _FakeNavigationOutput(),
      );
      controller.setUiLifecycle(WearUiLifecycle.active);
      controller.registerScreenActions(
        WearScreenId.availabilityCheck,
        WearScreenActionHandler(onPhoto: () => photoCalls++),
      );

      controller.enterScreen(WearScreenId.menu);
      await controller.handleVoiceCommand(WearVoiceCommand.takePhoto);
      expect(photoCalls, 0);

      controller.enterScreen(WearScreenId.availabilityCheck);
      await controller.handleVoiceCommand(WearVoiceCommand.takePhoto);
      expect(photoCalls, 1);
    });

    test('yes command falls back to select when screen has no yes action',
        () async {
      int selectCalls = 0;
      final WearFlowController controller = WearFlowController(
        glassesOutput: _FakeGlassesOutput(),
        navigationOutput: _FakeNavigationOutput(),
      );
      controller.setUiLifecycle(WearUiLifecycle.active);
      controller.enterScreen(WearScreenId.availabilityCheck);
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
  });
}

class _BlockingNavigationOutput extends _FakeNavigationOutput {
  @override
  Future<void> goTo(WearScreenId screen, {Object? extra}) async {
    goToCalls.add(screen);
    await Future<void>.delayed(const Duration(seconds: 10));
  }
}

class _FakeGlassesOutput implements WearGlassesOutput {
  final List<WearGlassesPayload> payloads = <WearGlassesPayload>[];

  @override
  Future<void> send(WearGlassesPayload payload) async {
    payloads.add(payload);
  }
}

class _ThrowingGlassesOutput implements WearGlassesOutput {
  @override
  Future<void> send(WearGlassesPayload payload) async {
    throw StateError('glasses unavailable');
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
