import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:smart_glasses/modules/wear/application/wear_printer_runtime.dart';
import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/config/wear_session.dart';
import 'package:smart_glasses/modules/wear/domain/price_tag_print/model/available_printer.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/wear_voice_command.dart';
import 'package:smart_glasses/modules/wear/models/wear_printer.dart';

void main() {
  setUp(() {
    dotenv.testLoad(fileInput: 'WEAR_USE_MOCKS=false');
  });

  tearDown(WearSession.clearPrinterSelection);

  test('loads and selects printers without a widget tree', () async {
    WearScreenId? target;
    Object? capturedExtra;
    final WearPrinterRuntime runtime = WearPrinterRuntime(
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
    expect(WearSession.printerSelectionOrNull?.whitePrinter.id, '1');
    expect(WearSession.printerSelectionOrNull?.yellowPrinter.id, '2');
    expect(capturedExtra, isNotNull);
  });

  test('voice item selection works while no printer screen exists', () async {
    final WearPrinterRuntime runtime = WearPrinterRuntime(
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

    expect(WearSession.printerSelectionOrNull?.whitePrinter.id, '1');
    expect(WearSession.printerSelectionOrNull?.yellowPrinter.id, '2');
  });

  test('screen-off handoff continues from selected white printer', () async {
    WearScreenId? target;
    final WearPrinterRuntime runtime = WearPrinterRuntime(
      loadPrinters: () async => const <AvailablePrinter>[],
      navigate: (
        WearScreenId screen, {
        Object? extra,
        bool replaceCurrent = false,
      }) async {
        target = screen;
      },
    );
    addTearDown(runtime.dispose);
    const WearPrinter white = WearPrinter(id: '1', name: 'Белый');
    const WearPrinter yellow = WearPrinter(id: '2', name: 'Жёлтый');

    runtime.restorePresentationState(
      WearScreenId.printerSelect,
      const WearPrinterRuntimeState(
        printers: <WearPrinter>[white, yellow],
        whitePrinter: white,
        step: WearPrinterRuntimeStep.yellow,
        focusedIndex: 0,
      ),
    );
    await runtime.handleCommand(
      WearScreenId.printerSelect,
      WearVoiceCommand.select,
    );

    expect(target, WearScreenId.scanIdle);
    expect(WearSession.printerSelectionOrNull?.whitePrinter, white);
    expect(WearSession.printerSelectionOrNull?.yellowPrinter, yellow);
  });
}
