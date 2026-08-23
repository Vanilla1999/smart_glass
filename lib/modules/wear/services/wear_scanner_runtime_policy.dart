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

/// Aggregate-state selector used by migrated scanner orchestration.
///
/// The legacy argument-based policy above remains as a compatibility adapter
/// until MR-S9; both are kept side-by-side so behavior can be compared.
WearScannerRuntimeDecision resolveWearScannerDecisionFromState(
  WearRuntimeState state, {
  required bool currentScreenAcceptsBarcode,
}) {
  final WearScannerControlDecision decision = selectScannerControlDecision(
    state,
    screenAcceptsBarcode: currentScreenAcceptsBarcode,
  );
  return WearScannerRuntimeDecision(
    barcodeAdmissionEnabled: decision.barcodeAdmissionEnabled,
    hardwarePrepared: decision.hardwareShouldBePrepared,
  );
}
