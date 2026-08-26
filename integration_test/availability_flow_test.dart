import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_glasses/core/constants/app_constants.dart';
import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/config/wear_dependencies.dart';
import 'package:smart_glasses/modules/wear/data/availability/local_wear_availability_repository.dart';
import 'package:smart_glasses/modules/wear/domain/auth/model/authenticated_user.dart';
import 'package:smart_glasses/modules/wear/infrastructure/noop_wear_glasses_output.dart';
import 'package:smart_glasses/modules/wear/navigation/wear_routes.dart';
import 'package:smart_glasses/modules/wear/presentation/input/wear_print_code_input_screen.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/menu/wear_menu_screen.dart';
import 'package:smart_glasses/modules/wear/presentation/widgets/wear_module_app.dart';

@pragma('vm:entry-point')
void glassesMain() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SizedBox.shrink());
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const MethodChannel appChannel = MethodChannel(AppConstants.appChannelName);

  setUp(() async {
    dotenv.testLoad(
      fileInput: [
        'WEAR_USE_MOCKS=true',
        'WEAR_SKIP_SCANNER_CONNECT_SCREEN=true',
      ].join('\n'),
    );
    SharedPreferences.setMockInitialValues(<String, Object>{});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(appChannel, (MethodCall call) async => null);
    await WearDependencies.I.authority.clearSession();
    await WearDependencies.I.authority.setRuntimeActive(false);
    await WearDependencies.I.authority.authorize(
      AuthenticatedUser(idUser: 1, idEmployee: 2, name: 'Test User'),
    );
    final repository = WearDependencies.I.availabilityRepository;
    if (repository is LocalWearAvailabilityRepository) {
      await repository.resetCompletedProducts();
      await repository.resetScannedProducts();
    }
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(appChannel, null);
    await WearDependencies.I.authority.clearSession();
    dotenv.clean();
  });

  testWidgets(
    'availability opens from menu and shows interaction choices',
    (WidgetTester tester) async {
      await _pumpWearModule(
        tester,
        initialLocation: WearMenuScreen.route,
      );

      expect(find.text('Меню'), findsWidgets);
      expect(find.text('Печать ценника'), findsWidgets);
      expect(find.text('Доступность'), findsWidgets);

      await tester.tap(find.text('Доступность'));

      await _pumpUntilFound(tester, find.text('Тип взаимодействия'));

      expect(find.text('Тип взаимодействия'), findsWidgets);
      expect(find.text('Список'), findsWidgets);
      expect(find.text('Прямое сканирование'), findsWidgets);
      expect(find.textContaining('Выберите принтер'), findsNothing);
      expect(find.text('Напечатать'), findsNothing);
    },
  );

  testWidgets(
    'availability list flow completes product without printing',
    (WidgetTester tester) async {
      await _pumpWearModule(
        tester,
        initialLocation: WearMenuScreen.route,
      );

      await tester.tap(find.text('Доступность'));
      await _pumpUntilFound(tester, find.text('Тип взаимодействия'));

      await tester.tap(find.text('Список'));
      await _pumpUntilFound(tester, find.text('Молочная продукция'));

      await tester.tap(find.text('Молочная продукция'));
      final flowController = WearDependencies.I.wearFlowController;
      await tester.runAsync(() async {
        if (flowController.availabilityState.products.isEmpty) {
          await flowController.availabilityStateStream.firstWhere(
            (state) => state.products.isNotEmpty,
          );
        }
      });
      await tester.pumpAndSettle();
      final Finder product = find.textContaining('HYPER Коктейль');
      await tester.scrollUntilVisible(
        product,
        300,
        scrollable: find.byType(Scrollable).last,
      );

      await tester.tap(product.first);
      await _pumpUntilFound(tester, find.text('Товар есть на полке?'));

      await tester.tap(find.text('Да'));
      await _pumpUntilFound(tester, find.text('Сканирование товара'));

      await tester.tap(find.text('Ручной ввод'));
      await _completeManualInput(tester, '8000097057');
      await _pumpUntilFound(tester, find.text('Завершение проверки'));

      expect(find.text('Напечатать'), findsNothing);
      expect(find.textContaining('Выберите принтер'), findsNothing);

      await tester.tap(find.text('Завершить'));
      await _pumpUntilFound(tester, find.text('Молочная продукция'));

      expect(
        WearDependencies.I.authority.payload.navigation.logicalScreen,
        WearScreenId.availabilityGroup,
      );
      expect(find.text('Напечатать'), findsNothing);
    },
  );
}

Future<void> _pumpWearModule(
  WidgetTester tester, {
  String initialLocation = WearMenuScreen.route,
}) async {
  final flowController = WearDependencies.I.wearFlowController;
  flowController.setGlassesOutput(NoopWearGlassesOutput());
  if (flowController.authority.payload.navigation.logicalScreen !=
      WearScreenId.menu) {
    await flowController.requestNavigation(
      WearScreenId.menu,
      replaceCurrent: true,
    );
  }
  await tester.pumpWidget(
    ProviderScope(
      child: WearModuleApp(
        flowController: flowController,
        voiceCommandStream: const Stream.empty(),
        routes: WearRoute.goRouteWear,
        initialLocation: initialLocation,
        onStartVoice: () async {},
        onStopVoice: () async {},
        onRestartVoice: (_) async {},
      ),
    ),
  );

  await _pumpUntilFound(tester, find.text('Меню'));
  expect(flowController.authority.payload.lifecycle.runtimeActive, isTrue);
}

Future<void> _completeManualInput(
  WidgetTester tester,
  String code,
) async {
  await _pumpUntilFound(tester, find.byType(WearPrintCodeInputScreen));
  Navigator.of(tester.element(find.byType(WearPrintCodeInputScreen))).pop(code);
  await tester.pump(const Duration(milliseconds: 100));
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
