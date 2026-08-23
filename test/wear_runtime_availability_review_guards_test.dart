import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_glasses/modules/wear/application/wear_availability_runtime.dart';
import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/domain/availability/model/wear_availability_group.dart';
import 'package:smart_glasses/modules/wear/domain/availability/model/wear_availability_product.dart';
import 'package:smart_glasses/modules/wear/domain/availability/repository/wear_availability_repository.dart';
import 'package:smart_glasses/modules/wear/domain/availability/use_case/wear_availability_flow_use_case.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_authority.dart';

void main() {
  test('single direct-scan result navigates with product route extra', () async {
    final WearAvailabilityProduct expected = _product(10, 'Товар');
    final _Repository repository = _Repository(
      find: (_) async => <WearAvailabilityProduct>[expected],
    );
    Object? navigationExtra;
    final WearRuntimeAuthority authority = WearRuntimeAuthority();
    final WearAvailabilityRuntime runtime = _runtime(
      authority,
      repository,
      navigate: (_, {extra, replaceCurrent = false}) async {
        navigationExtra = extra;
      },
    );
    addTearDown(() async {
      await runtime.dispose();
      await authority.dispose();
    });

    await runtime.enterScreen(WearScreenId.availabilityDirectScan);
    await runtime.handleBarcode(
      WearScreenId.availabilityDirectScan,
      '4600000000010',
    );
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(navigationExtra, same(expected));
  });

  test('same-screen attachment cannot restart active direct lookup', () async {
    final Completer<List<WearAvailabilityProduct>> lookup =
        Completer<List<WearAvailabilityProduct>>();
    int lookupCalls = 0;
    final _Repository repository = _Repository(find: (_) {
      lookupCalls++;
      return lookup.future;
    });
    final WearRuntimeAuthority authority = WearRuntimeAuthority();
    final WearAvailabilityRuntime runtime = _runtime(authority, repository);
    addTearDown(() async {
      if (!lookup.isCompleted) lookup.complete(const <WearAvailabilityProduct>[]);
      await runtime.dispose();
      await authority.dispose();
    });

    await runtime.enterScreen(WearScreenId.availabilityDirectScan);
    await runtime.handleBarcode(
      WearScreenId.availabilityDirectScan,
      '4600000000011',
    );
    await Future<void>.delayed(Duration.zero);
    expect(authority.availabilityTask.isBusy, isTrue);

    await runtime.enterScreen(WearScreenId.availabilityDirectScan);
    expect(lookupCalls, 1);
    expect(authority.availabilityTask.isBusy, isTrue);

    lookup.complete(const <WearAvailabilityProduct>[]);
  });

  test('one authority rejects two active availability effect leases', () async {
    final WearRuntimeAuthority authority = WearRuntimeAuthority();
    final _Repository repository = _Repository();
    final WearAvailabilityRuntime first = _runtime(authority, repository);
    addTearDown(() async {
      await first.dispose();
      await authority.dispose();
    });

    expect(
      () => _runtime(authority, repository),
      throwsStateError,
    );
  });
}

WearAvailabilityRuntime _runtime(
  WearRuntimeAuthority authority,
  WearAvailabilityRepository repository, {
  Future<void> Function(
    WearScreenId screen, {
    Object? extra,
    bool replaceCurrent,
  })? navigate,
}) {
  return WearAvailabilityRuntime(
    authority: authority,
    flowUseCase: WearAvailabilityFlowUseCase(repository),
    navigate: navigate ?? (_, {extra, replaceCurrent = false}) async {},
    capturePhoto: () async {},
    printPriceTag: (_) async => 'printer',
    fillAdd: (_) async => const <WearAvailabilityProduct>[],
    fillReset: () async {},
  );
}

WearAvailabilityProduct _product(int id, String name) {
  return WearAvailabilityProduct(
    id: id,
    groupId: 1,
    name: name,
    code: '$id',
    barcodes: <String>['46000000000$id'],
    priceTagBarcodes: <String>['price-$id'],
    price: 1,
    rest: 1,
    checkPrice: false,
    photoControl: false,
    unpackaged: false,
    priceTagActual: true,
  );
}

class _Repository implements WearAvailabilityRepository {
  _Repository({
    Future<List<WearAvailabilityProduct>> Function(String)? find,
  }) : _find = find;

  final Future<List<WearAvailabilityProduct>> Function(String)? _find;

  @override
  Future<List<WearAvailabilityGroup>> getGroups() async =>
      const <WearAvailabilityGroup>[];

  @override
  Future<List<WearAvailabilityProduct>> getProductsByGroup(int groupId) async =>
      const <WearAvailabilityProduct>[];

  @override
  Future<List<WearAvailabilityProduct>> findProductsByBarcode(
    String barcode,
  ) async {
    return _find?.call(barcode) ?? const <WearAvailabilityProduct>[];
  }

  @override
  Future<WearAvailabilityProduct> upsertScannedProduct({
    required int articleId,
    required String name,
    required String barcode,
    double? rest,
  }) async {
    return _product(articleId, name);
  }

  @override
  Future<void> resetScannedProducts() async {}

  @override
  Future<void> completeProduct(int productId) async {}

  @override
  Future<void> resetCompletedProducts() async {}
}
