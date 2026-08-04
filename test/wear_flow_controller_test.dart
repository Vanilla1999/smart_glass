import 'package:flutter_test/flutter_test.dart';
import 'package:smart_glasses/modules/wear/application/ports/wear_glasses_output.dart';
import 'package:smart_glasses/modules/wear/application/ports/wear_navigation_output.dart';
import 'package:smart_glasses/modules/wear/application/wear_flow_controller.dart';
import 'package:smart_glasses/modules/wear/application/wear_flow_state.dart';
import 'package:smart_glasses/modules/wear/application/wear_navigation_entry.dart';
import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/application/wear_ui_lifecycle.dart';
import 'package:smart_glasses/modules/wear/application/voice_clarification_args.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/voice_utterance_coordinator.dart';
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
      expect(controller.state.pendingNavigation, isNotNull);
      final int requestId = controller.state.pendingNavigation!.requestId;
      expect(
        controller.acknowledgeNavigation(
          requestId: requestId,
          screen: WearScreenId.help,
        ),
        isTrue,
      );
      expect(controller.state.pendingNavigation, isNull);
    });

    test('does not deliver a request again before its route acknowledgement',
        () async {
      final _FakeNavigationOutput navigation = _FakeNavigationOutput();
      final WearFlowController controller = WearFlowController(
        glassesOutput: _FakeGlassesOutput(),
        navigationOutput: navigation,
      );

      controller.setUiLifecycle(WearUiLifecycle.inactive);
      await controller.requestNavigation(WearScreenId.help);

      controller.setUiLifecycle(WearUiLifecycle.active);
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
      final WearFlowController controller = WearFlowController(
        glassesOutput: _FakeGlassesOutput(),
        navigationOutput: _FakeNavigationOutput(),
      );

      controller.setUiLifecycle(WearUiLifecycle.inactive);
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

    test(
        'controller commands do not invoke widget handlers while UI is inactive',
        () async {
      int upCalls = 0;
      int selectCalls = 0;
      final WearFlowController controller = WearFlowController(
        glassesOutput: _FakeGlassesOutput(),
        navigationOutput: _FakeNavigationOutput(),
      );
      controller.setUiLifecycle(WearUiLifecycle.inactive);
      controller.enterScreen(WearScreenId.printerSelect);
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
      final WearFlowController controller = WearFlowController(
        glassesOutput: _FakeGlassesOutput(),
        navigationOutput: _FakeNavigationOutput(),
      );
      controller.setUiLifecycle(WearUiLifecycle.active);
      controller.enterScreen(WearScreenId.menu);
      controller.setRuntimeActive(false);

      await controller.handleVoiceCommand(WearVoiceCommand.down);
      await controller.handleControllerCommand(WearVoiceCommand.down);

      expect(controller.state.menuFocusedIndex, 0);
    });

    test('voice commands remain blocked while UI is inactive', () async {
      int upCalls = 0;
      final WearFlowController controller = WearFlowController(
        glassesOutput: _FakeGlassesOutput(),
        navigationOutput: _FakeNavigationOutput(),
      );
      controller.setUiLifecycle(WearUiLifecycle.inactive);
      controller.enterScreen(WearScreenId.printerSelect);
      controller.registerScreenActions(
        WearScreenId.printerSelect,
        WearScreenActionHandler(onUp: () => upCalls++),
      );

      await controller.handleVoiceCommand(WearVoiceCommand.up);

      expect(upCalls, 0);
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

    test('direct-scan remembered hints become runtime grammar', () {
      final WearFlowController controller = WearFlowController(
        glassesOutput: _FakeGlassesOutput(),
        navigationOutput: _FakeNavigationOutput(),
      );

      controller.rememberScreenPayload(
        WearScreenId.availabilityDirectScan,
        const WearGlassesPayload(
          screenType: WearGlassesScreenType.productSelect,
          phase: WearGlassesPhase.idle,
          title: 'Выберите товар',
          items: <String>['Молоко Альфа'],
          voiceHints: <WearGlassesVoiceHint>[
            WearGlassesVoiceHint(
              itemId: '1',
              phrase: 'альфа',
              start: 7,
              end: 12,
            ),
          ],
        ),
      );

      expect(
        controller.voiceGrammarPhrasesFor(
          WearScreenId.availabilityDirectScan,
        ),
        <String>['альфа'],
      );
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

    test('exact product phrase wins over order-insensitive fuzzy ambiguity',
        () async {
      String? selectedItemId;
      const VoiceDynamicItemsSnapshot items = VoiceDynamicItemsSnapshot(
        revision: 77,
        items: <VoiceDynamicItem>[
          VoiceDynamicItem(
            id: 'exact',
            label: 'Чудо коктейль молочный',
          ),
          VoiceDynamicItem(
            id: 'reordered',
            label: 'Коктейль чудо молочный',
          ),
        ],
      );
      final WearFlowController controller = WearFlowController(
        glassesOutput: _FakeGlassesOutput(),
        navigationOutput: _FakeNavigationOutput(),
      );
      controller.setUiLifecycle(WearUiLifecycle.active);
      controller.enterScreen(WearScreenId.availabilityProduct);
      controller.registerScreenActions(
        WearScreenId.availabilityProduct,
        WearScreenActionHandler(
          dynamicVoiceItems: () => items,
          onDynamicItem: (String itemId) {
            selectedItemId = itemId;
          },
        ),
      );

      await controller.handleVoicePhrase('чудо коктейль молочный');

      expect(selectedItemId, 'exact');
      expect(controller.state.screen, WearScreenId.availabilityProduct);
      expect(controller.state.pendingNavigation, isNull);
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
      controller.setMenuFocusedIndex(0);
      await controller.handleVoiceCommand(WearVoiceCommand.select);
      final firstPending = controller.state.pendingNavigation;

      controller.setMenuFocusedIndex(1);
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

    test('back while inactive returns availability product to groups',
        () async {
      final _FakeNavigationOutput navigation = _FakeNavigationOutput();
      final WearFlowController controller = WearFlowController(
        glassesOutput: _FakeGlassesOutput(),
        navigationOutput: navigation,
      );

      controller.setUiLifecycle(WearUiLifecycle.inactive);
      controller.enterScreen(WearScreenId.availabilityProduct);
      await controller.handleVoiceCommand(WearVoiceCommand.back);

      expect(controller.state.screen, WearScreenId.availabilityGroup);
      expect(
        controller.state.pendingNavigation?.screen,
        WearScreenId.availabilityGroup,
      );
      expect(controller.state.pendingNavigation?.popCurrent, isTrue);

      controller.setUiLifecycle(WearUiLifecycle.active);
      await Future<void>.delayed(Duration.zero);

      expect(navigation.backCalls, 1);
    });

    test('back while inactive returns availability groups to interaction',
        () async {
      final WearFlowController controller = WearFlowController(
        glassesOutput: _FakeGlassesOutput(),
        navigationOutput: _FakeNavigationOutput(),
      );

      controller.setUiLifecycle(WearUiLifecycle.inactive);
      controller.enterScreen(WearScreenId.availabilityGroup);
      await controller.handleVoiceCommand(WearVoiceCommand.back);

      expect(controller.state.screen, WearScreenId.availabilityInteraction);
      expect(
        controller.state.pendingNavigation?.screen,
        WearScreenId.availabilityInteraction,
      );
      expect(controller.state.pendingNavigation?.popCurrent, isTrue);
    });

    test('inactive availability check back returns to product with extra',
        () async {
      final WearFlowController controller = WearFlowController(
        glassesOutput: _FakeGlassesOutput(),
        navigationOutput: _FakeNavigationOutput(),
      );
      final Object product = Object();
      controller.setUiLifecycle(WearUiLifecycle.inactive);
      controller.enterScreen(WearScreenId.availabilityProduct, extra: product);
      await controller.requestNavigation(
        WearScreenId.availabilityCheck,
        extra: Object(),
      );

      await controller.handleVoiceCommand(WearVoiceCommand.back);

      expect(controller.state.screen, WearScreenId.availabilityProduct);
      expect(controller.state.navigationHistory.last.extra, same(product));
    });

    test('back on menu is a no-op in both lifecycle states', () async {
      final _FakeNavigationOutput navigation = _FakeNavigationOutput();
      final WearFlowController controller = WearFlowController(
        glassesOutput: _FakeGlassesOutput(),
        navigationOutput: navigation,
      );
      controller.enterScreen(WearScreenId.menu);

      await controller.handleVoiceCommand(WearVoiceCommand.back);
      controller.setUiLifecycle(WearUiLifecycle.active);
      await controller.handleVoiceCommand(WearVoiceCommand.back);

      expect(navigation.backCalls, 0);
      expect(controller.state.pendingNavigation, isNull);
      expect(controller.state.navigationHistory, hasLength(1));
    });

    test('multiple inactive operations rebuild the complete navigation stack',
        () async {
      final _FakeNavigationOutput navigation = _FakeNavigationOutput();
      final WearFlowController controller = WearFlowController(
        glassesOutput: _FakeGlassesOutput(),
        navigationOutput: navigation,
      );
      final Object group = Object();
      controller.enterScreen(WearScreenId.menu);
      controller.setUiLifecycle(WearUiLifecycle.inactive);

      await controller.requestNavigation(WearScreenId.availabilityInteraction);
      await controller.requestNavigation(WearScreenId.availabilityGroup);
      await controller.requestNavigation(
        WearScreenId.availabilityProduct,
        extra: group,
      );
      await controller.handleVoiceCommand(WearVoiceCommand.back);
      controller.setUiLifecycle(WearUiLifecycle.active);
      await Future<void>.delayed(Duration.zero);

      expect(navigation.synchronizedHistories, hasLength(1));
      expect(
        navigation.synchronizedHistories.single
            .map((WearNavigationEntry entry) => entry.screen),
        <WearScreenId>[
          WearScreenId.menu,
          WearScreenId.availabilityInteraction,
          WearScreenId.availabilityGroup,
        ],
      );
    });

    test('runtime deactivation clears logical history and pending operation',
        () async {
      final WearFlowController controller = WearFlowController(
        glassesOutput: _FakeGlassesOutput(),
        navigationOutput: _FakeNavigationOutput(),
      );
      controller.enterScreen(WearScreenId.menu);
      await controller.requestNavigation(WearScreenId.help);

      controller.setRuntimeActive(false);

      expect(controller.state.screen, WearScreenId.scannerConnect);
      expect(controller.state.pendingNavigation, isNull);
      expect(controller.state.navigationHistory, hasLength(1));
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

    test('home on home confirm confirms navigation to menu', () async {
      final _FakeNavigationOutput navigation = _FakeNavigationOutput();
      final WearFlowController controller = WearFlowController(
        glassesOutput: _FakeGlassesOutput(),
        navigationOutput: navigation,
      );

      controller.setUiLifecycle(WearUiLifecycle.active);
      controller.enterScreen(WearScreenId.printerSelect);
      await controller.handleVoiceCommand(WearVoiceCommand.home);
      await controller.handleVoiceCommand(WearVoiceCommand.home);

      expect(controller.state.screen, WearScreenId.menu);
      expect(navigation.goToCalls, <WearScreenId>[WearScreenId.homeConfirm]);
      expect(navigation.replaceCalls, <WearScreenId>[WearScreenId.menu]);
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
      expect(navigation.replaceCalls, <WearScreenId>[WearScreenId.menu]);
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
      await controller.handleVoiceCommand(WearVoiceCommand.up);
      await controller.handleVoiceCommand(WearVoiceCommand.select);

      expect(controller.state.menuFocusedIndex, 1);
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
      controller.handleVoiceCommand(WearVoiceCommand.up);
      controller.handleVoiceCommand(WearVoiceCommand.select);

      await Future<void>.delayed(Duration.zero);

      expect(controller.state.menuFocusedIndex, 1);
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

    test('down at menu bottom stays at 3', () async {
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

      expect(controller.state.menuFocusedIndex, 3);
      expect(glasses.payloads.last.selectedIndex, 3);
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
          'Печать ценников',
          'Доступность',
          'Справка',
          'Настройки',
        ],
      );
    });

    test('menu item 0 select navigates to printerSelect', () async {
      final glasses = _FakeGlassesOutput();
      final nav = _FakeNavigationOutput();
      final controller = WearFlowController(
        glassesOutput: glasses,
        navigationOutput: nav,
      );
      controller.setUiLifecycle(WearUiLifecycle.active);
      controller.enterScreen(WearScreenId.menu);

      await controller.handleVoiceCommand(WearVoiceCommand.select);

      expect(controller.state.screen, WearScreenId.printerSelect);
      expect(glasses.payloads.last.screenType, WearGlassesScreenType.printer);
      expect(nav.goToCalls, <WearScreenId>[WearScreenId.printerSelect]);
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
      expect(controller.state.menuFocusedIndex, 0);
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
      expect(controller.state.menuFocusedIndex, 1);
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

    test('menu item 1 select navigates to availabilityInteraction', () async {
      final glasses = _FakeGlassesOutput();
      final nav = _FakeNavigationOutput();
      final controller = WearFlowController(
        glassesOutput: glasses,
        navigationOutput: nav,
      );
      controller.setUiLifecycle(WearUiLifecycle.active);
      controller.enterScreen(WearScreenId.menu);

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

    test('menu item 2 select navigates to help', () async {
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

      expect(controller.state.screen, WearScreenId.help);
      expect(glasses.payloads.last.screenType, WearGlassesScreenType.help);
      expect(nav.goToCalls, <WearScreenId>[WearScreenId.help]);
    });

    test('menu item 3 select navigates to settings', () async {
      final glasses = _FakeGlassesOutput();
      final nav = _FakeNavigationOutput();
      final controller = WearFlowController(
        glassesOutput: glasses,
        navigationOutput: nav,
      );
      controller.setUiLifecycle(WearUiLifecycle.active);
      controller.enterScreen(WearScreenId.menu);

      for (int i = 0; i < 3; i++) {
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

    test('back from help updates logical state before router acknowledgement',
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
      expect(controller.state.screen, WearScreenId.menu);

      // Simulate GoRouter pop → menu re-entry.
      controller.enterScreen(WearScreenId.menu);

      expect(glasses.payloads.last.screenType, WearGlassesScreenType.menu);
      expect(controller.state.screen, WearScreenId.menu);
    });

    test('back from scanIdle updates logical history without stale state',
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
      expect(controller.state.screen, WearScreenId.printerSelect);

      await controller.handleVoiceCommand(WearVoiceCommand.back);

      expect(nav.backCalls, 2);
      expect(controller.state.screen, WearScreenId.menu);
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
      controller.setMenuFocusedIndex(0);

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

    test('menu down does not await a blocking glasses render', () async {
      final _BlockingGlassesOutput glasses = _BlockingGlassesOutput();
      final WearFlowController controller = WearFlowController(
        glassesOutput: glasses,
        navigationOutput: _FakeNavigationOutput(),
      );

      controller.setUiLifecycle(WearUiLifecycle.active);
      controller.enterScreen(WearScreenId.menu);

      await controller.handleVoiceCommand(WearVoiceCommand.down);

      expect(controller.state.menuFocusedIndex, 1);
      expect(glasses.payloads.length, greaterThanOrEqualTo(1));
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

      expect(navigation.replaceCalls, <WearScreenId>[WearScreenId.menu]);
    });

    test('replace navigation preserves target screen and extra', () async {
      final _FakeNavigationOutput navigation = _FakeNavigationOutput();
      final WearFlowController controller = WearFlowController(
        glassesOutput: _FakeGlassesOutput(),
        navigationOutput: navigation,
      );
      final Object extra = Object();

      await controller.requestNavigation(
        WearScreenId.continueScan,
        extra: extra,
        replaceCurrent: true,
      );
      controller.setUiLifecycle(WearUiLifecycle.active);
      await Future<void>.delayed(Duration.zero);

      expect(
        navigation.replaceCalls,
        <WearScreenId>[WearScreenId.continueScan],
      );
      expect(navigation.replaceExtras, <Object?>[extra]);
      expect(navigation.homeCalls, 0);
    });

    test('replace to existing ancestor collapses logical history', () async {
      final WearFlowController controller = WearFlowController(
        glassesOutput: _FakeGlassesOutput(),
        navigationOutput: _FakeNavigationOutput(),
      );
      controller.enterScreen(WearScreenId.menu);
      controller.enterScreen(WearScreenId.printerSelect);
      controller.enterScreen(WearScreenId.scanIdle);

      await controller.requestNavigation(
        WearScreenId.printerSelect,
        replaceCurrent: true,
      );

      expect(
        controller.state.navigationHistory.map((entry) => entry.screen),
        <WearScreenId>[WearScreenId.menu, WearScreenId.printerSelect],
      );
    });

    test('non-poppable route observation replaces fabricated history', () {
      final WearFlowController controller = WearFlowController(
        glassesOutput: _FakeGlassesOutput(),
        navigationOutput: _FakeNavigationOutput(),
      );
      controller.enterScreen(WearScreenId.scanIdle);

      controller.observeRoute(
        WearScreenId.help,
        canPop: false,
      );

      expect(
        controller.state.navigationHistory.map((entry) => entry.screen),
        <WearScreenId>[WearScreenId.help],
      );
    });

    test('runtime reset emits cleared navigation state', () async {
      final WearFlowController controller = WearFlowController(
        glassesOutput: _FakeGlassesOutput(),
        navigationOutput: _FakeNavigationOutput(),
      );
      controller.enterScreen(WearScreenId.help);
      final Future<WearFlowState> reset = controller.stateStream.firstWhere(
        (state) => state.screen == WearScreenId.scannerConnect,
      );

      controller.setRuntimeActive(false);

      expect(
        (await reset).navigationHistory.map((entry) => entry.screen),
        <WearScreenId>[WearScreenId.scannerConnect],
      );
    });

    test('glasses failure does not block phone navigation', () async {
      final _FakeNavigationOutput navigation = _FakeNavigationOutput();
      final WearFlowController controller = WearFlowController(
        glassesOutput: _ThrowingGlassesOutput(),
        navigationOutput: navigation,
      );
      controller.setUiLifecycle(WearUiLifecycle.active);
      controller.enterScreen(WearScreenId.menu);
      controller.setMenuFocusedIndex(0);

      await controller.handleVoiceCommand(WearVoiceCommand.select);

      expect(controller.state.screen, WearScreenId.printerSelect);
      expect(navigation.goToCalls, <WearScreenId>[WearScreenId.printerSelect]);
    });

    test('active barcode is dispatched to the current screen handler',
        () async {
      final WearFlowController controller = WearFlowController(
        glassesOutput: _FakeGlassesOutput(),
        navigationOutput: _FakeNavigationOutput(),
      );
      String? received;
      controller.setUiLifecycle(WearUiLifecycle.active);
      controller.enterScreen(WearScreenId.scanIdle);
      controller.registerScreenActions(
        WearScreenId.scanIdle,
        WearScreenActionHandler(
          onBarcode: (String barcode) => received = barcode,
        ),
      );

      expect(await controller.handleBarcode('4600000000001'), isTrue);
      expect(received, '4600000000001');
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

    test('test photo command captures a photo on every screen', () async {
      var photoCaptures = 0;
      final WearFlowController controller = WearFlowController(
        glassesOutput: _FakeGlassesOutput(),
        navigationOutput: _FakeNavigationOutput(),
        photoCapture: () async => photoCaptures++,
      );
      controller.setUiLifecycle(WearUiLifecycle.active);

      controller.enterScreen(WearScreenId.menu);
      await controller.handleVoiceCommand(WearVoiceCommand.testPhoto);
      controller.enterScreen(WearScreenId.help);
      await controller.handleVoiceCommand(WearVoiceCommand.testPhoto);

      expect(photoCaptures, 2);
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
    test('opens clarification with only ambiguous dynamic matches', () async {
      final _FakeNavigationOutput navigation = _FakeNavigationOutput();
      final WearFlowController controller = WearFlowController(
        glassesOutput: _FakeGlassesOutput(),
        navigationOutput: navigation,
      );
      controller.setUiLifecycle(WearUiLifecycle.active);
      controller.enterScreen(WearScreenId.availabilityProduct);
      controller.registerScreenActions(
        WearScreenId.availabilityProduct,
        WearScreenActionHandler(
          dynamicVoiceItems: () => const VoiceDynamicItemsSnapshot(
            revision: 1,
            items: <VoiceDynamicItem>[
              VoiceDynamicItem(id: '1', label: 'Коровка из Кореновки пломбир'),
              VoiceDynamicItem(id: '2', label: 'Коровка из Кореновки стакан'),
              VoiceDynamicItem(id: '3', label: 'Другой товар'),
            ],
          ),
        ),
      );

      await controller.handleVoicePhrase('коровка из кореновки');

      expect(navigation.goToCalls, <WearScreenId>[
        WearScreenId.voiceClarification,
      ]);
      final VoiceClarificationArgs args =
          navigation.goToExtras.single! as VoiceClarificationArgs;
      expect(args.sourceScreen, WearScreenId.availabilityProduct);
      expect(args.matches.map((VoiceDynamicItem item) => item.id), <String>[
        '1',
        '2',
      ]);
    });

    test('clarification selection returns and invokes source item by id',
        () async {
      final _FakeNavigationOutput navigation = _FakeNavigationOutput();
      final WearFlowController controller = WearFlowController(
        glassesOutput: _FakeGlassesOutput(),
        navigationOutput: navigation,
      );
      String? selectedId;
      controller.setUiLifecycle(WearUiLifecycle.active);
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
      controller.enterScreen(WearScreenId.voiceClarification, extra: args);

      await controller.selectVoiceClarificationItem(args, '2');

      expect(navigation.backCalls, 1);
      expect(controller.state.screen, WearScreenId.availabilityProduct);
      expect(selectedId, '2');
    });

    test('does not leave clarification when selected item became stale',
        () async {
      final _FakeNavigationOutput navigation = _FakeNavigationOutput();
      final WearFlowController controller = WearFlowController(
        glassesOutput: _FakeGlassesOutput(),
        navigationOutput: navigation,
      );
      controller.setUiLifecycle(WearUiLifecycle.active);
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
      controller.enterScreen(WearScreenId.voiceClarification, extra: args);

      final bool selected =
          await controller.selectVoiceClarificationItem(args, '2');

      expect(selected, isFalse);
      expect(navigation.backCalls, 0);
      expect(controller.state.screen, WearScreenId.voiceClarification);
    });

    test('rejects clarification selection after source revision changes',
        () async {
      final _FakeNavigationOutput navigation = _FakeNavigationOutput();
      final WearFlowController controller = WearFlowController(
        glassesOutput: _FakeGlassesOutput(),
        navigationOutput: navigation,
      );
      controller.setUiLifecycle(WearUiLifecycle.active);
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
      controller.enterScreen(WearScreenId.voiceClarification, extra: args);

      final bool selected =
          await controller.selectVoiceClarificationItem(args, '1');

      expect(selected, isFalse);
      expect(navigation.backCalls, 0);
    });

    test('clarification grammar follows the visible candidate page', () async {
      final WearFlowController controller = WearFlowController(
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
      controller.enterScreen(WearScreenId.voiceClarification, extra: args);
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
      final WearFlowController controller = WearFlowController(
        glassesOutput: _FakeGlassesOutput(),
        navigationOutput: navigation,
      );
      int selectCalls = 0;
      controller.setUiLifecycle(WearUiLifecycle.active);
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
      controller.enterScreen(WearScreenId.voiceClarification, extra: args);

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

    test('keeps refined clarification after cancelling home confirmation', () {
      final WearFlowController controller = WearFlowController(
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
      controller.enterScreen(
        WearScreenId.voiceClarification,
        extra: refined,
      );
      controller.setVoiceClarificationFocusedIndex(1, 2);

      controller.enterScreen(WearScreenId.homeConfirm);
      controller.enterScreen(
        WearScreenId.voiceClarification,
        extra: root,
      );

      expect(controller.state.currentVoiceClarificationArgs, same(refined));
      expect(controller.state.voiceClarificationFocusedIndex, 1);
    });

    test('shows clarification notice without replacing matches', () async {
      final _FakeGlassesOutput glasses = _FakeGlassesOutput();
      final WearFlowController controller = WearFlowController(
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
      controller.enterScreen(WearScreenId.voiceClarification, extra: args);

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

    test('clears clarification arguments after leaving the flow', () {
      final WearFlowController controller = WearFlowController(
        glassesOutput: _FakeGlassesOutput(),
        navigationOutput: _FakeNavigationOutput(),
      );
      const VoiceClarificationArgs args = VoiceClarificationArgs(
        sourceScreen: WearScreenId.availabilityProduct,
        phrase: 'товар',
        sourceListRevision: 1,
        matches: <VoiceDynamicItem>[],
      );
      controller.enterScreen(WearScreenId.voiceClarification, extra: args);

      controller.enterScreen(WearScreenId.menu);

      expect(controller.state.currentVoiceClarificationArgs, isNull);
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
