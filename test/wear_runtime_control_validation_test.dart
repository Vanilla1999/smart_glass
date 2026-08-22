import 'package:flutter_test/flutter_test.dart';
import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_authority.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_store.dart';

void main() {
  test('negative barcode delivery id is rejected before mutation', () async {
    final WearRuntimeAuthority authority = WearRuntimeAuthority();
    addTearDown(authority.dispose);

    final WearDispatchResult result = await authority.store.dispatch(
      const WearBarcodeDeliveryAccepted(
        sessionEpoch: 0,
        deliveryId: -1,
        logicalScreen: WearScreenId.scanIdle,
      ),
    );

    expect(result.accepted, isFalse);
    expect(result.rejectReason, WearDispatchRejectReason.unsupported);
    expect(authority.controls.scanner.lastAcceptedDeliveryId, isNull);
  });

  test('non-positive observation revision is rejected', () async {
    final WearRuntimeAuthority authority = WearRuntimeAuthority();
    addTearDown(authority.dispose);

    final WearDispatchResult result = await authority.store.dispatch(
      const WearConnectivityObserved(
        sessionEpoch: 0,
        observationRevision: 0,
        phase: WearConnectivityPhase.online,
      ),
    );

    expect(result.accepted, isFalse);
    expect(result.rejectReason, WearDispatchRejectReason.unsupported);
    expect(
      authority.controls.connectivity.phase,
      WearConnectivityPhase.unknown,
    );
  });
}
