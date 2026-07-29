import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_glasses/app/glasses/glasses_coordinator_cubit.dart';
import 'package:smart_glasses/core/constants/app_constants.dart';
import 'package:smart_glasses/core/services/method_channel_service.dart';
import 'package:smart_glasses/modules/wear/config/wear_session.dart';
import 'package:smart_glasses/modules/wear/data/bdto/data_source/bdto_datasource.dart';
import 'package:smart_glasses/modules/wear/domain/auth/model/authenticated_user.dart';
import 'package:smart_glasses/modules/wear/domain/price_tag_print/model/available_printer.dart';
import 'package:smart_glasses/modules/wear/domain/price_tag_print/use_case/get_available_printers_use_case.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/wear_voice_control_service.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/voice_command_parser_service.dart';
import 'package:smart_glasses/features/glasses/presentation/cubit/wear/wear_glasses_state.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_typing/speech_recognition_service.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_typing/voice_device_profile.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_typing/segmented_recognition_result.dart';
import 'package:smart_glasses/modules/wear/application/ports/wear_glasses_output.dart';
import 'package:smart_glasses/modules/wear/application/ports/wear_navigation_output.dart';
import 'package:smart_glasses/modules/wear/application/wear_flow_controller.dart';
import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/application/wear_ui_lifecycle.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/wear_voice_command.dart';
import 'package:smart_glasses/modules/wear/infrastructure/flutter_wear_glasses_output.dart';
import 'package:smart_glasses/modules/wear/infrastructure/flutter_wear_navigation_output.dart';
import 'package:smart_glasses/modules/wear/models/wear_printer.dart';
import 'package:smart_glasses/modules/wear/models/wear_printer_selection.dart';
import 'package:smart_glasses/modules/wear/presentation/glasses/wear_glasses_payload.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/main/wear_main_screen.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/printers/cubit/wear_printer_select_cubit.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/menu/wear_menu_screen.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/photo/wear_latest_photo_screen.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/printers/wear_printer_select_screen.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/scan/wear_product_select_screen.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/scan/wear_scan_idle_screen.dart';
import 'package:smart_glasses/modules/wear/presentation/widgets/wear_module_app.dart';
import 'package:smart_glasses/modules/wear/services/wear_status_icon_reporter.dart';
import 'package:smart_glasses/modules/wear/services/wear_wifi_status_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Bridges WearGlassesOutput → MethodChannel → GlassesCoordinatorCubit
/// simulating the real native bridge path.
class _CoordinatorBridgeOutput implements WearGlassesOutput {
  _CoordinatorBridgeOutput(this.channel);

  final MethodChannel channel;
  final List<WearGlassesPayload> sentPayloads = <WearGlassesPayload>[];

  @override
  Future<void> send(WearGlassesPayload payload) async {
    sentPayloads.add(payload);
    final Map<String, dynamic> json = payload.toJson();
    final ByteData encoded = channel.codec.encodeMethodCall(
      MethodCall('updateWearGlasses', json),
    );
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(channel.name, encoded, (ByteData? data) {});
  }
}

class _TestGlassesOutput implements WearGlassesOutput {
  final List<WearGlassesPayload> payloads = <WearGlassesPayload>[];

  @override
  Future<void> send(WearGlassesPayload payload) async {
    payloads.add(payload);
  }
}

Future<void> simulateIncomingMethodCall(
  MethodChannel channel,
  MethodCall call,
) {
  final ByteData encoded = channel.codec.encodeMethodCall(call);
  return TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(channel.name, encoded, (ByteData? data) {});
}

void main() {
  late MethodChannel channel;
  late MethodChannel appChannel;
  late _CoordinatorBridgeOutput bridgeOutput;
  late _FakeNavigationOutput navigation;
  late WearFlowController flowController;
  late GlassesCoordinatorCubit coordinator;
  late Map<String, dynamic> lastWearPayload;

  void testWearWidget(
    String description,
    Future<void> Function(WidgetTester tester) body,
  ) {
    testWidgets(description, (WidgetTester tester) async {
      try {
        await body(tester);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await WearStatusIconReporter.I.stop();
      }
    });
  }

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    dotenv.testLoad(fileInput: 'WEAR_GLASSES_ENABLED=false');

    channel = MethodChannel(AppConstants.glassesChannelName);
    appChannel = MethodChannel(AppConstants.appChannelName);
    bridgeOutput = _CoordinatorBridgeOutput(channel);
    navigation = _FakeNavigationOutput();
    lastWearPayload = <String, dynamic>{};

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      channel,
      (MethodCall methodCall) async {
        if (methodCall.method == 'getInitialCounter') {
          return 42;
        }
        return null;
      },
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      appChannel,
      (_) async => null,
    );

    flowController = WearFlowController(
      glassesOutput: bridgeOutput,
      navigationOutput: navigation,
    );

    coordinator = GlassesCoordinatorCubit(
      methodChannelService: MethodChannelService(),
      onNavigateToScreen: (String route) {},
      onNavigateHome: () {},
      onUpdateScreen1Counter: (int counter) {},
      onUpdateScreen1RecognizedText: (String text) {},
      onUpdateScreen2RecognizedText: (String text) {},
      onUpdateWearGlasses: (Map<String, dynamic> payload) {
        lastWearPayload = payload;
      },
    );
  });

  tearDown(() async {
    WearStatusIconReporter.I.endVoiceStartup();
    WearStatusIconReporter.I.debugSetCurrentScreenProviderForTesting(null);
    WearStatusIconReporter.I.debugSetRefreshForTesting(null);
    await WearStatusIconReporter.I.stop();
    coordinator.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(appChannel, null);
  });

  group('WearFlowController → GlassesCoordinatorCubit integration', () {
    test('enterScreen menu sends menu payload through coordinator', () async {
      await coordinator.init();

      flowController.setUiLifecycle(WearUiLifecycle.active);
      flowController.enterScreen(WearScreenId.menu);
      await Future<void>.delayed(Duration.zero);

      expect(lastWearPayload['screenType'], 'menu');
      expect(lastWearPayload['selectedIndex'], 0);
      expect(
        lastWearPayload['items'],
        <String>[
          'Печать ценников',
          'Доступность',
          'Справка',
          'Настройки',
        ],
      );
    });

    test('voice down propagates selectedIndex to coordinator', () async {
      await coordinator.init();

      flowController.setUiLifecycle(WearUiLifecycle.active);
      flowController.enterScreen(WearScreenId.menu);
      await Future<void>.delayed(Duration.zero);

      await flowController.handleVoiceCommand(WearVoiceCommand.down);

      expect(lastWearPayload['selectedIndex'], 1);
      expect(lastWearPayload['screenType'], 'menu');
    });

    test('menu select navigates to printer selection', () async {
      await coordinator.init();

      flowController.setUiLifecycle(WearUiLifecycle.active);
      flowController.enterScreen(WearScreenId.menu);
      await Future<void>.delayed(Duration.zero);

      await flowController.handleVoiceCommand(WearVoiceCommand.select);

      expect(flowController.state.screen, WearScreenId.printerSelect);
      expect(lastWearPayload['screenType'], 'printer');
    });

    test('menu item 1 select sends availability payload to coordinator',
        () async {
      await coordinator.init();

      flowController.setUiLifecycle(WearUiLifecycle.active);
      flowController.enterScreen(WearScreenId.menu);
      await Future<void>.delayed(Duration.zero);

      await flowController.handleVoiceCommand(WearVoiceCommand.down);
      await flowController.handleVoiceCommand(WearVoiceCommand.select);

      expect(flowController.state.screen, WearScreenId.availabilityInteraction);
      expect(lastWearPayload['screenType'], 'availability');
      expect(lastWearPayload['phase'], 'idle');
    });

    test('help screen sends help payload to coordinator', () async {
      await coordinator.init();

      flowController.setUiLifecycle(WearUiLifecycle.active);
      flowController.enterScreen(WearScreenId.menu);
      await Future<void>.delayed(Duration.zero);

      await flowController.handleVoiceCommand(WearVoiceCommand.down);
      await flowController.handleVoiceCommand(WearVoiceCommand.down);
      await flowController.handleVoiceCommand(WearVoiceCommand.select);

      expect(flowController.state.screen, WearScreenId.help);
      expect(lastWearPayload['screenType'], 'help');
      expect(lastWearPayload['phase'], 'idle');
      expect(lastWearPayload['title'], 'Справка');
    });

    test('settings screen sends status payload to coordinator', () async {
      await coordinator.init();

      flowController.setUiLifecycle(WearUiLifecycle.active);
      flowController.enterScreen(WearScreenId.menu);
      await Future<void>.delayed(Duration.zero);

      for (int i = 0; i < 3; i++) {
        await flowController.handleVoiceCommand(WearVoiceCommand.down);
      }
      await flowController.handleVoiceCommand(WearVoiceCommand.select);

      expect(flowController.state.screen, WearScreenId.settings);
      expect(lastWearPayload['screenType'], 'status');
      expect(lastWearPayload['title'], 'Настройки');
    });

    test(
        'WearGlassesState.fromPayload produces correct state from bridge output',
        () async {
      flowController.setUiLifecycle(WearUiLifecycle.active);
      flowController.enterScreen(WearScreenId.menu);
      await Future<void>.delayed(Duration.zero);

      await flowController.handleVoiceCommand(WearVoiceCommand.down);

      final WearGlassesState glassesState =
          WearGlassesState.fromPayload(lastWearPayload);

      expect(glassesState.screenType, WearGlassesScreenType.menu);
      expect(glassesState.selectedIndex, 1);
      expect(glassesState.title, 'Выбор раздела');
      expect(
        glassesState.items,
        <String>[
          'Печать ценников',
          'Доступность',
          'Справка',
          'Настройки',
        ],
      );
      expect(glassesState.phase, WearGlassesPhase.idle);
    });

    test('rapid up/down commands keep coordinator in sync with controller',
        () async {
      await coordinator.init();

      flowController.setUiLifecycle(WearUiLifecycle.active);
      flowController.enterScreen(WearScreenId.menu);
      await Future<void>.delayed(Duration.zero);

      await flowController.handleVoiceCommand(WearVoiceCommand.down);
      await flowController.handleVoiceCommand(WearVoiceCommand.down);
      await flowController.handleVoiceCommand(WearVoiceCommand.down);
      await flowController.handleVoiceCommand(WearVoiceCommand.up);

      final WearGlassesState glassesState =
          WearGlassesState.fromPayload(lastWearPayload);

      expect(glassesState.selectedIndex, 2);
      expect(flowController.state.menuFocusedIndex, 2);
    });

    test('back from help sends menu payload to coordinator', () async {
      await coordinator.init();

      flowController.setUiLifecycle(WearUiLifecycle.active);
      flowController.enterScreen(WearScreenId.help);
      await Future<void>.delayed(Duration.zero);

      await flowController.handleVoiceCommand(WearVoiceCommand.back);

      // Simulate GoRouter pop → menu re-entry
      flowController.enterScreen(WearScreenId.menu);
      await Future<void>.delayed(Duration.zero);

      final WearGlassesState glassesState =
          WearGlassesState.fromPayload(lastWearPayload);

      expect(glassesState.screenType, WearGlassesScreenType.menu);
      expect(glassesState.selectedIndex, 0);
    });

    test('full voice flow: start → menu → navigate → verify coordinator state',
        () async {
      await coordinator.init();

      flowController.setUiLifecycle(WearUiLifecycle.active);
      flowController.enterScreen(WearScreenId.menu);
      await Future<void>.delayed(Duration.zero);

      // down to index 1 (Доступность)
      await flowController.handleVoiceCommand(WearVoiceCommand.down);
      // select → availability
      await flowController.handleVoiceCommand(WearVoiceCommand.select);

      WearGlassesState glassesState =
          WearGlassesState.fromPayload(lastWearPayload);
      expect(glassesState.screenType, WearGlassesScreenType.availability);
      expect(flowController.state.screen, WearScreenId.availabilityInteraction);

      // back to menu
      await flowController.handleVoiceCommand(WearVoiceCommand.back);
      flowController.enterScreen(WearScreenId.menu);
      await Future<void>.delayed(Duration.zero);

      glassesState = WearGlassesState.fromPayload(lastWearPayload);
      expect(glassesState.screenType, WearGlassesScreenType.menu);
      expect(glassesState.selectedIndex, 1);
      expect(flowController.state.menuFocusedIndex, 1);
    });

    test('fast direct-scan alias navigates before the segment closes',
        () async {
      final _FakeSpeechRecognitionService speech =
          _FakeSpeechRecognitionService();
      final WearVoiceControlService voiceControl = WearVoiceControlService(
        speechRecognitionService: speech,
        screenProvider: () => flowController.state.screen,
      );
      addTearDown(voiceControl.dispose);
      addTearDown(speech.dispose);
      voiceControl.commandStream.listen(flowController.handleVoiceCommand);

      flowController.setUiLifecycle(WearUiLifecycle.active);
      flowController.enterScreen(WearScreenId.availabilityInteraction);
      await Future<void>.delayed(Duration.zero);

      speech.emitCommandPartial('прямое');
      await Future<void>.delayed(Duration.zero);

      expect(flowController.state.screen, WearScreenId.availabilityDirectScan);

      speech.emitCommandResult('прямое сканирование');
      speech.endSegment();
      await Future<void>.delayed(Duration.zero);

      expect(flowController.state.screen, WearScreenId.availabilityDirectScan);
    });
  });

  group('WearModuleApp router integration', () {
    test('latest photo route is not mapped to the glasses flow', () {
      expect(
        FlutterWearNavigationOutput.screenIdForRoute(
          WearLatestPhotoScreen.route,
        ),
        isNull,
      );
    });

    setUp(() async {
      await WearStatusIconReporter.I.stop();
      WearStatusIconReporter.I.debugSetCurrentScreenProviderForTesting(
        () => WearScreenId.menu,
      );
      WearStatusIconReporter.I.debugSetRefreshForTesting(
        () async => const WearStatusIconSnapshot(
          wifi: WearWifiStatus(isAvailable: true, level: 3),
          showPrinter: false,
          printerAvailable: false,
        ),
      );
    });

    setUp(() {
      dotenv.testLoad(
        fileInput: '''
WEAR_GLASSES_ENABLED=false
WEAR_SKIP_SCANNER_CONNECT_SCREEN=true
''',
      );
      WearSession.setUser(AuthenticatedUser(
        idUser: 1,
        idEmployee: 1,
        name: 'Test User',
      ));
    });

    tearDown(() {
      WearSession.clear();
    });

    testWearWidget('pop from scanIdle syncs flow state back to printerSelect',
        (WidgetTester tester) async {
      GoRouter? router;
      final WearFlowController routerFlow = WearFlowController(
        glassesOutput: _TestGlassesOutput(),
        navigationOutput: _FakeNavigationOutput(),
      );
      await tester.pumpWidget(
        WearModuleApp(
          flowController: routerFlow,
          voiceCommandStream: const Stream<WearVoiceCommand>.empty(),
          routes: _testRoutes,
          initialLocation: WearMenuScreen.route,
          onStartVoice: () async {},
          onStopVoice: () async {},
          onRestartVoice: (_) async {},
          onRouterReady: (GoRouter value) => router = value,
        ),
      );
      await tester.pumpAndSettle();

      router!.go(WearMenuScreen.route);
      await tester.pumpAndSettle();
      router!.push(WearPrinterSelectScreen.route);
      await tester.pumpAndSettle();
      router!.push(WearScanIdleScreen.route, extra: _printerSelection());
      await tester.pumpAndSettle();

      expect(
        routerFlow.state.screen,
        WearScreenId.scanIdle,
      );

      router!.pop();
      await tester.pumpAndSettle();

      expect(
        routerFlow.state.screen,
        WearScreenId.printerSelect,
      );
    });

    testWearWidget(
        'controller navigation clears pending request after matching route ack',
        (WidgetTester tester) async {
      GoRouter? router;
      final WearFlowController routerFlow = WearFlowController(
        glassesOutput: _TestGlassesOutput(),
        navigationOutput: _FakeNavigationOutput(),
      );
      await tester.pumpWidget(
        WearModuleApp(
          flowController: routerFlow,
          voiceCommandStream: const Stream<WearVoiceCommand>.empty(),
          routes: _testRoutes,
          initialLocation: WearMenuScreen.route,
          onStartVoice: () async {},
          onStopVoice: () async {},
          onRestartVoice: (_) async {},
          onRouterReady: (GoRouter value) => router = value,
        ),
      );
      await tester.pumpAndSettle();

      await routerFlow.requestNavigation(WearScreenId.help);
      await tester.pumpAndSettle();

      expect(router!.state.matchedLocation, '/wear_help');
      expect(routerFlow.state.screen, WearScreenId.help);
      expect(routerFlow.state.pendingNavigation, isNull);
    });

    testWearWidget('pop to scanIdle keeps route extra in flow state',
        (WidgetTester tester) async {
      final WearPrinterSelection selection = _printerSelection();
      GoRouter? router;
      final WearFlowController routerFlow = WearFlowController(
        glassesOutput: _TestGlassesOutput(),
        navigationOutput: _FakeNavigationOutput(),
      );
      await tester.pumpWidget(
        WearModuleApp(
          flowController: routerFlow,
          voiceCommandStream: const Stream<WearVoiceCommand>.empty(),
          routes: _testRoutes,
          initialLocation: WearMenuScreen.route,
          onStartVoice: () async {},
          onStopVoice: () async {},
          onRestartVoice: (_) async {},
          onRouterReady: (GoRouter value) => router = value,
        ),
      );
      await tester.pumpAndSettle();

      router!.go(WearMenuScreen.route);
      await tester.pumpAndSettle();
      router!.push(WearScanIdleScreen.route, extra: selection);
      await tester.pumpAndSettle();
      router!.push(WearProductSelectScreen.route);
      await tester.pumpAndSettle();

      router!.pop();
      await tester.pumpAndSettle();

      expect(routerFlow.state.screen, WearScreenId.scanIdle);
      expect(
        routerFlow.state.currentPrinterSelection,
        same(selection),
      );
    });

    testWearWidget(
        'voice stream command is routed through WearModuleApp to flow',
        (WidgetTester tester) async {
      final StreamController<WearVoiceCommand> voiceCommands =
          StreamController<WearVoiceCommand>.broadcast();
      addTearDown(voiceCommands.close);
      GoRouter? router;
      final WearFlowController routerFlow = WearFlowController(
        glassesOutput: _TestGlassesOutput(),
        navigationOutput: _FakeNavigationOutput(),
      );
      await tester.pumpWidget(
        WearModuleApp(
          flowController: routerFlow,
          voiceCommandStream: voiceCommands.stream,
          routes: _testRoutes,
          initialLocation: WearMenuScreen.route,
          onStartVoice: () async {},
          onStopVoice: () async {},
          onRestartVoice: (_) async {},
          onRouterReady: (GoRouter value) => router = value,
        ),
      );
      await tester.pumpAndSettle();

      router!.go(WearMenuScreen.route);
      await tester.pumpAndSettle();
      expect(routerFlow.state.screen, WearScreenId.menu);

      voiceCommands.add(WearVoiceCommand.down);
      await tester.pumpAndSettle();

      expect(routerFlow.state.menuFocusedIndex, 1);
    });

    testWearWidget(
        'microphone pause suppresses commands and phrases until resumed',
        (WidgetTester tester) async {
      final StreamController<WearVoiceCommand> voiceCommands =
          StreamController<WearVoiceCommand>.broadcast();
      final StreamController<String> voicePhrases =
          StreamController<String>.broadcast();
      addTearDown(voiceCommands.close);
      addTearDown(voicePhrases.close);
      final WearFlowController routerFlow = WearFlowController(
        glassesOutput: _TestGlassesOutput(),
        navigationOutput: _FakeNavigationOutput(),
      );
      var phraseCalls = 0;

      await tester.pumpWidget(
        WearModuleApp(
          flowController: routerFlow,
          voiceCommandStream: voiceCommands.stream,
          voicePhraseStream: voicePhrases.stream,
          routes: _testRoutes,
          initialLocation: WearMenuScreen.route,
          onStartVoice: () async {},
          onStopVoice: () async {},
          onRestartVoice: (_) async {},
        ),
      );
      await tester.pumpAndSettle();
      routerFlow.registerScreenActions(
        WearScreenId.menu,
        WearScreenActionHandler(onPhrase: (String phrase) => phraseCalls++),
      );

      voiceCommands.add(WearVoiceCommand.stopMicrophone);
      await tester.pumpAndSettle();
      expect(WearStatusIconReporter.I.voiceCommandsEnabled.value, isFalse);

      voiceCommands.add(WearVoiceCommand.down);
      voicePhrases.add('безалкогольное');
      await tester.pumpAndSettle();
      expect(routerFlow.state.menuFocusedIndex, 0);
      expect(phraseCalls, 0);

      voiceCommands.add(WearVoiceCommand.startMicrophone);
      await tester.pumpAndSettle();
      expect(WearStatusIconReporter.I.voiceCommandsEnabled.value, isTrue);

      voiceCommands.add(WearVoiceCommand.down);
      voicePhrases.add('безалкогольное');
      await tester.pumpAndSettle();
      expect(routerFlow.state.menuFocusedIndex, 1);
      expect(phraseCalls, 1);
    });

    testWearWidget('final voice phrase invokes the committed flow action',
        (WidgetTester tester) async {
      final StreamController<String> voicePhrases =
          StreamController<String>.broadcast();
      addTearDown(voicePhrases.close);
      final WearFlowController routerFlow = WearFlowController(
        glassesOutput: _TestGlassesOutput(),
        navigationOutput: _FakeNavigationOutput(),
      );

      await tester.pumpWidget(
        WearModuleApp(
          flowController: routerFlow,
          voiceCommandStream: const Stream<WearVoiceCommand>.empty(),
          voicePhraseStream: voicePhrases.stream,
          routes: _testRoutes,
          initialLocation: WearMenuScreen.route,
          onStartVoice: () async {},
          onStopVoice: () async {},
          onRestartVoice: (_) async {},
        ),
      );
      await tester.pumpAndSettle();

      var partialCalls = 0;
      var finalCalls = 0;
      routerFlow.registerScreenActions(
        WearScreenId.menu,
        WearScreenActionHandler(
          onPartialPhrase: (String phrase) {
            partialCalls++;
            return true;
          },
          onPhrase: (String phrase) {
            finalCalls++;
          },
        ),
      );

      voicePhrases.add('безалкогольное');
      await tester.pumpAndSettle();

      expect(partialCalls, 0);
      expect(finalCalls, 1);
    });

    testWearWidget('voice starts immediately when authorization completes',
        (WidgetTester tester) async {
      WearSession.clear();
      int startVoiceCalls = 0;
      int stopVoiceCalls = 0;
      final WearFlowController routerFlow = WearFlowController(
        glassesOutput: _TestGlassesOutput(),
        navigationOutput: _FakeNavigationOutput(),
      );

      await tester.pumpWidget(
        WearModuleApp(
          flowController: routerFlow,
          voiceCommandStream: const Stream<WearVoiceCommand>.empty(),
          routes: _testRoutes,
          initialLocation: WearMainScreen.route,
          onStartVoice: () async {
            startVoiceCalls++;
          },
          onStopVoice: () async {
            stopVoiceCalls++;
          },
          onRestartVoice: (_) async {},
        ),
      );
      await tester.pumpAndSettle();
      expect(startVoiceCalls, 0);

      WearSession.setUser(AuthenticatedUser(
        idUser: 2,
        idEmployee: 2,
        name: 'Authorized User',
      ));
      await tester.pumpAndSettle();

      expect(startVoiceCalls, 1);

      WearSession.clear();
      await tester.pump();

      expect(stopVoiceCalls, 1);
    });

    testWearWidget('voice startup loader stays until voice start completes',
        (WidgetTester tester) async {
      WearSession.clear();
      final Completer<void> startVoiceCompleter = Completer<void>();
      final WearFlowController routerFlow = WearFlowController(
        glassesOutput: FlutterWearGlassesOutput(),
        navigationOutput: _FakeNavigationOutput(),
      );

      await tester.pumpWidget(
        WearModuleApp(
          flowController: routerFlow,
          voiceCommandStream: const Stream<WearVoiceCommand>.empty(),
          routes: _testRoutes,
          initialLocation: WearMainScreen.route,
          onStartVoice: () => startVoiceCompleter.future,
          onStopVoice: () async {},
          onRestartVoice: (_) async {},
        ),
      );
      await tester.pumpAndSettle();

      WearSession.setUser(AuthenticatedUser(
        idUser: 2,
        idEmployee: 2,
        name: 'Authorized User',
      ));
      await tester.pump();
      await tester.pump();

      expect(find.text('Подготовка голосового\nуправления'), findsOneWidget);

      startVoiceCompleter.complete();
      await tester.pump();

      expect(find.text('Подготовка голосового\nуправления'), findsNothing);
    });

    testWearWidget('voice startup loader adds no delay after voice is ready',
        (WidgetTester tester) async {
      WearSession.clear();
      final WearFlowController routerFlow = WearFlowController(
        glassesOutput: _TestGlassesOutput(),
        navigationOutput: _FakeNavigationOutput(),
      );

      await tester.pumpWidget(
        WearModuleApp(
          flowController: routerFlow,
          voiceCommandStream: const Stream<WearVoiceCommand>.empty(),
          routes: _testRoutes,
          initialLocation: WearMainScreen.route,
          onStartVoice: () async {},
          onStopVoice: () async {},
          onRestartVoice: (_) async {},
        ),
      );
      await tester.pumpAndSettle();

      WearSession.setUser(AuthenticatedUser(
        idUser: 2,
        idEmployee: 2,
        name: 'Authorized User',
      ));
      await tester.pump();
      await tester.pump();
      expect(find.text('Подготовка голосового\nуправления'), findsNothing);
    });

    testWearWidget(
        'voice startup success does not overwrite current glasses screen',
        (WidgetTester tester) async {
      WearSession.clear();
      final Completer<void> startVoiceCompleter = Completer<void>();
      final _TestGlassesOutput glassesOutput = _TestGlassesOutput();
      final WearFlowController routerFlow = WearFlowController(
        glassesOutput: glassesOutput,
        navigationOutput: _FakeNavigationOutput(),
      );

      await tester.pumpWidget(
        WearModuleApp(
          flowController: routerFlow,
          voiceCommandStream: const Stream<WearVoiceCommand>.empty(),
          routes: _testRoutes,
          initialLocation: WearMainScreen.route,
          onStartVoice: () => startVoiceCompleter.future,
          onStopVoice: () async {},
          onRestartVoice: (_) async {},
        ),
      );
      await tester.pumpAndSettle();

      WearSession.setUser(AuthenticatedUser(
        idUser: 2,
        idEmployee: 2,
        name: 'Authorized User',
      ));
      await tester.pump();
      routerFlow.enterScreen(WearScreenId.menu);
      await tester.pump();

      expect(
          glassesOutput.payloads.last.screenType, WearGlassesScreenType.menu);

      startVoiceCompleter.complete();
      await tester.pumpAndSettle();

      expect(
          glassesOutput.payloads.last.screenType, WearGlassesScreenType.menu);
      expect(glassesOutput.payloads.last.title, 'Выбор раздела');
    });

    test('wear payload continues updating during voice startup overlay',
        () async {
      WearStatusIconReporter.I.beginVoiceStartup();
      addTearDown(WearStatusIconReporter.I.endVoiceStartup);

      await WearStatusIconReporter.I.sendFast(
        WearGlassesPayload.loading(
          screenType: WearGlassesScreenType.status,
          title: 'Голосовое управление',
          statusText: 'Запускаем голос...',
          subtitle: 'Пожалуйста, подождите',
        ),
      );

      expect(
        WearStatusIconReporter.I.lastPayload?.title,
        'Голосовое управление',
      );

      await WearStatusIconReporter.I.send(
        WearGlassesPayload.status(
          isError: false,
          title: 'Вошли как',
          subtitle: 'Колиус',
          statusText: 'Успешно',
        ),
      );
      await WearStatusIconReporter.I.sendFast(WearGlassesPayload.menu());

      expect(WearStatusIconReporter.I.lastPayload?.title, 'Выбор раздела');

      WearStatusIconReporter.I.endVoiceStartup();
      await WearStatusIconReporter.I.sendFast(WearGlassesPayload.menu());

      expect(WearStatusIconReporter.I.lastPayload?.title, 'Выбор раздела');
    });

    test('startup tokens do not block ordinary wear payload updates', () async {
      final int oldStartup = WearStatusIconReporter.I.beginVoiceStartup();
      final int currentStartup = WearStatusIconReporter.I.beginVoiceStartup();
      await WearStatusIconReporter.I.sendFast(
        WearGlassesPayload.loading(
          screenType: WearGlassesScreenType.status,
          title: 'Голосовое управление',
          statusText: 'Запускаем голос...',
        ),
      );

      WearStatusIconReporter.I.endVoiceStartup(oldStartup);
      await WearStatusIconReporter.I.sendFast(WearGlassesPayload.menu());

      expect(WearStatusIconReporter.I.lastPayload?.title, 'Выбор раздела');
      WearStatusIconReporter.I.endVoiceStartup(currentStartup);
    });

    test(
        'sendFastForScreen drops stale product payload after check becomes current',
        () async {
      WearStatusIconReporter.I.debugSetCurrentScreenProviderForTesting(
        () => WearScreenId.availabilityCheck,
      );
      addTearDown(
        () => WearStatusIconReporter.I.debugSetCurrentScreenProviderForTesting(
          null,
        ),
      );

      await WearStatusIconReporter.I.sendFastForScreen(
        WearScreenId.availabilityProduct,
        WearGlassesPayload.loading(
          screenType: WearGlassesScreenType.availability,
          title: 'Товарная позиция',
          statusText: 'Устаревший список',
        ),
      );
      await WearStatusIconReporter.I.sendFastForScreen(
        WearScreenId.availabilityCheck,
        const WearGlassesPayload(
          screenType: WearGlassesScreenType.availability,
          phase: WearGlassesPhase.idle,
          title: 'Товар есть на полке?',
          subtitle: 'Товар\nЦена: 99,90 ₽',
          primaryAction: 'Да',
          secondaryAction: 'Нет',
        ),
      );

      expect(
          WearStatusIconReporter.I.lastPayload?.title, 'Товар есть на полке?');
    });

    test('transient feedback does not restore an older payload', () async {
      WearStatusIconReporter.I.debugSetCurrentScreenProviderForTesting(
        () => WearScreenId.menu,
      );
      await WearStatusIconReporter.I.sendFastForScreen(
        WearScreenId.menu,
        WearGlassesPayload.menu(selectedIndex: 0),
      );
      await WearStatusIconReporter.I.showTransientFastForScreen(
        WearScreenId.menu,
        WearGlassesPayload.status(
          isError: true,
          title: 'Голосовой выбор',
          statusText: 'Не найдено',
        ),
        duration: const Duration(milliseconds: 10),
      );
      await WearStatusIconReporter.I.sendFastForScreen(
        WearScreenId.menu,
        WearGlassesPayload.menu(selectedIndex: 2),
      );

      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(WearStatusIconReporter.I.lastPayload?.selectedIndex, 2);
      expect(WearStatusIconReporter.I.lastPayload?.title, 'Выбор раздела');
    });

    test('new fast payload supersedes delayed refresh and reopens projection',
        () async {
      dotenv.testLoad(fileInput: 'WEAR_GLASSES_ENABLED=true');
      final List<MethodCall> calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(appChannel, (MethodCall call) async {
        calls.add(call);
        return true;
      });
      await WearStatusIconReporter.I.stop();
      calls.clear();

      final Completer<WearStatusIconSnapshot> refresh =
          Completer<WearStatusIconSnapshot>();
      WearStatusIconReporter.I.debugSetRefreshForTesting(() => refresh.future);
      final Future<void> staleSend = WearStatusIconReporter.I.send(
        WearGlassesPayload.status(
          isError: false,
          title: 'Старый payload',
          statusText: 'Ожидание',
        ),
      );
      await Future<void>.delayed(Duration.zero);

      await WearStatusIconReporter.I.sendFast(WearGlassesPayload.menu());
      refresh.complete(
        const WearStatusIconSnapshot(
          wifi: WearWifiStatus(isAvailable: true, level: 3),
          showPrinter: false,
          printerAvailable: false,
        ),
      );
      await staleSend;

      final List<MethodCall> projectionCalls = calls.where((MethodCall call) {
        return call.method == 'showWearGlasses' ||
            call.method == 'updateWearGlasses';
      }).toList(growable: false);
      expect(projectionCalls, hasLength(1));
      expect(projectionCalls.single.method, 'showWearGlasses');
      expect(
        (projectionCalls.single.arguments as Map<Object?, Object?>)['title'],
        'Выбор раздела',
      );
      expect(WearStatusIconReporter.I.lastPayload?.title, 'Выбор раздела');
    });

    testWearWidget('direction ASR alias executes before its segment final',
        (WidgetTester tester) async {
      final _FakeSpeechRecognitionService speech =
          _FakeSpeechRecognitionService();
      final WearVoiceControlService voiceControl = WearVoiceControlService(
        speechRecognitionService: speech,
        clock: () => 1000,
      );
      addTearDown(voiceControl.dispose);
      addTearDown(speech.dispose);
      final WearFlowController routerFlow = WearFlowController(
        glassesOutput: _TestGlassesOutput(),
        navigationOutput: _FakeNavigationOutput(),
      );

      await tester.pumpWidget(
        WearModuleApp(
          flowController: routerFlow,
          voiceCommandStream: voiceControl.commandStream,
          routes: _testRoutes,
          initialLocation: WearMenuScreen.route,
          onStartVoice: () async {},
          onStopVoice: () async {},
          onRestartVoice: (_) async {},
        ),
      );
      await tester.pumpAndSettle();
      expect(routerFlow.state.screen, WearScreenId.menu);

      speech.emitCommandPartial('вниз');
      await tester.pumpAndSettle();

      expect(routerFlow.state.menuFocusedIndex, 1);

      speech.emitCommandResult('вниз');
      speech.endSegment();
      await tester.pumpAndSettle();

      expect(routerFlow.state.menuFocusedIndex, 1);
    });

    testWearWidget('injected resume recovery receives lifecycle reason',
        (WidgetTester tester) async {
      WearSession.setUser(AuthenticatedUser(
        idUser: 1,
        idEmployee: 1,
        name: 'Test User',
      ));
      addTearDown(WearSession.clear);
      String? restartReason;

      await tester.pumpWidget(
        WearModuleApp(
          flowController: WearFlowController(
            glassesOutput: _TestGlassesOutput(),
            navigationOutput: _FakeNavigationOutput(),
          ),
          routes: _testRoutes,
          initialLocation: WearMenuScreen.route,
          onStartVoice: () async {},
          onStopVoice: () async {},
          onRestartVoice: (String reason) async {
            restartReason = reason;
          },
        ),
      );
      await tester.pumpAndSettle();

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();

      expect(restartReason, 'app_lifecycle_resumed');
    });

    testWearWidget('shows voice reconnection overlay without changing route',
        (WidgetTester tester) async {
      WearSession.setUser(AuthenticatedUser(
        idUser: 1,
        idEmployee: 1,
        name: 'Test User',
      ));
      addTearDown(WearSession.clear);
      final StreamController<bool> reconnecting =
          StreamController<bool>.broadcast(sync: true);
      addTearDown(reconnecting.close);
      final StreamController<String?> reconnectErrors =
          StreamController<String?>.broadcast(sync: true);
      addTearDown(reconnectErrors.close);
      final StreamController<WearVoiceCommand> commands =
          StreamController<WearVoiceCommand>.broadcast(sync: true);
      addTearDown(commands.close);
      final WearFlowController flow = WearFlowController(
        glassesOutput: _TestGlassesOutput(),
        navigationOutput: _FakeNavigationOutput(),
      );
      GoRouter? router;

      await tester.pumpWidget(
        WearModuleApp(
          flowController: flow,
          routes: _testRoutes,
          initialLocation: WearMenuScreen.route,
          voiceCommandStream: commands.stream,
          onStartVoice: () async {},
          onStopVoice: () async {},
          onRestartVoice: (_) async {},
          voiceReconnectingStream: reconnecting.stream,
          voiceReconnectErrorStream: reconnectErrors.stream,
          onRouterReady: (GoRouter value) => router = value,
        ),
      );
      await tester.pumpAndSettle();

      reconnecting.add(true);
      await tester.pump();

      expect(
        find.text('Переподключаем голосовое\nуправление'),
        findsOneWidget,
      );
      expect(router?.state.matchedLocation, WearMenuScreen.route);

      commands.add(WearVoiceCommand.down);
      await tester.pump();

      expect(flow.state.menuFocusedIndex, 0);

      reconnecting.add(false);
      await tester.pump();

      expect(
        find.text('Переподключаем голосовое\nуправление'),
        findsNothing,
      );

      reconnectErrors.add('Голосовое управление недоступно');
      await tester.pump();

      expect(find.text('Голосовое управление недоступно'), findsOneWidget);

      reconnectErrors.add(null);
      await tester.pump();

      commands.add(WearVoiceCommand.down);
      await tester.pump();

      expect(flow.state.menuFocusedIndex, 1);
    });
  });

  group('WearPrinterSelectScreen widget integration', () {
    setUp(() {
      dotenv.testLoad(
        fileInput: 'WEAR_GLASSES_ENABLED=false\nWEAR_USE_MOCKS=true',
      );
      WearSession.setUser(AuthenticatedUser(
        idUser: 1,
        idEmployee: 1,
        name: 'Test User',
      ));
    });

    tearDown(() {
      WearSession.clear();
    });

    testWearWidget(
        're-selecting already selected yellow printer pushes scanIdle once with selection extra',
        (WidgetTester tester) async {
      GoRouter? router;
      Object? pushedExtra;
      int scanIdleBuilds = 0;
      final WearFlowController printerFlow = WearFlowController(
        glassesOutput: _TestGlassesOutput(),
        navigationOutput: _FakeNavigationOutput(),
      )..setUiLifecycle(WearUiLifecycle.active);
      final List<RouteBase> routes = <RouteBase>[
        GoRoute(
          path: WearPrinterSelectScreen.route,
          builder: (_, __) => WearPrinterSelectScreen(
            flowController: printerFlow,
          ),
        ),
        GoRoute(
          path: WearScanIdleScreen.route,
          builder: (_, GoRouterState state) {
            scanIdleBuilds++;
            pushedExtra = state.extra;
            return const SizedBox(key: Key('scanIdle'));
          },
        ),
      ];
      router = GoRouter(
        initialLocation: WearPrinterSelectScreen.route,
        routes: routes,
      );
      addTearDown(router.dispose);
      WearStatusIconReporter.I.debugSetCurrentScreenProviderForTesting(
        () => WearScreenId.printerSelect,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            wearPrinterSelectNotifierProvider.overrideWith(
              (ref) => _PresetPrinterSelectNotifier(),
            ),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      expect(router.state.matchedLocation, WearPrinterSelectScreen.route);
      expect(find.text('Yellow'), findsOneWidget);

      await printerFlow.handleVoiceCommand(
        WearVoiceCommand.select,
      );
      await tester.pumpAndSettle();

      expect(router.state.matchedLocation, WearScanIdleScreen.route);
      expect(scanIdleBuilds, 1);
      final WearPrinterSelection selection =
          pushedExtra as WearPrinterSelection;
      expect(selection.whitePrinter.id, 'white');
      expect(selection.yellowPrinter.id, 'yellow');
    });
  });
}

final List<RouteBase> _testRoutes = <RouteBase>[
  GoRoute(
    path: WearMainScreen.route,
    builder: (_, __) => const SizedBox(key: Key('main')),
  ),
  GoRoute(
    path: WearMenuScreen.route,
    builder: (_, __) => const SizedBox(key: Key('menu')),
  ),
  GoRoute(
    path: WearPrinterSelectScreen.route,
    builder: (_, __) => const SizedBox(key: Key('printerSelect')),
  ),
  GoRoute(
    path: WearScanIdleScreen.route,
    builder: (_, __) => const SizedBox(key: Key('scanIdle')),
  ),
  GoRoute(
    path: WearProductSelectScreen.route,
    builder: (_, __) => const SizedBox(key: Key('productSelect')),
  ),
];

WearPrinterSelection _printerSelection() {
  return const WearPrinterSelection(
    whitePrinter: WearPrinter(id: 'white', name: 'White'),
    yellowPrinter: WearPrinter(id: 'yellow', name: 'Yellow'),
  );
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

class _PresetPrinterSelectNotifier extends WearPrinterSelectNotifier {
  _PresetPrinterSelectNotifier() : super(useCase: _NeverPrintersUseCase()) {
    state = const WearPrinterSelectState(
      phase: WearPrinterSelectPhase.idle,
      printers: <WearPrinter>[
        WearPrinter(id: 'white', name: 'White'),
        WearPrinter(id: 'yellow', name: 'Yellow'),
      ],
      error: null,
      whitePrinter: WearPrinter(id: 'white', name: 'White'),
      yellowPrinter: WearPrinter(id: 'yellow', name: 'Yellow'),
      step: WearPrinterSelectStep.yellow,
    );
  }
}

class _NeverPrintersUseCase extends GetAvailablePrintersUseCase {
  _NeverPrintersUseCase() : super(BdtoDataSource());

  @override
  Future<List<AvailablePrinter>> call() =>
      Completer<List<AvailablePrinter>>().future;
}

class _FakeSpeechRecognitionService implements SpeechRecognitionService {
  final StreamController<SegmentedRecognitionResult>
      _segmentedResultsController =
      StreamController<SegmentedRecognitionResult>.broadcast();
  final StreamController<SpeechSegmentEnded> _segmentEndedController =
      StreamController<SpeechSegmentEnded>.broadcast();
  final StreamController<SpeechSegmentStarted> _segmentStartedController =
      StreamController<SpeechSegmentStarted>.broadcast();
  bool _segmentStarted = false;

  @override
  Never get audioStreamService => throw UnsupportedError('Not used in test');

  @override
  Stream<SegmentedRecognitionResult> get segmentedResultsStream =>
      _segmentedResultsController.stream;

  @override
  Stream<SpeechSegmentEnded> get segmentEndedStream =>
      _segmentEndedController.stream;
  @override
  Stream<SpeechSegmentStarted> get segmentStartedStream =>
      _segmentStartedController.stream;

  @override
  bool get isPrepared => true;

  @override
  bool get isSessionActive => false;

  @override
  bool get isListening => false;

  @override
  bool get isVadCalibrated => true;

  @override
  bool get isCaptureRunning => false;

  @override
  bool get usesFreeTextRecognition => true;

  @override
  int? get lastAudioChunkAtMillis => null;

  @override
  int? get lastNonSilentAudioChunkAtMillis => null;

  @override
  int? get lastNonZeroNativeInputAtMillis => null;

  @override
  int? get continuousZeroAudioStartedAtMillis => null;

  @override
  int get audioChunksReceived => 0;

  @override
  int get audioCaptureId => 0;

  @override
  int? get captureStartedAtMillis => null;

  @override
  bool get hasExpectedInputDevice => true;

  @override
  String? get preferredInputDeviceId => null;

  @override
  String? get preferredInputDeviceLabel => null;

  @override
  void useDeviceProfile(VoiceDeviceProfile profile) {}

  @override
  Never get deviceProfile => throw UnsupportedError('Not used in test');

  @override
  Future<void> setFreeTextEnabled(bool enabled) async {}

  void emitCommandPartial(String text) {
    _emitSegmented(text, RecognitionKind.partial);
  }

  void emitCommandResult(String text) {
    _emitSegmented(text, RecognitionKind.finalResult);
  }

  void endSegment() {
    _segmentEndedController.add(const SpeechSegmentEnded(
      captureEpoch: 1,
      segmentId: 1,
      endChunkId: 1,
    ));
  }

  void _emitSegmented(String text, RecognitionKind kind) {
    if (!_segmentStarted) {
      _segmentStarted = true;
      _segmentStartedController.add(const SpeechSegmentStarted(
        captureEpoch: 1,
        segmentId: 1,
        startChunkId: 1,
      ));
    }
    _segmentedResultsController.add(SegmentedRecognitionResult(
      captureEpoch: 1,
      segmentId: 1,
      lane: RecognitionLane.command,
      kind: kind,
      text: text,
      lastChunkId: 1,
      parsedCommand: VoiceCommandParserService().parseExact(text),
    ));
  }

  @override
  Future<bool> requestMicrophonePermission() async => true;

  @override
  Future<bool> refreshNativeInputActivity() async => false;

  @override
  Future<void> prepare() async {}

  @override
  Future<void> startSession() async {}

  @override
  Future<void> stopSession() async {}

  @override
  Future<void> startListening() async {}

  @override
  Future<void> stopListening() async {}

  @override
  Future<void> restartListening({required String reason}) async {}

  @override
  Future<String> diagnostics() async => 'fake';

  @override
  Future<void> processAudioChunk(Uint8List bytes) async {}

  @override
  Future<void> dispose() async {
    await _segmentedResultsController.close();
    await _segmentStartedController.close();
    await _segmentEndedController.close();
  }
}
