import 'package:flutter_test/flutter_test.dart';
import 'package:smart_glasses/modules/wear/application/wear_availability_runtime.dart';
import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/data/availability/local_wear_availability_repository.dart';
import 'package:smart_glasses/modules/wear/domain/availability/model/wear_availability_flow_state.dart';
import 'package:smart_glasses/modules/wear/domain/availability/model/wear_availability_product.dart';
import 'package:smart_glasses/modules/wear/domain/availability/use_case/wear_availability_flow_use_case.dart';

void main() {
  test('camera capture is ignored before photo control step', () async {
    var calls = 0;
    final WearAvailabilityRuntime runtime = _runtime(() async => calls++);
    addTearDown(runtime.dispose);
    await runtime.enterScreen(WearScreenId.availabilityCheck,
        extra: _photoProduct);

    await runtime.takePhoto();

    expect(calls, 0);
    expect(runtime.state.flow.step, WearAvailabilityFlowStep.productQuestion);
  });

  test('successful camera capture completes photo control step', () async {
    var calls = 0;
    final WearAvailabilityRuntime runtime = _runtime(() async => calls++);
    addTearDown(runtime.dispose);
    await runtime.enterScreen(WearScreenId.availabilityCheck,
        extra: _photoProduct);
    await _waitForState(
      runtime,
      (state) => state.flow.step == WearAvailabilityFlowStep.productQuestion,
    );
    expect(runtime.answerAvailable(true), isTrue);
    await _waitForState(
      runtime,
      (state) => state.flow.step == WearAvailabilityFlowStep.photoCapture,
    );

    await runtime.takePhoto();
    await _waitForState(
      runtime,
      (state) =>
          state.flow.check?.photoCaptured == true &&
          state.flow.step == WearAvailabilityFlowStep.readyToComplete,
    );

    expect(calls, 1);
    expect(runtime.state.flow.check?.photoCaptured, isTrue);
    expect(runtime.state.flow.step, WearAvailabilityFlowStep.readyToComplete);
  });

  test('camera error keeps photo control step incomplete', () async {
    final WearAvailabilityRuntime runtime = _runtime(
      () async => throw Exception('camera unavailable'),
    );
    addTearDown(runtime.dispose);
    await runtime.enterScreen(WearScreenId.availabilityCheck,
        extra: _photoProduct);
    await _waitForState(
      runtime,
      (state) => state.flow.step == WearAvailabilityFlowStep.productQuestion,
    );
    expect(runtime.answerAvailable(true), isTrue);
    await _waitForState(
      runtime,
      (state) => state.flow.step == WearAvailabilityFlowStep.photoCapture,
    );

    await runtime.takePhoto();
    await _waitForState(
      runtime,
      (state) =>
          state.flow.step == WearAvailabilityFlowStep.photoCapture &&
          state.flow.check?.photoCaptured == false &&
          state.error == 'camera unavailable',
    );

    expect(runtime.state.flow.step, WearAvailabilityFlowStep.photoCapture);
    expect(runtime.state.flow.check?.photoCaptured, isFalse);
    expect(runtime.state.error, 'camera unavailable');
  });
}

Future<WearAvailabilityRuntimeState> _waitForState(
  WearAvailabilityRuntime runtime,
  bool Function(WearAvailabilityRuntimeState state) predicate,
) {
  final WearAvailabilityRuntimeState current = runtime.state;
  if (predicate(current)) return Future.value(current);
  return runtime.stateStream.firstWhere(predicate);
}

WearAvailabilityRuntime _runtime(Future<void> Function() capture) {
  return WearAvailabilityRuntime(
    flowUseCase: WearAvailabilityFlowUseCase(LocalWearAvailabilityRepository()),
    navigate: (_, {extra, replaceCurrent = false}) async {},
    capturePhoto: capture,
    printPriceTag: (_) async => 'printer',
  );
}

const WearAvailabilityProduct _photoProduct = WearAvailabilityProduct(
  id: 1,
  groupId: 1,
  name: 'Товар с фотоконтролем',
  code: '1',
  barcodes: <String>['1'],
  priceTagBarcodes: <String>[],
  price: 10,
  rest: 1,
  checkPrice: false,
  photoControl: true,
  unpackaged: true,
  priceTagActual: true,
);
