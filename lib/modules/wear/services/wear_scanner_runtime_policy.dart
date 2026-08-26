import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_authority.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_store.dart';

class WearScannerRuntimeDecision {
  const WearScannerRuntimeDecision({
    required this.barcodeAdmissionEnabled,
    required this.hardwarePrepared,
  });

  final bool barcodeAdmissionEnabled;
  final bool hardwarePrepared;
}

/// Aggregate-state selector used by scanner orchestration.
///
/// Badge authorization is the only supported pre-session barcode flow. It is
/// admitted only while the bounded anonymous runtime is active and both logical
/// and actual phone screens are `main`. Once a session exists, the aggregate
/// control selector applies the normal runtime/lifecycle/background policy.
WearScannerRuntimeDecision resolveWearScannerDecisionFromState(
  WearRuntimeState state, {
  required bool currentScreenAcceptsBarcode,
}) {
  final WearAggregatePayload aggregate =
      state.payloadAs<WearAggregatePayload>();
  final WearRuntimeControlPayload controls =
      aggregate.controls as WearRuntimeControlPayload;
  final bool preAuthMain = !state.terminal &&
      !aggregate.lifecycle.terminal &&
      aggregate.lifecycle.runtimeActive &&
      !aggregate.session.isAuthorized &&
      aggregate.navigation.logicalScreen == WearScreenId.main &&
      aggregate.lifecycle.phoneUiActive &&
      aggregate.navigation.actualPhoneScreen == WearScreenId.main;
  if (preAuthMain) {
    return WearScannerRuntimeDecision(
      hardwarePrepared: true,
      barcodeAdmissionEnabled:
          controls.scanner.hardwarePrepared && currentScreenAcceptsBarcode,
    );
  }

  final WearScannerControlDecision decision = selectScannerControlDecision(
    state,
    screenAcceptsBarcode: currentScreenAcceptsBarcode,
  );
  return WearScannerRuntimeDecision(
    barcodeAdmissionEnabled: decision.barcodeAdmissionEnabled,
    hardwarePrepared: decision.hardwareShouldBePrepared,
  );
}
