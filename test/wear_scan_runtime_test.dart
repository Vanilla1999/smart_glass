import 'dart:async';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_glasses/modules/wear/application/wear_scan_runtime.dart';
import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/config/wear_session.dart';
import 'package:smart_glasses/modules/wear/domain/auth/model/authenticated_user.dart';
import 'package:smart_glasses/modules/wear/domain/price_tag_print/model/barcode_product_info.dart';
import 'package:smart_glasses/modules/wear/models/wear_printer.dart';
import 'package:smart_glasses/modules/wear/models/wear_printer_selection.dart';

void main() {
  setUp(() {
    dotenv.testLoad(fileInput: 'WEAR_USE_MOCKS=false');
    WearSession.setUser(AuthenticatedUser(
      idUser: 1,
      idEmployee: 2,
      name: 'Test User',
    ));
    WearSession.setPrinterSelection(
      const WearPrinterSelection(
        whitePrinter: WearPrinter(id: '1', name: 'white'),
        yellowPrinter: WearPrinter(id: '2', name: 'yellow'),
      ),
    );
  });

  tearDown(WearSession.clear);

  test('barcode lookup and print run without scan widgets', () async {
    final List<WearScreenId> navigation = <WearScreenId>[];
    var printCalls = 0;
    final WearScanRuntime runtime = WearScanRuntime(
      lookupBarcode: (_) async => <BarcodeProductInfo>[
        BarcodeProductInfo(id: 10, name: 'Товар', articleRest: 4),
      ],
      printProduct: (BarcodeProductInfo product) async {
        printCalls++;
        return 'white';
      },
      navigate: (
        WearScreenId screen, {
        Object? extra,
        bool replaceCurrent = false,
      }) async {
        navigation.add(screen);
      },
    );

    await runtime.enterScreen(WearScreenId.scanIdle);
    expect(
      await runtime.handleBarcode(WearScreenId.scanIdle, '4600000000001'),
      isTrue,
    );

    expect(printCalls, 1);
    expect(navigation, <WearScreenId>[WearScreenId.status]);
    await runtime.dispose();
  });

  test('duplicate lookup exposes runtime voice items', () async {
    final WearScanRuntime runtime = WearScanRuntime(
      lookupBarcode: (_) async => <BarcodeProductInfo>[
        BarcodeProductInfo(id: 10, name: 'Товар первый'),
        BarcodeProductInfo(id: 11, name: 'Товар второй'),
      ],
      printProduct: (_) async => 'white',
      navigate: (
        WearScreenId _, {
        Object? extra,
        bool replaceCurrent = false,
      }) async {},
    );

    await runtime.enterScreen(WearScreenId.scanIdle);
    await runtime.handleBarcode(WearScreenId.scanIdle, '4600000000002');
    await runtime.enterScreen(WearScreenId.productSelect);

    expect(
      runtime
          .dynamicVoiceItemsFor(WearScreenId.productSelect)
          .items
          .map((item) => item.label),
      <String>['Товар первый', 'Товар второй'],
    );
    await runtime.dispose();
  });

  test('reset suppresses completion of an in-flight print', () async {
    final Completer<String> printResult = Completer<String>();
    final List<WearScreenId> navigation = <WearScreenId>[];
    final WearScanRuntime runtime = WearScanRuntime(
      lookupBarcode: (_) async => <BarcodeProductInfo>[
        BarcodeProductInfo(id: 10, name: 'Товар', articleRest: 4),
      ],
      printProduct: (_) => printResult.future,
      navigate: (
        WearScreenId screen, {
        Object? extra,
        bool replaceCurrent = false,
      }) async {
        navigation.add(screen);
      },
    );
    addTearDown(runtime.dispose);
    await runtime.enterScreen(WearScreenId.scanIdle);

    final Future<bool> scan =
        runtime.handleBarcode(WearScreenId.scanIdle, '4600000000003');
    await Future<void>.delayed(Duration.zero);
    await runtime.reset();
    printResult.complete('white');
    await scan;

    expect(navigation, isEmpty);
  });
}
