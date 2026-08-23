import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_glasses/modules/wear/application/wear_printer_runtime.dart';
import 'package:smart_glasses/modules/wear/application/wear_product_select_args.dart';
import 'package:smart_glasses/modules/wear/application/wear_scan_runtime.dart';
import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/config/wear_mock_config.dart';
import 'package:smart_glasses/modules/wear/config/wear_session.dart';
import 'package:smart_glasses/modules/wear/domain/auth/model/authenticated_user.dart';
import 'package:smart_glasses/modules/wear/domain/price_tag_print/model/barcode_product_info.dart';
import 'package:smart_glasses/modules/wear/models/wear_printer.dart';
import 'package:smart_glasses/modules/wear/models/wear_printer_selection.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/main/cubit/wear_auth_cubit.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/status/wear_status_args.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    dotenv.testLoad(fileInput: 'WEAR_USE_MOCKS=true');
    WearSession.clear();
  });

  tearDown(() {
    WearSession.clear();
    dotenv.clean();
  });

  test('WearMockConfig reads WEAR_USE_MOCKS flag', () {
    expect(WearMockConfig.isEnabled, isTrue);

    dotenv.testLoad(fileInput: 'WEAR_USE_MOCKS=false');

    expect(WearMockConfig.isEnabled, isFalse);
  });

  test('mock auth authorizes user without real auth request', () async {
    final ProviderContainer container = ProviderContainer();
    addTearDown(container.dispose);
    container.listen<WearAuthState>(
      wearAuthNotifierProvider,
      (_, __) {},
    );
    final WearAuthNotifier notifier =
        container.read(wearAuthNotifierProvider.notifier);

    await notifier.authorizeByBadgeBarcode('any-badge');

    expect(WearSession.isAuthorized, isTrue);
    expect(WearSession.userOrNull?.name, 'Колиус');
    expect(notifier.state.phase, WearAuthPhase.idle);
    expect(notifier.state.nav?.kind, WearStatusKind.success);
    expect(notifier.state.nav?.message, 'Колиус');
  });

  test('mock printer loading returns mock printers', () async {
    final WearPrinterRuntime runtime = WearPrinterRuntime(
      loadPrinters: () async => throw StateError('mock loader must not run'),
      navigate: (_, {extra, replaceCurrent = false}) async {},
    );
    addTearDown(runtime.dispose);

    await runtime.enterScreen(WearScreenId.printerSelect);

    expect(runtime.state.phase, WearPrinterRuntimePhase.idle);
    expect(runtime.state.printers, hasLength(3));
    expect(
      runtime.state.printers.map((WearPrinter printer) => printer.name),
      containsAll(<String>[
        'MOCK Белый 1',
        'MOCK Жёлтый 1',
        'MOCK Мобильный 2',
      ]),
    );
  });

  test('mock scan with barcode ending 2 opens product selection', () async {
    WearSession.setUser(_testUser());
    WearSession.setPrinterSelection(_selection());
    WearProductSelectArgs? selection;
    final WearScanRuntime runtime = _runtime((screen, extra) {
      if (screen == WearScreenId.productSelect) {
        selection = extra as WearProductSelectArgs;
      }
    });
    addTearDown(runtime.dispose);

    await runtime.enterScreen(WearScreenId.scanIdle);
    await runtime.handleBarcode(WearScreenId.scanIdle, '2200002');

    expect(runtime.state.phase, WearScanRuntimePhase.selection);
    expect(selection?.barcode, '2200002');
    expect(selection?.products, hasLength(2));
  });

  test('mock print uses yellow printer for even product id', () async {
    WearSession.setUser(_testUser());
    WearSession.setPrinterSelection(_selection());
    WearStatusScreenArgs? status;
    final WearScanRuntime runtime = _runtime((screen, extra) {
      if (screen == WearScreenId.status) {
        status = extra as WearStatusScreenArgs;
      }
    });
    addTearDown(runtime.dispose);

    final BarcodeProductInfo product = BarcodeProductInfo(
      id: 1002002,
      name: 'MOCK Молоко 3,2% 930 мл',
    );
    await runtime.enterScreen(
      WearScreenId.productSelect,
      extra: WearProductSelectArgs(
        barcode: '2200002',
        products: <BarcodeProductInfo>[product],
      ),
    );
    await runtime.selectProduct(product);

    expect(runtime.state.phase, WearScanRuntimePhase.status);
    expect(status?.kind, WearStatusKind.success);
    expect(status?.details, 'MOCK Желтый 1');
  });
}

WearScanRuntime _runtime(
  void Function(WearScreenId screen, Object? extra) onNavigate,
) {
  return WearScanRuntime(
    lookupBarcode: (_) async => const <BarcodeProductInfo>[],
    printProduct: (_) async => 'unused',
    showStatus: (args, completion) async {
      onNavigate(WearScreenId.status, args);
    },
    navigate: (screen, {extra, replaceCurrent = false}) async {
      onNavigate(screen, extra);
    },
  );
}

AuthenticatedUser _testUser() {
  return AuthenticatedUser(
    idUser: 1,
    idEmployee: 2,
    name: 'Mock User',
  );
}

WearPrinterSelection _selection() {
  return const WearPrinterSelection(
    whitePrinter: WearPrinter(id: 'mock-white-1', name: 'MOCK Белый 1'),
    yellowPrinter: WearPrinter(id: 'mock-yellow-1', name: 'MOCK Желтый 1'),
  );
}
