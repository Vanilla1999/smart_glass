import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_glasses/modules/wear/application/wear_printer_runtime.dart';
import 'package:smart_glasses/modules/wear/application/wear_product_select_args.dart';
import 'package:smart_glasses/modules/wear/application/wear_scan_runtime.dart';
import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/config/wear_mock_config.dart';
import 'package:smart_glasses/modules/wear/config/wear_dependencies.dart';
import 'package:smart_glasses/modules/wear/domain/auth/model/authenticated_user.dart';
import 'package:smart_glasses/modules/wear/domain/price_tag_print/model/barcode_product_info.dart';
import 'package:smart_glasses/modules/wear/models/wear_printer.dart';
import 'package:smart_glasses/modules/wear/models/wear_printer_selection.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/main/cubit/wear_auth_cubit.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/status/wear_status_args.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_authority.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_printer_authority.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late WearRuntimeAuthority authority;

  setUp(() async {
    dotenv.testLoad(fileInput: 'WEAR_USE_MOCKS=true');
    authority = WearRuntimeAuthority();
    await WearDependencies.I.authority.clearSession();
  });

  tearDown(() async {
    await authority.dispose();
    await WearDependencies.I.authority.clearSession();
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

    expect(WearDependencies.I.authority.isAuthorized, isTrue);
    expect(WearDependencies.I.authority.userOrNull?.name, 'Колиус');
    expect(notifier.state.phase, WearAuthPhase.idle);
    expect(notifier.state.nav?.kind, WearStatusKind.success);
    expect(notifier.state.nav?.message, 'Колиус');
  });

  test('mock printer loading returns mock printers', () async {
    final WearPrinterRuntime runtime = WearPrinterRuntime(
      authority: authority,
      loadPrinters: () async => throw StateError('mock loader must not run'),
      navigate: (_, {extra, replaceCurrent = false}) async {},
    );
    addTearDown(runtime.dispose);

    await authority.requestNavigation(WearScreenId.printerSelect);
    await runtime.enterScreen(WearScreenId.printerSelect);

    expect(runtime.state.phase, WearPrinterRuntimePhase.ready);
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
    await authority.authorize(_testUser());
    await authority.importPrinterSelection(_selection());
    await authority.requestNavigation(WearScreenId.scanIdle);
    WearProductSelectArgs? selection;
    final WearScanRuntime runtime = _runtime(authority, (screen, extra) {
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
    await authority.authorize(_testUser());
    await authority.importPrinterSelection(_selection());
    await authority.requestNavigation(WearScreenId.scanIdle);
    WearStatusScreenArgs? status;
    final WearScanRuntime runtime = _runtime(authority, (screen, extra) {
      if (screen == WearScreenId.status) {
        status = extra as WearStatusScreenArgs;
      }
    });
    addTearDown(runtime.dispose);

    await runtime.enterScreen(WearScreenId.scanIdle);
    await runtime.handleBarcode(WearScreenId.scanIdle, '2200002');
    final BarcodeProductInfo product = runtime.state.products.firstWhere(
      (BarcodeProductInfo item) => item.id.isEven,
    );
    await runtime.selectProduct(product);

    expect(runtime.state.phase, WearScanRuntimePhase.status);
    expect(status?.kind, WearStatusKind.success);
    expect(status?.details, 'MOCK Желтый 1');
  });
}

WearScanRuntime _runtime(
  WearRuntimeAuthority authority,
  void Function(WearScreenId screen, Object? extra) onNavigate,
) {
  return WearScanRuntime(
    authority: authority,
    lookupBarcode: (_) async => const <BarcodeProductInfo>[],
    printProduct: (_, __) async => 'unused',
    showStatus: (args, {required completion}) async {
      onNavigate(WearScreenId.status, args);
    },
    navigate: (screen, {extra, replaceCurrent = false}) async {
      onNavigate(screen, extra);
    },
    delay: (_) async {},
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
