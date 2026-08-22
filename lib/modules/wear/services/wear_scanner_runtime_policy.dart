class WearScannerRuntimeDecision {
  const WearScannerRuntimeDecision({
    required this.barcodeAdmissionEnabled,
    required this.hardwarePrepared,
  });

  final bool barcodeAdmissionEnabled;
  final bool hardwarePrepared;
}

WearScannerRuntimeDecision resolveWearScannerRuntimeDecision({
  required bool sessionAuthorized,
  required bool phoneUiActive,
  required bool routeMatchesLogicalScreen,
  required bool currentScreenAcceptsBarcode,
}) {
  final bool barcodeAdmissionEnabled = currentScreenAcceptsBarcode &&
      (phoneUiActive ? routeMatchesLogicalScreen : sessionAuthorized);
  return WearScannerRuntimeDecision(
    barcodeAdmissionEnabled: barcodeAdmissionEnabled,
    hardwarePrepared: sessionAuthorized || barcodeAdmissionEnabled,
  );
}
