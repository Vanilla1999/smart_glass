import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_glasses/modules/wear/config/wear_session.dart';
import 'package:smart_glasses/modules/wear/domain/availability/model/wear_availability_group.dart';
import 'package:smart_glasses/modules/wear/domain/availability/model/wear_availability_flow_state.dart';
import 'package:smart_glasses/modules/wear/domain/availability/model/wear_availability_product.dart';
import 'package:smart_glasses/modules/wear/domain/availability/repository/wear_availability_repository.dart';
import 'package:smart_glasses/modules/wear/domain/availability/use_case/wear_availability_flow_use_case.dart';
import 'package:smart_glasses/modules/wear/models/wear_printer.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/printers/cubit/wear_printer_select_cubit.dart';

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

  test('outdated price tag flow requires printing before completion', () {
    final WearAvailabilityFlowUseCase useCase = WearAvailabilityFlowUseCase(
      _FakeAvailabilityRepository(),
    );
    WearAvailabilityFlowState flow = useCase.selectProduct(
      state: const WearAvailabilityFlowState(
        step: WearAvailabilityFlowStep.productSelection,
      ),
      product: _outdatedProduct,
    );

    flow = useCase.answerProductAvailable(flow, available: true);
    flow = useCase.scanProductBarcode(state: flow, barcode: '460700001');
    flow = useCase.scanPriceTagBarcode(state: flow, barcode: '220700001');

    expect(flow.step, WearAvailabilityFlowStep.priceTagOutdated);
    expect(flow.check?.priceTagOutdated, isTrue);
    expect(flow.check?.priceTagPrinted, isFalse);
    expect(flow.check?.canCompletePositive, isFalse);

    flow = useCase.markPriceTagPrinted(state: flow, printerName: 'White');

    expect(flow.step, WearAvailabilityFlowStep.readyToComplete);
    expect(flow.check?.priceTagPrinted, isTrue);
    expect(flow.check?.canCompletePositive, isTrue);
  });

  test('printer selection reset clears previous white and yellow printers', () {
    final WearPrinterSelectNotifier notifier = WearPrinterSelectNotifier();
    addTearDown(notifier.dispose);

    notifier.selectPrinter(const WearPrinter(id: 'white', name: 'White'));
    notifier.selectPrinter(const WearPrinter(id: 'yellow', name: 'Yellow'));

    expect(notifier.state.whitePrinter?.name, 'White');
    expect(notifier.state.yellowPrinter?.name, 'Yellow');

    notifier.resetSelection();

    expect(notifier.state.whitePrinter, isNull);
    expect(notifier.state.yellowPrinter, isNull);
    expect(notifier.state.step, WearPrinterSelectStep.white);
  });
}

const WearAvailabilityProduct _outdatedProduct = WearAvailabilityProduct(
  id: 1002001,
  groupId: 1,
  name: 'Тестовый товар',
  code: '460700001',
  barcodes: <String>['460700001'],
  priceTagBarcodes: <String>['220700001'],
  price: 99.90,
  rest: 3,
  checkPrice: true,
  photoControl: false,
  unpackaged: false,
  priceTagActual: false,
);

class _FakeAvailabilityRepository implements WearAvailabilityRepository {
  @override
  Future<void> completeProduct(int productId) async {}

  @override
  Future<List<WearAvailabilityProduct>> findProductsByBarcode(String barcode) =>
      Future<List<WearAvailabilityProduct>>.value(<WearAvailabilityProduct>[]);

  @override
  Future<List<WearAvailabilityGroup>> getGroups() =>
      Future<List<WearAvailabilityGroup>>.value(<WearAvailabilityGroup>[]);

  @override
  Future<List<WearAvailabilityProduct>> getProductsByGroup(int groupId) =>
      Future<List<WearAvailabilityProduct>>.value(<WearAvailabilityProduct>[]);

  @override
  Future<void> resetCompletedProducts() async {}

  @override
  Future<void> resetScannedProducts() async {}

  @override
  Future<WearAvailabilityProduct> upsertScannedProduct({
    required int articleId,
    required String name,
    required String barcode,
    double? rest,
  }) async {
    return _outdatedProduct;
  }
}
