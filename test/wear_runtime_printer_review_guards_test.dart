import 'dart:async';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_glasses/modules/wear/application/wear_printer_runtime.dart';
import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/domain/price_tag_print/model/available_printer.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_authority.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_store.dart';

void main() {
  setUp(() {
    dotenv.testLoad(fileInput: 'WEAR_USE_MOCKS=false');
  });

  test('reentry supersedes a stale pending load operation', () async {
    final Completer<List<AvailablePrinter>> firstLoad =
        Completer<List<AvailablePrinter>>();
    var calls = 0;
    final WearRuntimeAuthority authority = WearRuntimeAuthority();
    final WearPrinterRuntime runtime = WearPrinterRuntime(
      authority: authority,
      loadPrinters: () {
        calls++;
        if (calls == 1) return firstLoad.future;
        return Future<List<AvailablePrinter>>.value(<AvailablePrinter>[
          AvailablePrinter(number: 'fresh', name: 'Fresh'),
        ]);
      },
      navigate: _noopNavigation,
    );
    addTearDown(runtime.dispose);
    addTearDown(authority.dispose);

    await runtime.enterScreen(WearScreenId.printerSelect);
    final int firstOperation = authority.state.expectedOperationId(
      WearLoadPrintersEffect.loadOperationKind,
    )!;
    await authority.requestNavigation(WearScreenId.menu);

    await runtime.enterScreen(WearScreenId.printerSelect);
    await _flush();

    final int? currentOperation = authority.state.expectedOperationId(
      WearLoadPrintersEffect.loadOperationKind,
    );
    expect(currentOperation, isNot(firstOperation));
    expect(authority.printerTask.printers.single.id, 'fresh');

    firstLoad.complete(<AvailablePrinter>[
      AvailablePrinter(number: 'stale', name: 'Stale'),
    ]);
    await _flush();
    expect(authority.printerTask.printers.single.id, 'fresh');
  });

  test('duplicate backend printer ids fail the current load atomically',
      () async {
    final WearRuntimeAuthority authority = WearRuntimeAuthority();
    final WearPrinterRuntime runtime = WearPrinterRuntime(
      authority: authority,
      loadPrinters: () async => <AvailablePrinter>[
        AvailablePrinter(number: 'same', name: 'First'),
        AvailablePrinter(number: 'same', name: 'Second'),
      ],
      navigate: _noopNavigation,
    );
    addTearDown(runtime.dispose);
    addTearDown(authority.dispose);

    await runtime.enterScreen(WearScreenId.printerSelect);
    await _flush();

    expect(authority.printerTask.phase, WearPrinterTaskPhase.error);
    expect(authority.printerTask.printers, isEmpty);
    expect(authority.printerTask.error, contains('повторяющийся элемент'));
    expect(
      authority.state.expectedOperationId(
        WearLoadPrintersEffect.loadOperationKind,
      ),
      isNull,
    );
  });

  test('malformed stale response cannot write an error into a new screen',
      () async {
    final Completer<List<AvailablePrinter>> load =
        Completer<List<AvailablePrinter>>();
    final WearRuntimeAuthority authority = WearRuntimeAuthority();
    final WearPrinterRuntime runtime = WearPrinterRuntime(
      authority: authority,
      loadPrinters: () => load.future,
      navigate: _noopNavigation,
    );
    addTearDown(runtime.dispose);
    addTearDown(authority.dispose);
    await runtime.enterScreen(WearScreenId.printerSelect);
    await authority.requestNavigation(WearScreenId.menu);

    load.complete(<AvailablePrinter>[
      AvailablePrinter(number: '', name: 'Broken'),
    ]);
    await _flush();

    expect(authority.payload.navigation.logicalScreen, WearScreenId.menu);
    expect(authority.printerTask.error, isNull);
  });

  test('same printer cannot be imported as white and yellow', () async {
    final WearRuntimeAuthority authority = WearRuntimeAuthority();
    addTearDown(authority.dispose);
    final AvailablePrinter raw = AvailablePrinter(number: 'one', name: 'One');
    final WearPrinterRuntime runtime = WearPrinterRuntime(
      authority: authority,
      loadPrinters: () async => <AvailablePrinter>[raw],
      navigate: _noopNavigation,
    );
    addTearDown(runtime.dispose);
    await runtime.enterScreen(WearScreenId.printerSelect);
    await _flush();

    final WearDispatchResult result = await authority.selectPrinterById('one');
    expect(result.accepted, isTrue);
    final WearDispatchResult second = await authority.selectPrinterById('one');
    expect(second.accepted, isFalse);
  });
}

Future<void> _noopNavigation(
  WearScreenId screen, {
  Object? extra,
  bool replaceCurrent = false,
}) async {}

Future<void> _flush() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}
