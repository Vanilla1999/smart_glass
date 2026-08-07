import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_glasses/modules/wear/application/wear_availability_runtime.dart';
import 'package:smart_glasses/modules/wear/application/wear_background_runtime.dart';
import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/domain/availability/model/wear_availability_group.dart';
import 'package:smart_glasses/modules/wear/domain/availability/model/wear_availability_product.dart';
import 'package:smart_glasses/modules/wear/domain/availability/model/wear_availability_flow_state.dart';
import 'package:smart_glasses/modules/wear/domain/availability/repository/wear_availability_repository.dart';
import 'package:smart_glasses/modules/wear/domain/availability/use_case/wear_availability_flow_use_case.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/wear_voice_command.dart';
import 'package:smart_glasses/modules/wear/presentation/glasses/wear_glasses_payload.dart';

void main() {
  test('coalesces duplicate screen entry while groups are loading', () async {
    final _BlockingAvailabilityRepository repository =
        _BlockingAvailabilityRepository();
    final WearAvailabilityRuntime runtime = _runtime(repository);
    addTearDown(runtime.dispose);

    final Future<void> first =
        runtime.enterScreen(WearScreenId.availabilityGroup);
    final Future<void> second =
        runtime.enterScreen(WearScreenId.availabilityGroup);
    await Future<void>.delayed(Duration.zero);

    expect(repository.groupCalls, 1);
    repository.groups.complete(
      const <WearAvailabilityGroup>[_AvailabilityRepository.group],
    );
    await Future.wait(<Future<void>>[first, second]);
  });

  test('reset starts a fresh availability flow', () async {
    final _AvailabilityRepository repository = _AvailabilityRepository();
    final WearAvailabilityRuntime runtime = _runtime(repository);
    addTearDown(runtime.dispose);

    await runtime.enterScreen(WearScreenId.availabilityGroup);
    await runtime.reset();
    await runtime.enterScreen(WearScreenId.availabilityGroup);

    expect(repository.groupCalls, 2);
  });

  test('reset suppresses navigation from an in-flight group selection',
      () async {
    final _BlockingProductsAvailabilityRepository repository =
        _BlockingProductsAvailabilityRepository();
    final List<WearScreenId> navigation = <WearScreenId>[];
    final WearAvailabilityRuntime runtime = WearAvailabilityRuntime(
      flowUseCase: WearAvailabilityFlowUseCase(repository),
      navigate: (
        WearScreenId screen, {
        Object? extra,
        bool replaceCurrent = false,
      }) async {
        navigation.add(screen);
      },
      capturePhoto: () async {},
      printPriceTag: (_) async => 'printer',
    );
    addTearDown(runtime.dispose);

    await runtime.enterScreen(WearScreenId.availabilityGroup);
    final Future<bool> selection = runtime.handleCommand(
      WearScreenId.availabilityGroup,
      WearVoiceCommand.select,
    );
    await Future<void>.delayed(Duration.zero);
    await runtime.reset();
    repository.products.complete(
      const <WearAvailabilityProduct>[_AvailabilityRepository.product],
    );
    await selection;

    expect(navigation, isEmpty);
  });

  test('new screen request suppresses an in-flight selection navigation',
      () async {
    final _BlockingProductsAvailabilityRepository repository =
        _BlockingProductsAvailabilityRepository();
    final List<WearScreenId> navigation = <WearScreenId>[];
    final WearAvailabilityRuntime runtime = WearAvailabilityRuntime(
      flowUseCase: WearAvailabilityFlowUseCase(repository),
      navigate: (
        WearScreenId screen, {
        Object? extra,
        bool replaceCurrent = false,
      }) async {
        navigation.add(screen);
      },
      capturePhoto: () async {},
      printPriceTag: (_) async => 'printer',
    );
    addTearDown(runtime.dispose);

    await runtime.enterScreen(WearScreenId.availabilityGroup);
    final Future<bool> selection = runtime.handleCommand(
      WearScreenId.availabilityGroup,
      WearVoiceCommand.select,
    );
    await Future<void>.delayed(Duration.zero);
    await runtime.enterScreen(WearScreenId.availabilityDirectScan);
    repository.products.complete(
      const <WearAvailabilityProduct>[_AvailabilityRepository.product],
    );
    await selection;

    expect(navigation, isEmpty);
  });

  test('presentation handoff invalidates an older screen load', () async {
    final _BlockingAvailabilityRepository repository =
        _BlockingAvailabilityRepository();
    final WearAvailabilityFlowUseCase useCase =
        WearAvailabilityFlowUseCase(repository);
    final WearAvailabilityRuntime runtime = _runtime(repository);
    addTearDown(runtime.dispose);

    final Future<void> oldLoad =
        runtime.enterScreen(WearScreenId.availabilityGroup);
    await Future<void>.delayed(Duration.zero);
    final WearAvailabilityFlowState activeFlow = useCase.selectProduct(
      state: const WearAvailabilityFlowState(
        step: WearAvailabilityFlowStep.productSelection,
      ),
      product: _AvailabilityRepository.product,
    );
    runtime.restorePresentationState(
      WearScreenId.availabilityCheck,
      WearAvailabilityRuntimeState(flow: activeFlow, focusedIndex: 0),
    );
    repository.groups.complete(
      const <WearAvailabilityGroup>[_AvailabilityRepository.group],
    );
    await oldLoad;

    final WearAvailabilityRuntimeState restored = runtime.presentationStateFor(
      WearScreenId.availabilityCheck,
    )! as WearAvailabilityRuntimeState;
    expect(restored.flow.selectedProduct, _AvailabilityRepository.product);
    expect(restored.flow.step, WearAvailabilityFlowStep.productQuestion);
  });

  test('direct scan failure can retry the same barcode', () async {
    final _RetryAvailabilityRepository repository =
        _RetryAvailabilityRepository();
    final WearAvailabilityRuntime runtime = _runtime(repository);
    addTearDown(runtime.dispose);
    await runtime.enterScreen(WearScreenId.availabilityDirectScan);

    expect(
      await runtime.handleBarcode(
        WearScreenId.availabilityDirectScan,
        _AvailabilityRepository.product.code,
      ),
      isTrue,
    );
    expect(
      await runtime.handleBarcode(
        WearScreenId.availabilityDirectScan,
        _AvailabilityRepository.product.code,
      ),
      isTrue,
    );

    expect(repository.barcodeCalls, 2);
  });

  test('direct scan publishes scanning payload before the flow is loaded',
      () async {
    final WearAvailabilityRuntime runtime = _runtime(_AvailabilityRepository());
    addTearDown(runtime.dispose);
    final List<WearBackgroundScreenUpdate> updates =
        <WearBackgroundScreenUpdate>[];
    final StreamSubscription<WearBackgroundScreenUpdate> subscription =
        runtime.updates.listen(updates.add);
    addTearDown(subscription.cancel);

    await runtime.enterScreen(WearScreenId.availabilityDirectScan);

    expect(updates, isNotEmpty);
    expect(updates.last.payload.phase, WearGlassesPhase.scanning);
    expect(updates.last.payload.statusText, 'Поиск ШК...');
  });

  test('loads groups and products without providers or widgets', () async {
    final _AvailabilityRepository repository = _AvailabilityRepository();
    final List<WearScreenId> navigation = <WearScreenId>[];
    final WearAvailabilityRuntime runtime = WearAvailabilityRuntime(
      flowUseCase: WearAvailabilityFlowUseCase(repository),
      navigate: (
        WearScreenId screen, {
        Object? extra,
        bool replaceCurrent = false,
      }) async {
        navigation.add(screen);
      },
      capturePhoto: () async {},
      printPriceTag: (_) async => 'printer',
    );
    addTearDown(runtime.dispose);

    await runtime.enterScreen(WearScreenId.availabilityGroup);
    expect(
      runtime
          .dynamicVoiceItemsFor(WearScreenId.availabilityGroup)
          .items
          .single
          .label,
      'Молоко',
    );

    await runtime.handleCommand(
      WearScreenId.availabilityGroup,
      WearVoiceCommand.select,
    );
    await runtime.enterScreen(
      WearScreenId.availabilityProduct,
      extra: _AvailabilityRepository.group,
    );

    expect(navigation.last, WearScreenId.availabilityProduct);
    expect(
      runtime
          .dynamicVoiceItemsFor(WearScreenId.availabilityProduct)
          .items
          .single
          .label,
      'Молоко 3.2%',
    );
  });

  test('runs answer, photo, and completion in application runtime', () async {
    final _AvailabilityRepository repository = _AvailabilityRepository();
    var photoCalls = 0;
    final List<WearScreenId> navigation = <WearScreenId>[];
    final WearAvailabilityRuntime runtime = WearAvailabilityRuntime(
      flowUseCase: WearAvailabilityFlowUseCase(repository),
      navigate: (
        WearScreenId screen, {
        Object? extra,
        bool replaceCurrent = false,
      }) async {
        navigation.add(screen);
      },
      capturePhoto: () async {
        photoCalls++;
      },
      printPriceTag: (_) async => 'printer',
    );
    addTearDown(runtime.dispose);

    await runtime.enterScreen(WearScreenId.availabilityGroup);
    await runtime.handleCommand(
      WearScreenId.availabilityGroup,
      WearVoiceCommand.select,
    );
    await runtime.enterScreen(
      WearScreenId.availabilityProduct,
      extra: _AvailabilityRepository.group,
    );
    await runtime.handleCommand(
      WearScreenId.availabilityProduct,
      WearVoiceCommand.select,
    );
    await runtime.enterScreen(
      WearScreenId.availabilityCheck,
      extra: _AvailabilityRepository.product,
    );
    await runtime.handleCommand(
      WearScreenId.availabilityCheck,
      WearVoiceCommand.yes,
    );
    await runtime.handleCommand(
      WearScreenId.availabilityCheck,
      WearVoiceCommand.takePhoto,
    );
    await runtime.handleCommand(
      WearScreenId.availabilityCheck,
      WearVoiceCommand.finish,
    );

    expect(photoCalls, 1);
    expect(repository.completedProductIds, <int>[10]);
    expect(navigation.last, WearScreenId.availabilityGroup);
  });

  test('screen-off handoff continues availability question state', () async {
    final _AvailabilityRepository repository = _AvailabilityRepository();
    final WearAvailabilityFlowUseCase useCase =
        WearAvailabilityFlowUseCase(repository);
    final WearAvailabilityRuntime runtime = _runtime(repository);
    addTearDown(runtime.dispose);
    final WearAvailabilityFlowState activeFlow = useCase.selectProduct(
      state: const WearAvailabilityFlowState(
        step: WearAvailabilityFlowStep.productSelection,
      ),
      product: _AvailabilityRepository.product,
    );

    runtime.restorePresentationState(
      WearScreenId.availabilityCheck,
      WearAvailabilityRuntimeState(flow: activeFlow, focusedIndex: 0),
    );
    await runtime.handleCommand(
      WearScreenId.availabilityCheck,
      WearVoiceCommand.no,
    );
    final WearAvailabilityRuntimeState restored = runtime.presentationStateFor(
      WearScreenId.availabilityCheck,
    )! as WearAvailabilityRuntimeState;

    expect(
      restored.flow.step,
      WearAvailabilityFlowStep.manualInventoryRequired,
    );
    expect(restored.flow.selectedProduct, _AvailabilityRepository.product);
  });
}

WearAvailabilityRuntime _runtime(WearAvailabilityRepository repository) {
  return WearAvailabilityRuntime(
    flowUseCase: WearAvailabilityFlowUseCase(repository),
    navigate: (
      WearScreenId _, {
      Object? extra,
      bool replaceCurrent = false,
    }) async {},
    capturePhoto: () async {},
    printPriceTag: (_) async => 'printer',
  );
}

class _AvailabilityRepository implements WearAvailabilityRepository {
  static const WearAvailabilityGroup group = WearAvailabilityGroup(
    id: 1,
    name: 'Молоко',
    counter: 1,
  );
  static const WearAvailabilityProduct product = WearAvailabilityProduct(
    id: 10,
    groupId: 1,
    name: 'Молоко 3.2%',
    code: '4600000000010',
    barcodes: <String>['4600000000010'],
    priceTagBarcodes: <String>[],
    price: 99,
    rest: 3,
    checkPrice: false,
    photoControl: true,
    unpackaged: true,
    priceTagActual: true,
  );

  final List<int> completedProductIds = <int>[];
  int groupCalls = 0;

  @override
  Future<void> completeProduct(int productId) async {
    completedProductIds.add(productId);
  }

  @override
  Future<List<WearAvailabilityProduct>> findProductsByBarcode(
    String barcode,
  ) async {
    return product.matchesProductBarcode(barcode)
        ? <WearAvailabilityProduct>[product]
        : <WearAvailabilityProduct>[];
  }

  @override
  Future<List<WearAvailabilityGroup>> getGroups() async {
    groupCalls++;
    return const <WearAvailabilityGroup>[group];
  }

  @override
  Future<List<WearAvailabilityProduct>> getProductsByGroup(int groupId) async {
    return groupId == group.id
        ? const <WearAvailabilityProduct>[product]
        : const <WearAvailabilityProduct>[];
  }

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
    return product;
  }
}

class _BlockingAvailabilityRepository extends _AvailabilityRepository {
  final Completer<List<WearAvailabilityGroup>> groups =
      Completer<List<WearAvailabilityGroup>>();

  @override
  Future<List<WearAvailabilityGroup>> getGroups() {
    groupCalls++;
    return groups.future;
  }
}

class _RetryAvailabilityRepository extends _AvailabilityRepository {
  int barcodeCalls = 0;

  @override
  Future<List<WearAvailabilityProduct>> findProductsByBarcode(
    String barcode,
  ) async {
    barcodeCalls++;
    if (barcodeCalls == 1) throw Exception('temporary failure');
    return super.findProductsByBarcode(barcode);
  }
}

class _BlockingProductsAvailabilityRepository extends _AvailabilityRepository {
  final Completer<List<WearAvailabilityProduct>> products =
      Completer<List<WearAvailabilityProduct>>();

  @override
  Future<List<WearAvailabilityProduct>> getProductsByGroup(int groupId) {
    return products.future;
  }
}
