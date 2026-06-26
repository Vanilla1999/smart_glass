import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_glasses/modules/wear/config/wear_dependencies.dart';
import 'package:smart_glasses/modules/wear/config/wear_session.dart';
import 'package:smart_glasses/modules/wear/data/availability/local_wear_availability_repository.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/wear_voice_command.dart';
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

  setUp(() async {
    dotenv.testLoad(
      fileInput: [
        'WEAR_USE_MOCKS=true',
        'WEAR_SKIP_SCANNER_CONNECT_SCREEN=true',
      ].join('\n'),
    );
    SharedPreferences.setMockInitialValues(<String, Object>{});
    WearSession.clear();
    final repository = WearDependencies.I.availabilityRepository;
    if (repository is LocalWearAvailabilityRepository) {
      await repository.resetCompletedProducts();
      await repository.resetScannedProducts();
    }
  });

  tearDown(() {
    WearSession.clear();
    dotenv.clean();
  });

  testWidgets(
    'availability opens from menu and shows interaction choices',
    (WidgetTester tester) async {
      final StreamController<WearVoiceCommand> commands =
          StreamController<WearVoiceCommand>();
      addTearDown(commands.close);

      await _pumpWearModule(
        tester,
        voiceCommandStream: commands.stream,
        initialLocation: WearMenuScreen.route,
      );

      expect(find.text('Меню'), findsWidgets);
      expect(find.text('Печать ценника'), findsWidgets);
      expect(find.text('Доступность'), findsWidgets);

      commands.add(WearVoiceCommand.down);
      await tester.pump(const Duration(milliseconds: 100));
      commands.add(WearVoiceCommand.select);

      await _pumpUntilFound(tester, find.text('Тип взаимодействия'));

      expect(find.text('Тип взаимодействия'), findsWidgets);
      expect(find.text('Список'), findsWidgets);
      expect(find.text('Прямое сканирование'), findsWidgets);
      expect(find.textContaining('Выберите принтер'), findsNothing);
      expect(find.text('Напечатать'), findsNothing);
    },
  );

  testWidgets(
    'availability list flow completes actual price tag product without printing',
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
      await _pumpUntilFound(tester, find.textContaining('ЧУДО Коктейль'));

      await tester.tap(find.textContaining('ЧУДО Коктейль').first);
      await _pumpUntilFound(tester, find.text('Товар есть на полке?'));

      await tester.tap(find.text('Да'));
      await _pumpUntilFound(tester, find.text('Сканирование товара'));

      await tester.tap(find.text('Ручной ввод'));
      await _completeManualInput(tester, '3010420008');
      await _pumpUntilFound(tester, find.text('Проверка ценника'));

      await tester.tap(find.text('Ручной ввод'));
      await _completeManualInput(tester, '2230104200084');
      await _pumpUntilFound(tester, find.text('Завершение проверки'));

      expect(find.text('Напечатать'), findsNothing);
      expect(find.textContaining('Выберите принтер'), findsNothing);

      await tester.tap(find.text('Завершить'));
      await _pumpUntilFound(tester, find.text('Проверка завершена'));

      expect(find.text('Проверка завершена'), findsWidgets);
      expect(find.text('Проверка товара завершена'), findsWidgets);
    },
  );
}

Future<void> _pumpWearModule(
  WidgetTester tester, {
  Stream<WearVoiceCommand>? voiceCommandStream,
  String initialLocation = WearMenuScreen.route,
}) async {
  final flowController = WearDependencies.I.wearFlowController;
  flowController.setGlassesOutput(NoopWearGlassesOutput());

  await tester.pumpWidget(
    ProviderScope(
      child: WearModuleApp(
        flowController: flowController,
        voiceCommandStream: voiceCommandStream ?? const Stream.empty(),
        routes: WearRoute.goRouteWear,
        initialLocation: initialLocation,
        onStartVoice: () async {},
        onStopVoice: () async {},
        onRestartVoice: (_) async {},
      ),
    ),
  );

  await _pumpUntilFound(tester, find.text('Меню'));
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
