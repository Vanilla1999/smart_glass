import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_glasses/modules/wear/application/wear_availability_runtime.dart';
import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/domain/auth/model/authenticated_user.dart';
import 'package:smart_glasses/modules/wear/domain/availability/model/wear_availability_flow_state.dart';
import 'package:smart_glasses/modules/wear/domain/availability/model/wear_availability_group.dart';
import 'package:smart_glasses/modules/wear/domain/availability/model/wear_availability_product.dart';
import 'package:smart_glasses/modules/wear/domain/availability/repository/wear_availability_repository.dart';
import 'package:smart_glasses/modules/wear/domain/availability/use_case/wear_availability_flow_use_case.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_authority.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_store.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_availability_slice.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_scan_slice.dart';

void main() {
  test('group loading snapshot is committed before repository completes',
      () async {
    final Completer<List<WearAvailabilityGroup>> groups =
        Completer<List<WearAvailabilityGroup>>();
    final _AvailabilityRepository repository =
        _AvailabilityRepository(groups: () => groups.future);
    final WearRuntimeAuthority authority = WearRuntimeAuthority();
    final WearAvailabilityRuntime runtime = _runtime(authority, repository);
    addTearDown(runtime.dispose);
    addTearDown(authority.dispose);

    await runtime.enterScreen(WearScreenId.availabilityGroup);

    expect(authority.availabilityTask.isBusy, isTrue);
    expect(authority.availabilityTask.flow.groups, isEmpty);

    groups.complete(<WearAvailabilityGroup>[
      const WearAvailabilityGroup(id: 1, name: 'Молоко', counter: 0),
    ]);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(authority.availabilityTask.isBusy, isFalse);
    expect(authority.availabilityTask.flow.groups.single.name, 'Молоко');
  });

  test('direct barcode with duplicates keeps one authoritative list', () async {
    final WearAvailabilityProduct first = product(10, 'Первый');
    final WearAvailabilityProduct second = product(11, 'Второй').copyWith(
      barcodes: <String>['4600000000010'],
    );
    final _AvailabilityRepository repository = _AvailabilityRepository(
      barcodeProducts: <WearAvailabilityProduct>[first, second],
    );
    final WearRuntimeAuthority authority = WearRuntimeAuthority();
    final WearAvailabilityRuntime runtime = _runtime(authority, repository);
    addTearDown(runtime.dispose);
    addTearDown(authority.dispose);

    await runtime.enterScreen(WearScreenId.availabilityDirectScan);
    expect(
      await runtime.handleBarcode(
        WearScreenId.availabilityDirectScan,
        '4600000000010',
      ),
      isTrue,
    );
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    final WearAvailabilityTaskSlice task = authority.availabilityTask;
    expect(task.flow.step, WearAvailabilityFlowStep.duplicateSelection);
    expect(
        task.flow.duplicateProducts, <WearAvailabilityProduct>[first, second]);
    expect(task.listValues.length, 2);
    expect(runtime.state.duplicateProducts.length, 2);
    expect(
        runtime.acceptsBarcode(WearScreenId.availabilityDirectScan), isFalse);
  });

  test('screen change supersedes an older availability operation', () async {
    final Completer<List<WearAvailabilityProduct>> result =
        Completer<List<WearAvailabilityProduct>>();
    final _AvailabilityRepository repository = _AvailabilityRepository(
      findByBarcode: (_) => result.future,
    );
    final WearRuntimeAuthority authority = WearRuntimeAuthority();
    final WearAvailabilityRuntime runtime = _runtime(authority, repository);
    addTearDown(runtime.dispose);
    addTearDown(authority.dispose);

    await runtime.enterScreen(WearScreenId.availabilityDirectScan);
    final Future<bool> scan = runtime.handleBarcode(
      WearScreenId.availabilityDirectScan,
      '4600000000011',
    );
    await Future<void>.delayed(Duration.zero);
    await runtime.enterScreen(WearScreenId.availabilityFill);

    result.complete(<WearAvailabilityProduct>[product(11, 'Старый результат')]);
    await scan;
    await Future<void>.delayed(Duration.zero);

    expect(authority.availabilityTask.screen, WearScreenId.availabilityFill);
    expect(authority.availabilityTask.flow.selectedProduct, isNull);
  });

  test('fill reset blocks barcode until repository reset finishes', () async {
    final Completer<void> reset = Completer<void>();
    int addCalls = 0;
    final _AvailabilityRepository repository = _AvailabilityRepository();
    final WearRuntimeAuthority authority = WearRuntimeAuthority();
    final WearAvailabilityRuntime runtime = WearAvailabilityRuntime(
      authority: authority,
      flowUseCase: WearAvailabilityFlowUseCase(repository),
      navigate: (_, {extra, replaceCurrent = false}) async {},
      capturePhoto: () async {},
      printPriceTag: (_) async => 'printer',
      fillAdd: (_) async {
        addCalls++;
        return <WearAvailabilityProduct>[product(1, 'Добавлен')];
      },
      fillReset: () => reset.future,
    );
    addTearDown(runtime.dispose);
    addTearDown(authority.dispose);

    await runtime.enterScreen(WearScreenId.availabilityFill);
    await runtime.resetFill();
    await Future<void>.delayed(Duration.zero);

    expect(authority.availabilityTask.isBusy, isTrue);
    expect(
      await runtime.handleBarcode(WearScreenId.availabilityFill, '1'),
      isFalse,
    );
    expect(addCalls, 0);

    reset.complete();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(authority.availabilityTask.isBusy, isFalse);
  });

  test('authorization epoch resets printer scan and availability together',
      () async {
    final WearRuntimeAuthority authority = WearRuntimeAuthority();
    final WearAvailabilityRuntime runtime = _runtime(
      authority,
      _AvailabilityRepository(),
    );
    addTearDown(runtime.dispose);
    addTearDown(authority.dispose);

    await runtime.enterScreen(WearScreenId.availabilityFill);
    expect(
      await runtime.handleBarcode(
        WearScreenId.availabilityFill,
        '4600000000012',
      ),
      isTrue,
    );
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(authority.availabilityTask.savedCount, 1);

    final int previousEpoch = authority.state.sessionEpoch;
    final WearDispatchResult result = await authority.authorize(
      AuthenticatedUser(idUser: 1, idEmployee: 2, name: 'Test User'),
    );

    expect(result.accepted, isTrue);
    expect(authority.state.sessionEpoch, previousEpoch + 1);
    expect(authority.availabilityTask.savedCount, 0);
    expect(authority.availabilityTask.phase, WearAvailabilityTaskPhase.idle);
    expect(authority.features.printer.selection, isNull);
    expect(
      (authority.features.scan as WearScanTaskSlice).products,
      isEmpty,
    );
  });
}

WearAvailabilityRuntime _runtime(
  WearRuntimeAuthority authority,
  WearAvailabilityRepository repository,
) {
  return WearAvailabilityRuntime(
    authority: authority,
    flowUseCase: WearAvailabilityFlowUseCase(repository),
    navigate: (_, {extra, replaceCurrent = false}) async {},
    capturePhoto: () async {},
    printPriceTag: (_) async => 'printer',
    fillAdd: (String barcode) async => <WearAvailabilityProduct>[
      product(1, 'Добавлен $barcode'),
    ],
    fillReset: () async {},
  );
}

WearAvailabilityProduct product(int id, String name) {
  return WearAvailabilityProduct(
    id: id,
    groupId: 1,
    name: name,
    code: '$id',
    barcodes: <String>['46000000000$id'],
    priceTagBarcodes: <String>['price-$id'],
    price: 10,
    rest: 1,
    checkPrice: false,
    photoControl: false,
    unpackaged: false,
    priceTagActual: true,
  );
}

class _AvailabilityRepository implements WearAvailabilityRepository {
  _AvailabilityRepository({
    Future<List<WearAvailabilityGroup>> Function()? groups,
    this.barcodeProducts = const <WearAvailabilityProduct>[],
    Future<List<WearAvailabilityProduct>> Function(String)? findByBarcode,
  })  : _groups = groups,
        _findByBarcode = findByBarcode;

  final Future<List<WearAvailabilityGroup>> Function()? _groups;
  final Future<List<WearAvailabilityProduct>> Function(String)? _findByBarcode;
  final List<WearAvailabilityProduct> barcodeProducts;

  @override
  Future<List<WearAvailabilityGroup>> getGroups() async {
    return _groups?.call() ??
        <WearAvailabilityGroup>[
          const WearAvailabilityGroup(id: 1, name: 'Группа', counter: 0),
        ];
  }

  @override
  Future<List<WearAvailabilityProduct>> getProductsByGroup(int groupId) async {
    return barcodeProducts;
  }

  @override
  Future<List<WearAvailabilityProduct>> findProductsByBarcode(
    String barcode,
  ) async {
    return _findByBarcode?.call(barcode) ?? barcodeProducts;
  }

  @override
  Future<WearAvailabilityProduct> upsertScannedProduct({
    required int articleId,
    required String name,
    required String barcode,
    double? rest,
  }) async {
    return product(articleId, name);
  }

  @override
  Future<void> resetScannedProducts() async {}

  @override
  Future<void> completeProduct(int productId) async {}

  @override
  Future<void> resetCompletedProducts() async {}
}
