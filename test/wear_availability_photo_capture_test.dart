import 'package:flutter_test/flutter_test.dart';
import 'package:smart_glasses/modules/wear/data/availability/local_wear_availability_repository.dart';
import 'package:smart_glasses/modules/wear/domain/availability/model/wear_availability_flow_state.dart';
import 'package:smart_glasses/modules/wear/domain/availability/model/wear_availability_product.dart';
import 'package:smart_glasses/modules/wear/domain/availability/use_case/wear_availability_flow_use_case.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/availability/cubit/wear_availability_check_cubit.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/status/wear_status_args.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('camera capture is ignored before photo control step', () async {
    var captureCalls = 0;
    final WearAvailabilityCheckNotifier notifier =
        WearAvailabilityCheckNotifier(
      _photoProduct,
      capturePhoto: () async {
        captureCalls++;
        return '/app/latest_photo';
      },
      flowUseCase: _flowUseCase(),
    );
    addTearDown(notifier.dispose);

    await notifier.capturePhoto();

    expect(captureCalls, 0);
    expect(notifier.state.flow.step, WearAvailabilityFlowStep.productQuestion);
    expect(notifier.state.flow.check?.photoCaptured, isFalse);
  });

  test('successful camera capture completes photo control step', () async {
    var captureCalls = 0;
    final WearAvailabilityCheckNotifier notifier =
        WearAvailabilityCheckNotifier(
      _photoProduct,
      capturePhoto: () async {
        captureCalls++;
        return '/app/latest_photo';
      },
      flowUseCase: _flowUseCase(),
    );
    addTearDown(notifier.dispose);
    notifier.answerProductAvailable(true);

    expect(notifier.state.flow.step, WearAvailabilityFlowStep.photoCapture);
    await notifier.capturePhoto();

    expect(captureCalls, 1);
    expect(notifier.state.flow.check?.photoCaptured, isTrue);
    expect(notifier.state.flow.step, WearAvailabilityFlowStep.readyToComplete);
  });

  test('camera error keeps photo control step incomplete', () async {
    final WearAvailabilityCheckNotifier notifier =
        WearAvailabilityCheckNotifier(
      _photoProduct,
      capturePhoto: () async => throw Exception('camera unavailable'),
      flowUseCase: _flowUseCase(),
    );
    addTearDown(notifier.dispose);
    notifier.answerProductAvailable(true);

    await notifier.capturePhoto();

    expect(notifier.state.flow.step, WearAvailabilityFlowStep.photoCapture);
    expect(notifier.state.flow.check?.photoCaptured, isFalse);
    expect(notifier.state.navStatus?.kind, WearStatusKind.error);
    expect(notifier.state.navStatus?.message, 'camera unavailable');
  });
}

WearAvailabilityFlowUseCase _flowUseCase() =>
    WearAvailabilityFlowUseCase(LocalWearAvailabilityRepository());

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
