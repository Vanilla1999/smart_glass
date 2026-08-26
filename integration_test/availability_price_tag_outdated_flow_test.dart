import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:smart_glasses/core/constants/app_constants.dart';
import 'package:smart_glasses/modules/wear/config/wear_dependencies.dart';
import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/domain/auth/model/authenticated_user.dart';
import 'package:smart_glasses/modules/wear/domain/availability/model/wear_availability_product.dart';
import 'package:smart_glasses/modules/wear/models/wear_printer.dart';
import 'package:smart_glasses/modules/wear/models/wear_printer_selection.dart';
import 'package:smart_glasses/modules/wear/presentation/input/wear_print_code_input_screen.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_availability_authority.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_printer_authority.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/availability/wear_availability_check_screen.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/printers/wear_printer_select_screen.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/status/wear_status_args.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/status/wear_status_screen.dart';
import 'package:smart_glasses/modules/wear/presentation/widgets/wear_module_app.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel appChannel = MethodChannel(AppConstants.appChannelName);
  final List<Map<String, dynamic>> glassesPayloads = <Map<String, dynamic>>[];

  setUp(() async {
    dotenv.testLoad(
      fileInput: 'WEAR_USE_MOCKS=true\nWEAR_GLASSES_ENABLED=true',
    );
    glassesPayloads.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(appChannel, (MethodCall call) async {
      if (call.method == 'updateWearGlasses' ||
          call.method == 'showWearGlasses') {
        glassesPayloads.add(Map<String, dynamic>.from(call.arguments as Map));
      }
      return null;
    });
    await WearDependencies.I.authority.clearSession();
    await WearDependencies.I.authority.setRuntimeActive(false);
    await WearDependencies.I.authority.authorize(
      AuthenticatedUser(
        idUser: 1,
        idEmployee: 2,
        name: 'Test User',
      ),
    );
    await WearDependencies.I.authority.importPrinterSelection(
      const WearPrinterSelection(
        whitePrinter: WearPrinter(id: 'old-white', name: 'OLD White'),
        yellowPrinter: WearPrinter(id: 'old-yellow', name: 'OLD Yellow'),
      ),
    );
    await WearDependencies.I.authority.enterAvailabilityScreen(
      WearScreenId.availabilityCheck,
      extra: _outdatedProduct,
    );
    final pending = WearDependencies.I.authority.payload.navigation.pending!;
    await WearDependencies.I.authority.acknowledgeNavigationAtEpoch(
      sessionEpoch: WearDependencies.I.authority.state.sessionEpoch,
      requestId: pending.requestId,
      screen: pending.screen,
    );
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(appChannel, null);
    await WearDependencies.I.authority.clearSession();
    dotenv.clean();
  });

  testWidgets(
    'outdated price tag forces printer selection and prints without rescan',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: WearModuleApp(
            flowController: WearDependencies.I.wearFlowController,
            voiceCommandStream: const Stream.empty(),
            routes: _routes(_outdatedProduct),
            initialLocation: WearAvailabilityCheckScreen.route,
            onStartVoice: () async {},
            onStopVoice: () async {},
            onRestartVoice: (_) async {},
          ),
        ),
      );

      await _pumpUntilFound(tester, find.text('Товар есть на полке?'));

      expect(find.text('Товар есть на полке?'), findsWidgets);

      await tester.tap(find.text('Да'));
      await _pumpUntilFound(tester, find.text('Сканирование товара'));

      expect(find.text('Сканирование товара'), findsWidgets);
      await tester.tap(find.text('Ручной ввод'));
      await _pumpUntilFound(tester, find.byType(WearPrintCodeInputScreen));
      Navigator.of(tester.element(find.byType(WearPrintCodeInputScreen)))
          .pop('460700001');
      await _pumpUntilFound(tester, find.text('Проверка ценника'));

      expect(find.text('Проверка ценника'), findsWidgets);
      await tester.tap(find.text('Ручной ввод'));
      await _pumpUntilFound(tester, find.byType(WearPrintCodeInputScreen));
      Navigator.of(tester.element(find.byType(WearPrintCodeInputScreen)))
          .pop('220700001');
      await _pumpUntilFound(tester, find.text('Ценник неактуален'));

      expect(find.text('Ценник неактуален'), findsWidgets);
      expect(find.text('Напечатать'), findsWidgets);
      final Map<String, dynamic> outdatedPayload = await _pumpUntilPayload(
        tester,
        glassesPayloads,
        (Map<String, dynamic> payload) =>
            payload['title'] == 'Ценник не актуален' &&
            payload['primaryAction'] == 'Напечатать',
      );
      expect(outdatedPayload['screenType'], 'availability');
      expect(outdatedPayload['statusText'], 'Ценник неактуален');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Напечатать'));
      await _pumpUntilFound(tester, find.textContaining('Выберите принтер'));

      expect(find.textContaining('Выберите принтер'), findsWidgets);
      expect(find.text('MOCK Белый 1'), findsWidgets);
      expect(find.text('OLD White'), findsNothing);

      await tester.tap(find.text('MOCK Белый 1'));
      await _pumpUntilFound(
        tester,
        find.textContaining('для желтых ценников'),
      );
      final flowController = WearDependencies.I.wearFlowController;
      final yellowPrinter = flowController.printerState.printers.firstWhere(
        (printer) => printer.name == 'MOCK Жёлтый 1',
      );
      await flowController.selectPrinter(yellowPrinter);
      await _pumpUntilFound(tester, find.text('Завершение проверки'));

      expect(
          WearDependencies
              .I.authority.features.printer.selection?.whitePrinter.name,
          'MOCK Белый 1');
      expect(
          WearDependencies
              .I.authority.features.printer.selection?.yellowPrinter.name,
          'MOCK Жёлтый 1');
      expect(find.text('Завершение проверки'), findsWidgets);
      expect(find.text('Завершить'), findsWidgets);
      expect(find.text('Сканирование товара'), findsNothing);
    },
  );
}

Future<void> _pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final DateTime end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
    if (finder.evaluate().isNotEmpty) {
      return;
    }
  }
  expect(finder, findsOneWidget);
}

Future<Map<String, dynamic>> _pumpUntilPayload(
  WidgetTester tester,
  List<Map<String, dynamic>> payloads,
  bool Function(Map<String, dynamic> payload) matches, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final DateTime end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
    for (final Map<String, dynamic> envelope in payloads.reversed) {
      final Map<String, dynamic> payload =
          Map<String, dynamic>.from(envelope['payload'] as Map);
      if (matches(payload)) {
        return payload;
      }
    }
  }
  fail('Expected glasses payload was not sent. Payloads: $payloads');
}

List<RouteBase> _routes(WearAvailabilityProduct product) {
  return <RouteBase>[
    GoRoute(
      path: WearAvailabilityCheckScreen.route,
      builder: (BuildContext context, GoRouterState state) {
        return WearAvailabilityCheckScreen(
          product: state.extra is WearAvailabilityProduct
              ? state.extra! as WearAvailabilityProduct
              : product,
        );
      },
    ),
    GoRoute(
      path: WearPrinterSelectScreen.route,
      builder: (BuildContext context, GoRouterState state) {
        return WearPrinterSelectScreen(returnSelection: state.extra == true);
      },
    ),
    GoRoute(
      path: WearPrintCodeInputScreen.route,
      builder: (BuildContext context, GoRouterState state) {
        return WearPrintCodeInputScreen(args: state.extra);
      },
    ),
    GoRoute(
      path: WearStatusScreen.route,
      builder: (BuildContext context, GoRouterState state) {
        final WearStatusScreenArgs? args = state.extra is WearStatusScreenArgs
            ? state.extra! as WearStatusScreenArgs
            : null;
        return WearStatusScreen(args: args);
      },
    ),
  ];
}

const WearAvailabilityProduct _outdatedProduct = WearAvailabilityProduct(
  id: 1002001,
  groupId: 1,
  name: 'Тестовый товар',
  code: '460700001',
  barcodes: <String>['460700001'],
  priceTagBarcodes: <String>['220700001'],
  price: 99.90,
  rest: 3,
  checkPrice: true,
  photoControl: false,
  unpackaged: false,
  priceTagActual: false,
);
