import 'dart:async';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_glasses/modules/wear/application/wear_printer_runtime.dart';
import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/domain/auth/model/authenticated_user.dart';
import 'package:smart_glasses/modules/wear/domain/price_tag_print/model/available_printer.dart';
import 'package:smart_glasses/modules/wear/models/wear_printer.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_authority.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_store.dart';

void main() {
  setUp(() {
    dotenv.testLoad(fileInput: 'WEAR_USE_MOCKS=false');
  });

  AvailablePrinter available(String id, String name) {
    return AvailablePrinter(number: id, name: name);
  }

  AuthenticatedUser user() => AuthenticatedUser(
        idUser: 1,
        idEmployee: 2,
        name: 'Сотрудник',
      );

  test('loading snapshot commits before blocked loader completes', () async {
    final Completer<List<AvailablePrinter>> loader =
        Completer<List<AvailablePrinter>>();
    final WearRuntimeAuthority authority = WearRuntimeAuthority();
    final WearPrinterRuntime runtime = WearPrinterRuntime(
      authority: authority,
      loadPrinters: () => loader.future,
      navigate: _noopNavigation,
    );
    addTearDown(runtime.dispose);
    addTearDown(authority.dispose);

    await runtime.enterScreen(WearScreenId.printerSelect);

    expect(loader.isCompleted, isFalse);
    expect(authority.printerTask.phase, WearPrinterTaskPhase.loading);
    expect(
      authority.state.expectedOperationId(
        WearLoadPrintersEffect.loadOperationKind,
      ),
      isNotNull,
    );

    loader.complete(<AvailablePrinter>[
      available('a', 'Белый A'),
      available('b', 'Жёлтый B'),
    ]);
    await _flush();

    expect(authority.printerTask.phase, WearPrinterTaskPhase.ready);
    expect(authority.printerTask.printers, hasLength(2));
    expect(
      authority.state.expectedOperationId(
        WearLoadPrintersEffect.loadOperationKind,
      ),
      isNull,
    );
  });

  test('white and yellow selection navigates exactly once', () async {
    final List<WearScreenId> navigations = <WearScreenId>[];
    final WearRuntimeAuthority authority = WearRuntimeAuthority();
    final WearPrinterRuntime runtime = WearPrinterRuntime(
      authority: authority,
      loadPrinters: () async => <AvailablePrinter>[
        available('a', 'Белый A'),
        available('b', 'Жёлтый B'),
        available('c', 'Мобильный C'),
      ],
      navigate: (
        WearScreenId screen, {
        Object? extra,
        bool replaceCurrent = false,
      }) async {
        navigations.add(screen);
      },
    );
    addTearDown(runtime.dispose);
    addTearDown(authority.dispose);
    await runtime.enterScreen(WearScreenId.printerSelect);
    await _flush();

    await runtime.selectPrinter(authority.printerTask.visiblePrinters.first);
    expect(authority.printerTask.step, WearPrinterTaskStep.yellow);
    expect(
      authority.printerTask.visiblePrinters
          .any((WearPrinter item) => item.id == 'a'),
      isFalse,
    );

    await runtime.selectPrinter(authority.printerTask.visiblePrinters.first);
    await _flush();

    expect(authority.printerTask.selection?.whitePrinter.id, 'a');
    expect(authority.printerTask.selection?.yellowPrinter.id, 'b');
    expect(authority.payload.navigation.logicalScreen, WearScreenId.scanIdle);
    expect(navigations, <WearScreenId>[WearScreenId.scanIdle]);

    final WearDispatchResult duplicate =
        await authority.selectPrinterById('b');
    expect(duplicate.accepted, isFalse);
    expect(navigations, hasLength(1));
  });

  test('return-selection mode completes without navigation', () async {
    var navigationCalls = 0;
    final WearRuntimeAuthority authority = WearRuntimeAuthority();
    final WearPrinterRuntime runtime = WearPrinterRuntime(
      authority: authority,
      loadPrinters: () async => <AvailablePrinter>[
        available('a', 'A'),
        available('b', 'B'),
      ],
      navigate: (
        WearScreenId screen, {
        Object? extra,
        bool replaceCurrent = false,
      }) async {
        navigationCalls++;
      },
    );
    addTearDown(runtime.dispose);
    addTearDown(authority.dispose);
    await runtime.enterScreen(WearScreenId.printerSelect, extra: true);
    await _flush();

    await runtime.selectPrinter(authority.printerTask.visiblePrinters.first);
    await runtime.selectPrinter(authority.printerTask.visiblePrinters.first);
    await _flush();

    expect(authority.printerTask.selection, isNotNull);
    expect(authority.payload.navigation.logicalScreen, WearScreenId.printerSelect);
    expect(navigationCalls, 0);
  });

  test('reload rebinds a valid pair to fresh models', () async {
    var call = 0;
    final WearRuntimeAuthority authority = WearRuntimeAuthority();
    final WearPrinterRuntime runtime = WearPrinterRuntime(
      authority: authority,
      loadPrinters: () async {
        call++;
        return call == 1
            ? <AvailablePrinter>[
                available('a', 'A old'),
                available('b', 'B old'),
              ]
            : <AvailablePrinter>[
                available('a', 'A fresh'),
                available('b', 'B fresh'),
              ];
      },
      navigate: _noopNavigation,
    );
    addTearDown(runtime.dispose);
    addTearDown(authority.dispose);
    await _selectPair(runtime, authority);

    await runtime.load();
    await _flush();

    expect(authority.printerTask.selection?.whitePrinter.name, 'A fresh');
    expect(authority.printerTask.selection?.yellowPrinter.name, 'B fresh');
  });

  test('reload clears the pair when white printer disappears', () async {
    var call = 0;
    final WearRuntimeAuthority authority = WearRuntimeAuthority();
    final WearPrinterRuntime runtime = WearPrinterRuntime(
      authority: authority,
      loadPrinters: () async {
        call++;
        return call == 1
            ? <AvailablePrinter>[
                available('a', 'A'),
                available('b', 'B'),
              ]
            : <AvailablePrinter>[
                available('b', 'B'),
                available('c', 'C'),
              ];
      },
      navigate: _noopNavigation,
    );
    addTearDown(runtime.dispose);
    addTearDown(authority.dispose);
    await _selectPair(runtime, authority);

    await runtime.load();
    await _flush();

    expect(authority.printerTask.whitePrinter, isNull);
    expect(authority.printerTask.selection, isNull);
    expect(authority.printerTask.step, WearPrinterTaskStep.white);
  });

  test('reload keeps white and requests yellow when yellow disappears',
      () async {
    var call = 0;
    final WearRuntimeAuthority authority = WearRuntimeAuthority();
    final WearPrinterRuntime runtime = WearPrinterRuntime(
      authority: authority,
      loadPrinters: () async {
        call++;
        return call == 1
            ? <AvailablePrinter>[
                available('a', 'A'),
                available('b', 'B'),
              ]
            : <AvailablePrinter>[
                available('a', 'A fresh'),
                available('c', 'C'),
              ];
      },
      navigate: _noopNavigation,
    );
    addTearDown(runtime.dispose);
    addTearDown(authority.dispose);
    await _selectPair(runtime, authority);

    await runtime.load();
    await _flush();

    expect(authority.printerTask.whitePrinter?.name, 'A fresh');
    expect(authority.printerTask.selection, isNull);
    expect(authority.printerTask.step, WearPrinterTaskStep.yellow);
  });

  test('load result from cleared session cannot repopulate printer task',
      () async {
    final Completer<List<AvailablePrinter>> loader =
        Completer<List<AvailablePrinter>>();
    final WearRuntimeAuthority authority = WearRuntimeAuthority();
    await authority.authorize(user());
    final WearPrinterRuntime runtime = WearPrinterRuntime(
      authority: authority,
      loadPrinters: () => loader.future,
      navigate: _noopNavigation,
    );
    addTearDown(runtime.dispose);
    addTearDown(authority.dispose);
    await runtime.enterScreen(WearScreenId.printerSelect);
    final int oldEpoch = authority.state.sessionEpoch;

    await authority.clearSession();
    loader.complete(<AvailablePrinter>[available('a', 'A')]);
    await _flush();

    expect(authority.state.sessionEpoch, oldEpoch + 1);
    expect(authority.printerTask.printers, isEmpty);
    expect(authority.printerTask.selection, isNull);
  });

  test('session clear removes aggregate printer selection atomically', () async {
    final WearRuntimeAuthority authority = WearRuntimeAuthority();
    await authority.authorize(user());
    final WearPrinterRuntime runtime = WearPrinterRuntime(
      authority: authority,
      loadPrinters: () async => <AvailablePrinter>[
        available('a', 'A'),
        available('b', 'B'),
      ],
      navigate: _noopNavigation,
    );
    addTearDown(runtime.dispose);
    addTearDown(authority.dispose);
    await _selectPair(runtime, authority);
    expect(authority.printerTask.selection, isNotNull);

    await authority.clearSession();

    expect(authority.printerTask.selection, isNull);
    expect(authority.printerTask.printers, isEmpty);
    expect(authority.controls.scanner.barcodeAdmissionEnabled, isFalse);
  });
}

Future<void> _selectPair(
  WearPrinterRuntime runtime,
  WearRuntimeAuthority authority,
) async {
  await runtime.enterScreen(WearScreenId.printerSelect, extra: true);
  await _flush();
  await runtime.selectPrinter(authority.printerTask.visiblePrinters.first);
  await runtime.selectPrinter(authority.printerTask.visiblePrinters.first);
  await _flush();
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
