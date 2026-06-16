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
import 'package:smart_glasses/features/glasses/presentation/cubit/wear/wear_glasses_state.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_typing/speech_recognition_service.dart';
import 'package:smart_glasses/modules/wear/application/ports/wear_glasses_output.dart';
import 'package:smart_glasses/modules/wear/application/ports/wear_navigation_output.dart';
import 'package:smart_glasses/modules/wear/application/wear_flow_controller.dart';
import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/application/wear_ui_lifecycle.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/wear_voice_command.dart';
import 'package:smart_glasses/modules/wear/models/wear_printer.dart';
import 'package:smart_glasses/modules/wear/models/wear_printer_selection.dart';
import 'package:smart_glasses/modules/wear/presentation/glasses/wear_glasses_payload.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/main/wear_main_screen.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/printers/cubit/wear_printer_select_cubit.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/menu/wear_menu_screen.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/printers/wear_printer_select_screen.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/scan/wear_product_select_screen.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/scan/wear_scan_idle_screen.dart';
import 'package:smart_glasses/modules/wear/presentation/widgets/wear_module_app.dart';
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
  late _CoordinatorBridgeOutput bridgeOutput;
  late _FakeNavigationOutput navigation;
  late WearFlowController flowController;
  late GlassesCoordinatorCubit coordinator;
  late Map<String, dynamic> lastWearPayload;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();

    channel = MethodChannel(AppConstants.glassesChannelName);
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

  tearDown(() {
    coordinator.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
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
        <String>['Печать ценников', 'Доступность', 'Справка', 'Настройки'],
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

    test('menu select navigates and sends target screen payload', () async {
      await coordinator.init();

      flowController.setUiLifecycle(WearUiLifecycle.active);
      flowController.enterScreen(WearScreenId.menu);
      await Future<void>.delayed(Duration.zero);

      await flowController.handleVoiceCommand(WearVoiceCommand.select);

      expect(flowController.state.screen, WearScreenId.printerSelect);
      expect(lastWearPayload['screenType'], 'printer');
      expect(lastWearPayload['phase'], 'loading');
      expect(lastWearPayload['title'], 'Принтеры');
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
        <String>['Печать ценников', 'Доступность', 'Справка', 'Настройки'],
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
  });

  group('WearModuleApp router integration', () {
    setUp(() {
      dotenv.testLoad(fileInput: 'WEAR_SKIP_SCANNER_CONNECT_SCREEN=true');
      WearSession.setUser(AuthenticatedUser(
        idUser: 1,
        idEmployee: 1,
        name: 'Test User',
      ));
    });

    tearDown(() {
      WearSession.clear();
    });

    testWidgets('pop from scanIdle syncs flow state back to printerSelect',
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

    testWidgets('pop to scanIdle keeps route extra in flow state',
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

    testWidgets('voice stream command is routed through WearModuleApp to flow',
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

    testWidgets('voice starts immediately when authorization completes',
        (WidgetTester tester) async {
      WearSession.clear();
      int startVoiceCalls = 0;
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
          onStopVoice: () async {},
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
    });

    testWidgets(
        'ASR partial flows through WearVoiceControlService and WearModuleApp to flow',
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

      speech.emitPartial('вниз');
      await tester.pumpAndSettle();

      expect(routerFlow.state.menuFocusedIndex, 1);
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

    testWidgets(
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
  final StreamController<String> _resultsController =
      StreamController<String>.broadcast();
  final StreamController<String> _partialController =
      StreamController<String>.broadcast();

  @override
  Stream<String> get resultsStream => _resultsController.stream;

  @override
  Stream<String> get partialResultsStream => _partialController.stream;

  @override
  bool get isPrepared => true;

  @override
  bool get isSessionActive => false;

  @override
  bool get isListening => false;

  @override
  int? get lastAudioChunkAtMillis => null;

  void emitPartial(String text) {
    _partialController.add(text);
  }

  @override
  Future<bool> requestMicrophonePermission() async => true;

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
    await _resultsController.close();
    await _partialController.close();
  }
}
