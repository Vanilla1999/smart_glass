import 'dart:async';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_glasses/modules/wear/application/wear_product_select_args.dart';
import 'package:smart_glasses/modules/wear/application/wear_scan_runtime.dart';
import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/application/wear_status_state.dart';
import 'package:smart_glasses/modules/wear/config/wear_dependencies.dart';
import 'package:smart_glasses/modules/wear/domain/auth/model/authenticated_user.dart';
import 'package:smart_glasses/modules/wear/domain/price_tag_print/model/barcode_product_info.dart';
import 'package:smart_glasses/modules/wear/models/wear_printer.dart';
import 'package:smart_glasses/modules/wear/models/wear_printer_selection.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_authority.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_printer_authority.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late WearRuntimeAuthority authority;

  setUp(() async {
    dotenv.testLoad(fileInput: 'WEAR_USE_MOCKS=false');
    authority = WearRuntimeAuthority();
    await authority.authorize(AuthenticatedUser(
      idUser: 1,
      idEmployee: 2,
      name: 'Test User',
    ));
    await authority.importPrinterSelection(
      const WearPrinterSelection(
        whitePrinter: WearPrinter(id: '1', name: 'white'),
        yellowPrinter: WearPrinter(id: '2', name: 'yellow'),
      ),
    );
    await authority.requestNavigation(WearScreenId.scanIdle);
  });

  tearDown(() => authority.dispose());

  test('barcode lookup and print run without scan widgets', () async {
    final List<WearScreenId> navigation = <WearScreenId>[];
    var printCalls = 0;
    final WearScanRuntime runtime = WearScanRuntime(
      authority: authority,
      lookupBarcode: (_) async => <BarcodeProductInfo>[
        BarcodeProductInfo(id: 10, name: 'Товар', articleRest: 4),
      ],
      printProduct: (BarcodeProductInfo product, _) async {
        printCalls++;
        return 'white';
      },
      showStatus: (args, {required completion}) async {
        navigation.add(WearScreenId.status);
      },
      navigate: (
        WearScreenId screen, {
        Object? extra,
        bool replaceCurrent = false,
      }) async {
        navigation.add(screen);
      },
      delay: (_) async {},
    );

    await runtime.enterScreen(WearScreenId.scanIdle);
    expect(
      await runtime.handleBarcode(WearScreenId.scanIdle, '4600000000001'),
      isTrue,
    );
    await _flush();

    expect(printCalls, 1);
    expect(
      navigation,
      <WearScreenId>[WearScreenId.status, WearScreenId.scanIdle],
    );
    await runtime.dispose();
  });

  test('duplicate lookup exposes runtime voice items', () async {
    final WearScanRuntime runtime = WearScanRuntime(
      authority: authority,
      lookupBarcode: (_) async => <BarcodeProductInfo>[
        BarcodeProductInfo(id: 10, name: 'Товар первый'),
        BarcodeProductInfo(id: 11, name: 'Товар второй'),
      ],
      printProduct: (_, __) async => 'white',
      showStatus: (args, {required completion}) async {},
      navigate: (
        WearScreenId _, {
        Object? extra,
        bool replaceCurrent = false,
      }) async {},
      delay: (_) async {},
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
      authority: authority,
      lookupBarcode: (_) async => <BarcodeProductInfo>[
        BarcodeProductInfo(id: 10, name: 'Товар', articleRest: 4),
      ],
      printProduct: (_, __) => printResult.future,
      showStatus: (args, {required completion}) async {
        navigation.add(WearScreenId.status);
      },
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

  test('print status declares an explicit scan completion target', () async {
    WearStatusCompletion? statusCompletion;
    final WearScanRuntime runtime = WearScanRuntime(
      authority: authority,
      lookupBarcode: (_) async => <BarcodeProductInfo>[
        BarcodeProductInfo(id: 10, name: 'Товар', articleRest: 4),
      ],
      printProduct: (_, __) async => 'white',
      showStatus: (args, {required completion}) async {
        statusCompletion = completion;
      },
      navigate: (
        WearScreenId _, {
        Object? extra,
        bool replaceCurrent = false,
      }) async {},
      delay: (_) async {},
    );
    addTearDown(runtime.dispose);

    await runtime.enterScreen(WearScreenId.scanIdle);
    await runtime.handleBarcode(WearScreenId.scanIdle, '4600000000004');
    await _flush();
    expect(statusCompletion?.kind, WearStatusCompletionKind.stay);
    expect(statusCompletion?.target, isNull);
  });

  test('repeated barcode during lookup starts one request', () async {
    final Completer<List<BarcodeProductInfo>> lookup =
        Completer<List<BarcodeProductInfo>>();
    var lookupCalls = 0;
    final WearScanRuntime runtime = WearScanRuntime(
      authority: authority,
      lookupBarcode: (_) {
        lookupCalls++;
        return lookup.future;
      },
      printProduct: (_, __) async => 'white',
      showStatus: (args, {required completion}) async {},
      navigate: (_, {extra, replaceCurrent = false}) async {},
    );
    addTearDown(runtime.dispose);
    await runtime.enterScreen(WearScreenId.scanIdle);

    final Future<bool> first =
        runtime.handleBarcode(WearScreenId.scanIdle, '4600000000006');
    await Future<void>.delayed(Duration.zero);
    final bool second =
        await runtime.handleBarcode(WearScreenId.scanIdle, '4600000000006');

    expect(second, isFalse);
    expect(lookupCalls, 1);
    expect(runtime.state.phase, WearScanRuntimePhase.loading);
    expect(runtime.state.lastAcceptedBarcode, '4600000000006');

    lookup.complete(const <BarcodeProductInfo>[]);
    await first;
  });

  test('state stream exposes selection focus and products', () async {
    final WearScanRuntime runtime = WearScanRuntime(
      authority: authority,
      lookupBarcode: (_) async => <BarcodeProductInfo>[
        BarcodeProductInfo(id: 10, name: 'Первый'),
        BarcodeProductInfo(id: 11, name: 'Второй'),
      ],
      printProduct: (_, __) async => 'white',
      showStatus: (args, {required completion}) async {},
      navigate: (_, {extra, replaceCurrent = false}) async {},
    );
    addTearDown(runtime.dispose);
    await runtime.enterScreen(WearScreenId.scanIdle);
    await runtime.handleBarcode(WearScreenId.scanIdle, '4600000000007');
    await runtime.enterScreen(
      WearScreenId.productSelect,
      extra: WearProductSelectArgs(
        barcode: '4600000000007',
        products: runtime.state.products,
      ),
    );

    runtime.setFocusedIndex(1);

    expect(runtime.state.phase, WearScanRuntimePhase.selection);
    expect(runtime.state.focusedIndex, 1);
    expect(runtime.state.products.map((product) => product.name),
        <String>['Первый', 'Второй']);
  });
}

Future<void> _flush() async {
  for (int index = 0; index < 6; index++) {
    await Future<void>.delayed(Duration.zero);
  }
}
