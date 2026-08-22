import 'package:flutter_test/flutter_test.dart';
import 'package:smart_glasses/modules/wear/services/wear_scanner_runtime_policy.dart';

void main() {
  test('pre-auth scanner requires the actual route to match logical state', () {
    final WearScannerRuntimeDecision decision =
        resolveWearScannerRuntimeDecision(
      runtimeTerminated: false,
      sessionAuthorized: false,
      phoneUiActive: true,
      routeMatchesLogicalScreen: false,
      currentScreenAcceptsBarcode: true,
    );

    expect(decision.barcodeAdmissionEnabled, isFalse);
    expect(decision.hardwarePrepared, isFalse);
  });

  test('pre-auth matching route enables scanner admission', () {
    final WearScannerRuntimeDecision decision =
        resolveWearScannerRuntimeDecision(
      runtimeTerminated: false,
      sessionAuthorized: false,
      phoneUiActive: true,
      routeMatchesLogicalScreen: true,
      currentScreenAcceptsBarcode: true,
    );

    expect(decision.barcodeAdmissionEnabled, isTrue);
    expect(decision.hardwarePrepared, isTrue);
  });

  test('background logical state admits barcode while phone route lags', () {
    final WearScannerRuntimeDecision decision =
        resolveWearScannerRuntimeDecision(
      runtimeTerminated: false,
      sessionAuthorized: true,
      phoneUiActive: false,
      routeMatchesLogicalScreen: false,
      currentScreenAcceptsBarcode: true,
    );

    expect(decision.barcodeAdmissionEnabled, isTrue);
    expect(decision.hardwarePrepared, isTrue);
  });

  test('active route drift blocks barcode but keeps hardware prepared', () {
    final WearScannerRuntimeDecision decision =
        resolveWearScannerRuntimeDecision(
      runtimeTerminated: false,
      sessionAuthorized: true,
      phoneUiActive: true,
      routeMatchesLogicalScreen: false,
      currentScreenAcceptsBarcode: true,
    );

    expect(decision.barcodeAdmissionEnabled, isFalse);
    expect(decision.hardwarePrepared, isTrue);
  });

  test('authorized session keeps hardware prepared outside barcode screens', () {
    final WearScannerRuntimeDecision decision =
        resolveWearScannerRuntimeDecision(
      runtimeTerminated: false,
      sessionAuthorized: true,
      phoneUiActive: false,
      routeMatchesLogicalScreen: false,
      currentScreenAcceptsBarcode: false,
    );

    expect(decision.barcodeAdmissionEnabled, isFalse);
    expect(decision.hardwarePrepared, isTrue);
  });

  test('terminal lifecycle disables admission and hardware unconditionally', () {
    final WearScannerRuntimeDecision decision =
        resolveWearScannerRuntimeDecision(
      runtimeTerminated: true,
      sessionAuthorized: true,
      phoneUiActive: true,
      routeMatchesLogicalScreen: true,
      currentScreenAcceptsBarcode: true,
    );

    expect(decision.barcodeAdmissionEnabled, isFalse);
    expect(decision.hardwarePrepared, isFalse);
  });
}
