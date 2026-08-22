import 'dart:async';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_glasses/modules/wear/application/wear_printer_runtime.dart';
import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/domain/price_tag_print/model/available_printer.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_authority.dart';

void main() {
  setUp(() {
    dotenv.testLoad(fileInput: 'WEAR_USE_MOCKS=false');
  });

  Future<List<AvailablePrinter>> loader() async => <AvailablePrinter>[
        AvailablePrinter(number: 'a', name: 'A'),
        AvailablePrinter(number: 'b', name: 'B'),
      ];

  test('only one live printer effect adapter may own the domain', () async {
    final WearRuntimeAuthority authority = WearRuntimeAuthority();
    final WearPrinterRuntime first = WearPrinterRuntime(
      authority: authority,
      loadPrinters: loader,
      navigate: _noopNavigation,
    );
    addTearDown(authority.dispose);

    expect(
      () => WearPrinterRuntime(
        authority: authority,
        loadPrinters: loader,
        navigate: _noopNavigation,
      ),
      throwsStateError,
    );

    await first.dispose();
    final WearPrinterRuntime replacement = WearPrinterRuntime(
      authority: authority,
      loadPrinters: loader,
      navigate: _noopNavigation,
    );
    await replacement.dispose();
  });

  test('adapter state and aggregate task describe the same selection',
      () async {
    final WearRuntimeAuthority authority = WearRuntimeAuthority();
    final WearPrinterRuntime runtime = WearPrinterRuntime(
      authority: authority,
      loadPrinters: loader,
      navigate: _noopNavigation,
    );
    addTearDown(runtime.dispose);
    addTearDown(authority.dispose);
    await runtime.enterScreen(WearScreenId.printerSelect, extra: true);
    await _flush();

    await runtime.selectPrinter(runtime.state.visiblePrinters.first);
    await runtime.selectPrinter(runtime.state.visiblePrinters.first);
    await _flush();

    expect(
      runtime.state.selection?.whitePrinter.id,
      authority.printerTask.selection?.whitePrinter.id,
    );
    expect(
      runtime.state.selection?.yellowPrinter.id,
      authority.printerTask.selection?.yellowPrinter.id,
    );
    expect(runtime.state.focusedIndex, authority.printerTask.focusedIndex);
  });

  test('adapter dispose resets only printer task, not session authority',
      () async {
    final WearRuntimeAuthority authority = WearRuntimeAuthority();
    final WearPrinterRuntime runtime = WearPrinterRuntime(
      authority: authority,
      loadPrinters: loader,
      navigate: _noopNavigation,
    );
    addTearDown(authority.dispose);
    await runtime.enterScreen(WearScreenId.printerSelect);
    await _flush();
    expect(authority.printerTask.printers, isNotEmpty);

    await runtime.dispose();

    expect(authority.state.terminal, isFalse);
    expect(authority.printerTask.printers, isEmpty);
    expect(authority.printerTask.selection, isNull);
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
