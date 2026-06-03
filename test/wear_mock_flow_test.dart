import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_glasses/modules/wear/config/wear_mock_config.dart';
import 'package:smart_glasses/modules/wear/config/wear_session.dart';
import 'package:smart_glasses/modules/wear/domain/auth/model/authenticated_user.dart';
import 'package:smart_glasses/modules/wear/domain/price_tag_print/model/barcode_product_info.dart';
import 'package:smart_glasses/modules/wear/models/wear_printer.dart';
import 'package:smart_glasses/modules/wear/models/wear_printer_selection.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/main/cubit/wear_auth_cubit.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/printers/cubit/wear_printer_select_cubit.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/scan/cubit/wear_scan_cubit.dart';
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
    final ProviderContainer container = ProviderContainer();
    addTearDown(container.dispose);
    container.listen<WearPrinterSelectState>(
      wearPrinterSelectNotifierProvider,
      (_, __) {},
    );
    final WearPrinterSelectNotifier notifier =
        container.read(wearPrinterSelectNotifierProvider.notifier);

    await Future<void>.delayed(const Duration(milliseconds: 300));

    expect(notifier.state.phase, WearPrinterSelectPhase.idle);
    expect(notifier.state.printers, hasLength(3));
    expect(
      notifier.state.printers.map((WearPrinter printer) => printer.name),
      containsAll(<String>[
        'MOCK Белый 1',
        'MOCK Желтый 1',
        'MOCK Мобильный 2',
      ]),
    );
  });

  test('mock scan with barcode ending 2 opens product selection', () async {
    WearSession.setUser(_testUser());
    final ProviderContainer container = ProviderContainer();
    addTearDown(container.dispose);
    final provider = wearScanNotifierProvider(_selection());
    container.listen<WearScanState>(provider, (_, __) {});
    final WearScanNotifier notifier = container.read(provider.notifier);

    await notifier.handleBarcode('2200002');

    expect(notifier.state.phase, WearScanPhase.idle);
    expect(notifier.state.navSelect?.barcode, '2200002');
    expect(notifier.state.navSelect?.products, hasLength(2));
    expect(notifier.state.navStatus, isNull);
  });

  test('mock print uses yellow printer for even product id', () async {
    WearSession.setUser(_testUser());
    final ProviderContainer container = ProviderContainer();
    addTearDown(container.dispose);
    final provider = wearScanNotifierProvider(_selection());
    container.listen<WearScanState>(provider, (_, __) {});
    final WearScanNotifier notifier = container.read(provider.notifier);

    await notifier.printSelectedProduct(
      BarcodeProductInfo(
        id: 1002002,
        name: 'MOCK Молоко 3,2% 930 мл',
      ),
    );

    expect(notifier.state.phase, WearScanPhase.idle);
    expect(notifier.state.navStatus?.kind, WearStatusKind.success);
    expect(notifier.state.navStatus?.details, 'MOCK: MOCK Желтый 1');
  });
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
