import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:smart_glasses/modules/wear/application/wear_printer_runtime.dart';
import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/config/wear_dependencies.dart';
import 'package:smart_glasses/modules/wear/domain/price_tag_print/model/available_printer.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/wear_voice_command.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_authority.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_printer_authority.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late WearRuntimeAuthority authority;

  setUp(() async {
    dotenv.testLoad(fileInput: 'WEAR_USE_MOCKS=false');
    authority = WearRuntimeAuthority();
    await authority.requestNavigation(WearScreenId.printerSelect);
  });

  tearDown(() => authority.dispose());

  test('loads and selects printers without a widget tree', () async {
    WearScreenId? target;
    Object? capturedExtra;
    final WearPrinterRuntime runtime = WearPrinterRuntime(
      authority: authority,
      loadPrinters: () async => <AvailablePrinter>[
        AvailablePrinter(number: '1', name: 'Белый один'),
        AvailablePrinter(number: '2', name: 'Жёлтый два'),
      ],
      navigate: (
        WearScreenId screen, {
        Object? extra,
        bool replaceCurrent = false,
      }) async {
        target = screen;
        capturedExtra = extra;
      },
    );
    addTearDown(runtime.dispose);

    await runtime.enterScreen(WearScreenId.printerSelect);
    expect(
      runtime
          .dynamicVoiceItemsFor(WearScreenId.printerSelect)
          .items
          .map((item) => item.label),
      <String>['Белый один', 'Жёлтый два'],
    );

    await runtime.handleCommand(
      WearScreenId.printerSelect,
      WearVoiceCommand.select,
    );
    await runtime.handleCommand(
      WearScreenId.printerSelect,
      WearVoiceCommand.select,
    );

    expect(target, WearScreenId.scanIdle);
    expect(authority.features.printer.selection?.whitePrinter.id, '1');
    expect(authority.features.printer.selection?.yellowPrinter.id, '2');
    expect(capturedExtra, isNotNull);
  });

  test('voice item selection works while no printer screen exists', () async {
    final WearPrinterRuntime runtime = WearPrinterRuntime(
      authority: authority,
      loadPrinters: () async => <AvailablePrinter>[
        AvailablePrinter(number: '1', name: 'Принтер белый'),
        AvailablePrinter(number: '2', name: 'Принтер жёлтый'),
      ],
      navigate: (
        WearScreenId _, {
        Object? extra,
        bool replaceCurrent = false,
      }) async {},
    );
    addTearDown(runtime.dispose);
    await runtime.enterScreen(WearScreenId.printerSelect);

    expect(
      await runtime.handlePhrase(
        WearScreenId.printerSelect,
        'принтер белый',
      ),
      isTrue,
    );
    expect(
      await runtime.handleDynamicItem(WearScreenId.printerSelect, '2'),
      isTrue,
    );

    expect(authority.features.printer.selection?.whitePrinter.id, '1');
    expect(authority.features.printer.selection?.yellowPrinter.id, '2');
  });

  test('pause and resume preserve step and load printers once', () async {
    int loadCount = 0;
    final WearPrinterRuntime runtime = WearPrinterRuntime(
      authority: authority,
      loadPrinters: () async {
        loadCount++;
        return <AvailablePrinter>[
          AvailablePrinter(number: '1', name: 'Белый'),
          AvailablePrinter(number: '2', name: 'Жёлтый'),
        ];
      },
      navigate: (
        WearScreenId _, {
        Object? extra,
        bool replaceCurrent = false,
      }) async {},
    );
    addTearDown(runtime.dispose);

    await runtime.enterScreen(WearScreenId.printerSelect);
    await runtime.selectPrinter(runtime.state.printers.first);
    final int focusedBeforeResume = runtime.state.focusedIndex;
    await runtime.enterScreen(
      WearScreenId.printerSelect,
    );

    expect(loadCount, 1);
    expect(runtime.state.step, WearPrinterRuntimeStep.yellow);
    expect(runtime.state.focusedIndex, focusedBeforeResume);
  });

  test('touch and voice update the same state stream', () async {
    final WearPrinterRuntime runtime = WearPrinterRuntime(
      authority: authority,
      loadPrinters: () async => <AvailablePrinter>[
        AvailablePrinter(number: '1', name: 'Белый'),
        AvailablePrinter(number: '2', name: 'Жёлтый'),
      ],
      navigate: (_, {extra, replaceCurrent = false}) async {},
    );
    addTearDown(runtime.dispose);
    await runtime.enterScreen(WearScreenId.printerSelect);

    await runtime.selectPrinter(runtime.state.printers.first);
    expect(runtime.state.step, WearPrinterRuntimeStep.yellow);
    await runtime.handleCommand(
      WearScreenId.printerSelect,
      WearVoiceCommand.select,
    );

    expect(runtime.state.selection?.whitePrinter.id, '1');
    expect(runtime.state.selection?.yellowPrinter.id, '2');
  });

  test('completed printer pair navigates only once', () async {
    int navigationCount = 0;
    final Completer<void> navigation = Completer<void>();
    final WearPrinterRuntime runtime = WearPrinterRuntime(
      authority: authority,
      loadPrinters: () async => <AvailablePrinter>[
        AvailablePrinter(number: '1', name: 'Белый'),
        AvailablePrinter(number: '2', name: 'Жёлтый'),
      ],
      navigate: (_, {extra, replaceCurrent = false}) {
        navigationCount++;
        return navigation.future;
      },
    );
    addTearDown(runtime.dispose);
    await runtime.enterScreen(WearScreenId.printerSelect);
    await runtime.selectPrinter(runtime.state.printers.first);

    final Future<void> first =
        runtime.selectPrinter(runtime.state.visiblePrinters.first);
    final Future<void> duplicate =
        runtime.selectPrinter(runtime.state.visiblePrinters.first);
    expect(navigationCount, 1);
    navigation.complete();
    await Future.wait(<Future<void>>[first, duplicate]);
    expect(navigationCount, 1);
  });
}
