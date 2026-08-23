import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/domain/auth/model/authenticated_user.dart';
import 'package:smart_glasses/modules/wear/domain/price_tag_print/model/barcode_product_info.dart';
import 'package:smart_glasses/modules/wear/models/wear_printer.dart';
import 'package:smart_glasses/modules/wear/models/wear_printer_selection.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_authority.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_scan_effects.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_store.dart';

void main() {
  Future<WearRuntimeAuthority> preparedAuthority() async {
    final WearRuntimeAuthority authority = WearRuntimeAuthority();
    await authority.authorize(
      AuthenticatedUser(idUser: 1, idEmployee: 2, name: 'User'),
    );
    await authority.importPrinterSelection(
      const WearPrinterSelection(
        whitePrinter: WearPrinter(id: 'white', name: 'White'),
        yellowPrinter: WearPrinter(id: 'yellow', name: 'Yellow'),
      ),
    );
    return authority;
  }

  test('scan task is aggregate-owned at authority construction', () {
    final WearRuntimeAuthority authority = WearRuntimeAuthority();
    addTearDown(authority.dispose);

    expect(authority.features.scan, isA<WearScanTaskSlice>());
    expect(authority.scanTask.phase, WearScanTaskPhase.waiting);
  });

  test('status delay starts only after presenter result', () async {
    final WearRuntimeAuthority authority = await preparedAuthority();
    addTearDown(authority.dispose);
    final Completer<void> presenter = Completer<void>();
    final Completer<void> delay = Completer<void>();
    var presenterCalls = 0;
    var delayCalls = 0;
    final List<WearScreenId> navigation = <WearScreenId>[];
    authority.registerEffectExecutor(
      WearScanEffectExecutor(
        lookup: (_) async => const <BarcodeProductInfo>[],
        print: (_, __) async => 'unused',
        navigate: (screen, {extra, replaceCurrent = false}) async {
          navigation.add(screen);
        },
        presentStatus: (_, {required completion}) {
          presenterCalls++;
          return presenter.future;
        },
        delay: (_) {
          delayCalls++;
          return delay.future;
        },
      ),
    );

    await authority.enterScanScreen(WearScreenId.scanIdle);
    await authority.submitScanBarcode('4600000000001');
    await _flush();

    expect(authority.scanTask.phase, WearScanTaskPhase.status);
    expect(presenterCalls, 1);
    expect(delayCalls, 0);
    expect(navigation, isEmpty);

    presenter.complete();
    await _flush();
    expect(delayCalls, 1);
    expect(navigation, isEmpty);

    delay.complete();
    await _flush();
    expect(navigation, <WearScreenId>[WearScreenId.scanIdle]);
  });

  test('delay failure fails open to the committed return target', () async {
    final WearRuntimeAuthority authority = await preparedAuthority();
    addTearDown(authority.dispose);
    final List<WearScreenId> navigation = <WearScreenId>[];
    authority.registerEffectExecutor(
      WearScanEffectExecutor(
        lookup: (_) async => const <BarcodeProductInfo>[],
        print: (_, __) async => 'unused',
        navigate: (screen, {extra, replaceCurrent = false}) async {
          navigation.add(screen);
        },
        presentStatus: (_, {required completion}) async {},
        delay: (_) => Future<void>.error(StateError('scheduler failed')),
      ),
    );

    await authority.enterScanScreen(WearScreenId.scanIdle);
    await authority.submitScanBarcode('4600000000002');
    await _flush(6);

    expect(authority.scanTask.phase, WearScanTaskPhase.waiting);
    expect(authority.payload.navigation.logicalScreen, WearScreenId.scanIdle);
    expect(navigation, <WearScreenId>[WearScreenId.scanIdle]);
  });

  test('same-screen widget attachment cannot cancel active print', () async {
    final WearRuntimeAuthority authority = await preparedAuthority();
    addTearDown(authority.dispose);
    final Completer<String> print = Completer<String>();
    final Completer<void> statusDelay = Completer<void>();
    authority.registerEffectExecutor(
      WearScanEffectExecutor(
        lookup: (_) async => <BarcodeProductInfo>[
          BarcodeProductInfo(id: 10, name: 'Молоко'),
        ],
        print: (_, __) => print.future,
        navigate: (_, {extra, replaceCurrent = false}) async {},
        presentStatus: (_, {required completion}) async {},
        delay: (_) => statusDelay.future,
      ),
    );

    await authority.enterScanScreen(WearScreenId.scanIdle);
    await authority.submitScanBarcode('4600000000003');
    await _flush();
    expect(authority.scanTask.phase, WearScanTaskPhase.printing);
    expect(authority.scanTask.productName, 'Молоко');
    final int? printOperation = authority.state.expectedOperationId(
      WearPrintPriceTagEffect.operationKind,
    );

    final WearDispatchResult attachment =
        await authority.enterScanScreen(WearScreenId.scanIdle);

    expect(attachment.accepted, isTrue);
    expect(attachment.stateChanged, isFalse);
    expect(
      authority.state
          .expectedOperationId(WearPrintPriceTagEffect.operationKind),
      printOperation,
    );
    expect(authority.scanTask.phase, WearScanTaskPhase.printing);

    print.complete('Белый принтер');
    await _flush();

    expect(authority.scanTask.phase, WearScanTaskPhase.status);
    expect(authority.scanTask.productName, 'Молоко');
    expect(authority.scanTask.status?.message, 'Молоко');
    expect(authority.scanTask.status?.details, 'Белый принтер');
    statusDelay.complete();
  });
}

Future<void> _flush([int turns = 4]) async {
  for (int index = 0; index < turns; index++) {
    await Future<void>.delayed(Duration.zero);
  }
}
