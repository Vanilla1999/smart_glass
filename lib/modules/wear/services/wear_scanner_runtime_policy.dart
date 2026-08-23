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

WearScannerRuntimeDecision resolveWearScannerRuntimeDecision({
  required bool runtimeTerminated,
  required bool sessionAuthorized,
  required bool phoneUiActive,
  required bool routeMatchesLogicalScreen,
  required bool currentScreenAcceptsBarcode,
}) {
  if (runtimeTerminated) {
    return const WearScannerRuntimeDecision(
      barcodeAdmissionEnabled: false,
      hardwarePrepared: false,
    );
  }
  final bool barcodeAdmissionEnabled = currentScreenAcceptsBarcode &&
      (phoneUiActive ? routeMatchesLogicalScreen : sessionAuthorized);
  return WearScannerRuntimeDecision(
    barcodeAdmissionEnabled: barcodeAdmissionEnabled,
    hardwarePrepared: sessionAuthorized || barcodeAdmissionEnabled,
  );
}

/// Aggregate-state selector used by scanner orchestration.
///
/// Badge authorization is the only supported pre-session barcode flow. It is
/// admitted only while both logical and actual phone screens are `main`. Once a
/// session exists, the aggregate control selector applies the normal
/// runtime/lifecycle/background policy.
WearScannerRuntimeDecision resolveWearScannerDecisionFromState(
  WearRuntimeState state, {
  required bool currentScreenAcceptsBarcode,
}) {
  final WearAggregatePayload aggregate =
      state.payloadAs<WearAggregatePayload>();
  final WearRuntimeControlPayload controls =
      aggregate.controls as WearRuntimeControlPayload;
  final bool preAuthMain = !aggregate.session.isAuthorized &&
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
