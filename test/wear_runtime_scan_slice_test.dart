import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_glasses/modules/wear/application/wear_scan_runtime.dart';
import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/domain/auth/model/authenticated_user.dart';
import 'package:smart_glasses/modules/wear/domain/price_tag_print/model/barcode_product_info.dart';
import 'package:smart_glasses/modules/wear/models/wear_printer.dart';
import 'package:smart_glasses/modules/wear/models/wear_printer_selection.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_authority.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_scan_effects.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_store.dart';

void main() {
  test('zero lookup results enter aggregate not-found status', () async {
    final WearRuntimeAuthority authority = await _preparedAuthority();
    addTearDown(authority.dispose);
    authority.registerEffectExecutor(
      WearScanEffectExecutor(
        lookup: (_) async => const <BarcodeProductInfo>[],
        print: (_, __) async => 'unused',
        navigate: (_, {extra, replaceCurrent = false}) async {},
        presentStatus: (_, {required completion}) async {},
        delay: (_) => Completer<void>().future,
      ),
    );

    await authority.enterScanScreen(WearScreenId.scanIdle);
    final WearDispatchResult receipt =
        await authority.submitScanBarcode('4600000000000');
    await _flush();

    expect(receipt.accepted, isTrue);
    expect(authority.scanTask.phase, WearScanTaskPhase.status);
    expect(authority.scanTask.status?.title, 'Товар не найден');
    expect(authority.scanTask.products, isEmpty);
  });

  test('one lookup result commits printing before print completes', () async {
    final WearRuntimeAuthority authority = await _preparedAuthority();
    addTearDown(authority.dispose);
    final Completer<String> print = Completer<String>();
    var printCalls = 0;
    authority.registerEffectExecutor(
      WearScanEffectExecutor(
        lookup: (_) async => <BarcodeProductInfo>[
          BarcodeProductInfo(id: 10, name: 'Product'),
        ],
        print: (_, __) {
          printCalls++;
          return print.future;
        },
        navigate: (_, {extra, replaceCurrent = false}) async {},
        presentStatus: (_, {required completion}) async {},
        delay: (_) => Completer<void>().future,
      ),
    );

    await authority.enterScanScreen(WearScreenId.scanIdle);
    await authority.submitScanBarcode('4600000000001');
    await _flush();

    expect(printCalls, 1);
    expect(authority.scanTask.phase, WearScanTaskPhase.printing);
    expect(
      authority.state
          .expectedOperationId(WearPrintPriceTagEffect.operationKind),
      isNotNull,
    );

    print.complete('Product');
    await _flush();
    expect(authority.scanTask.phase, WearScanTaskPhase.status);
  });

  test('many lookup results enter immutable product selection', () async {
    final WearRuntimeAuthority authority = await _preparedAuthority();
    addTearDown(authority.dispose);
    final List<WearScreenId> navigation = <WearScreenId>[];
    authority.registerEffectExecutor(
      WearScanEffectExecutor(
        lookup: (_) async => <BarcodeProductInfo>[
          BarcodeProductInfo(id: 10, name: 'First'),
          BarcodeProductInfo(id: 11, name: 'Second'),
        ],
        print: (_, __) async => 'unused',
        navigate: (screen, {extra, replaceCurrent = false}) async {
          navigation.add(screen);
        },
        presentStatus: (_, {required completion}) async {},
        delay: (_) async {},
      ),
    );

    await authority.enterScanScreen(WearScreenId.scanIdle);
    await authority.submitScanBarcode('4600000000002');
    await _flush();

    expect(authority.scanTask.phase, WearScanTaskPhase.selecting);
    expect(authority.scanTask.screen, WearScreenId.productSelect);
    expect(
        authority.payload.navigation.logicalScreen, WearScreenId.productSelect);
    expect(authority.scanTask.products.map((item) => item.id), <int>[10, 11]);
    expect(navigation, <WearScreenId>[WearScreenId.productSelect]);
    expect(
      () => authority.scanTask.products.add(
        BarcodeProductInfo(id: 12, name: 'Third'),
      ),
      throwsUnsupportedError,
    );
  });

  test('duplicate product ids become a current lookup error', () async {
    final WearRuntimeAuthority authority = await _preparedAuthority();
    addTearDown(authority.dispose);
    authority.registerEffectExecutor(
      WearScanEffectExecutor(
        lookup: (_) async => <BarcodeProductInfo>[
          BarcodeProductInfo(id: 10, name: 'First'),
          BarcodeProductInfo(id: 10, name: 'Duplicate'),
        ],
        print: (_, __) async => 'unused',
        navigate: (_, {extra, replaceCurrent = false}) async {},
        presentStatus: (_, {required completion}) async {},
        delay: (_) => Completer<void>().future,
      ),
    );

    await authority.enterScanScreen(WearScreenId.scanIdle);
    await authority.submitScanBarcode('4600000000003');
    await _flush();

    expect(authority.scanTask.phase, WearScanTaskPhase.status);
    expect(authority.scanTask.products, isEmpty);
    expect(authority.scanTask.status?.kind.name, 'error');
  });

  test('duplicate barcode while lookup is active starts one lookup', () async {
    final WearRuntimeAuthority authority = await _preparedAuthority();
    addTearDown(authority.dispose);
    final Completer<List<BarcodeProductInfo>> lookup =
        Completer<List<BarcodeProductInfo>>();
    var lookupCalls = 0;
    authority.registerEffectExecutor(
      WearScanEffectExecutor(
        lookup: (_) {
          lookupCalls++;
          return lookup.future;
        },
        print: (_, __) async => 'unused',
        navigate: (_, {extra, replaceCurrent = false}) async {},
        presentStatus: (_, {required completion}) async {},
        delay: (_) async {},
      ),
    );

    await authority.enterScanScreen(WearScreenId.scanIdle);
    final WearDispatchResult first =
        await authority.submitScanBarcode('4600000000004');
    final WearDispatchResult duplicate =
        await authority.submitScanBarcode('4600000000004');

    expect(first.accepted, isTrue);
    expect(duplicate.accepted, isFalse);
    expect(lookupCalls, 1);
    expect(authority.scanTask.phase, WearScanTaskPhase.lookingUp);

    lookup.complete(const <BarcodeProductInfo>[]);
    await _flush();
  });

  test('old print result cannot mutate a cleared session epoch', () async {
    final WearRuntimeAuthority authority = await _preparedAuthority();
    addTearDown(authority.dispose);
    final Completer<String> print = Completer<String>();
    authority.registerEffectExecutor(
      WearScanEffectExecutor(
        lookup: (_) async => <BarcodeProductInfo>[
          BarcodeProductInfo(id: 10, name: 'Product'),
        ],
        print: (_, __) => print.future,
        navigate: (_, {extra, replaceCurrent = false}) async {},
        presentStatus: (_, {required completion}) async {},
        delay: (_) async {},
      ),
    );

    await authority.enterScanScreen(WearScreenId.scanIdle);
    await authority.submitScanBarcode('4600000000005');
    await _flush();
    final int oldEpoch = authority.state.sessionEpoch;
    expect(authority.scanTask.phase, WearScanTaskPhase.printing);

    await authority.clearSession();
    expect(authority.state.sessionEpoch, greaterThan(oldEpoch));
    expect(authority.scanTask.phase, WearScanTaskPhase.waiting);

    print.complete('Product');
    await _flush();
    expect(authority.scanTask.phase, WearScanTaskPhase.waiting);
    expect(authority.scanTask.status, isNull);
  });

  test('old same-epoch effect is stale after scan executor replacement',
      () async {
    final WearRuntimeAuthority authority = await _preparedAuthority();
    addTearDown(authority.dispose);
    final Completer<List<BarcodeProductInfo>> oldLookup =
        Completer<List<BarcodeProductInfo>>();
    final WearScanRuntime oldRuntime = WearScanRuntime(
      authority: authority,
      lookupBarcode: (_) => oldLookup.future,
      printProduct: (_, __) async => 'unused',
      navigate: (_, {extra, replaceCurrent = false}) async {},
      showStatus: (_, {required completion}) async {},
      delay: (_) async {},
    );

    await oldRuntime.enterScreen(WearScreenId.scanIdle);
    await oldRuntime.handleBarcode(WearScreenId.scanIdle, '4600000000006');
    final int oldOperationId = authority.state.expectedOperationId(
      WearLookupBarcodeEffect.operationKind,
    )!;
    await oldRuntime.dispose();

    final Completer<List<BarcodeProductInfo>> replacementLookup =
        Completer<List<BarcodeProductInfo>>();
    final Completer<void> replacementDelay = Completer<void>();
    final WearScanRuntime replacementRuntime = WearScanRuntime(
      authority: authority,
      lookupBarcode: (_) => replacementLookup.future,
      printProduct: (_, __) async => 'unused',
      navigate: (_, {extra, replaceCurrent = false}) async {},
      showStatus: (_, {required completion}) async {},
      delay: (_) => replacementDelay.future,
    );
    addTearDown(replacementRuntime.dispose);
    await replacementRuntime.enterScreen(WearScreenId.scanIdle);
    await replacementRuntime.handleBarcode(
      WearScreenId.scanIdle,
      '4600000000007',
    );
    final int replacementOperationId = authority.state.expectedOperationId(
      WearLookupBarcodeEffect.operationKind,
    )!;

    expect(replacementOperationId, greaterThan(oldOperationId));
    final WearDispatchResult staleSuccess = await authority.store.dispatch(
      WearBarcodeLookupSucceeded(
        sessionEpoch: authority.state.sessionEpoch,
        operationId: oldOperationId,
        products: const <BarcodeProductInfo>[],
      ),
    );
    final WearDispatchResult staleError = await authority.store.dispatch(
      WearBarcodeLookupFailed(
        sessionEpoch: authority.state.sessionEpoch,
        operationId: oldOperationId,
        message: 'old error',
      ),
    );
    expect(staleSuccess.rejectReason, WearDispatchRejectReason.staleOperation);
    expect(staleError.rejectReason, WearDispatchRejectReason.staleOperation);
    oldLookup.complete(<BarcodeProductInfo>[
      BarcodeProductInfo(id: 10, name: 'Old product'),
    ]);
    await _flush();
    expect(authority.scanTask.phase, WearScanTaskPhase.lookingUp);
    expect(authority.scanTask.barcode, '4600000000007');
    expect(
      authority.state.expectedOperationId(
        WearLookupBarcodeEffect.operationKind,
      ),
      replacementOperationId,
    );

    replacementLookup.complete(const <BarcodeProductInfo>[]);
    await _flush();
    expect(authority.scanTask.phase, WearScanTaskPhase.status);
    expect(authority.scanTask.status?.title, 'Товар не найден');
    replacementDelay.complete();
  });
}

Future<WearRuntimeAuthority> _preparedAuthority() async {
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

Future<void> _flush([int turns = 6]) async {
  for (int index = 0; index < turns; index++) {
    await Future<void>.delayed(Duration.zero);
  }
}
