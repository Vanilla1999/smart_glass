import 'package:flutter_test/flutter_test.dart';
import 'package:smart_glasses/modules/wear/services/wear_scanner_runtime_policy.dart';

void main() {
  test('pre-auth scanner requires the actual route to match logical state', () {
    final WearScannerRuntimeDecision decision =
        resolveWearScannerRuntimeDecision(
      sessionAuthorized: false,
      routeMatchesLogicalScreen: false,
      currentScreenAcceptsBarcode: true,
    );

    expect(decision.barcodeAdmissionEnabled, isFalse);
    expect(decision.hardwarePrepared, isFalse);
  });

  test('pre-auth matching route enables scanner admission', () {
    final WearScannerRuntimeDecision decision =
        resolveWearScannerRuntimeDecision(
      sessionAuthorized: false,
      routeMatchesLogicalScreen: true,
      currentScreenAcceptsBarcode: true,
    );

    expect(decision.barcodeAdmissionEnabled, isTrue);
    expect(decision.hardwarePrepared, isTrue);
  });

  test('authorized logical state admits barcode while phone route lags', () {
    final WearScannerRuntimeDecision decision =
        resolveWearScannerRuntimeDecision(
      sessionAuthorized: true,
      routeMatchesLogicalScreen: false,
      currentScreenAcceptsBarcode: true,
    );

    expect(decision.barcodeAdmissionEnabled, isTrue);
    expect(decision.hardwarePrepared, isTrue);
  });

  test('authorized session keeps hardware prepared outside barcode screens', () {
    final WearScannerRuntimeDecision decision =
        resolveWearScannerRuntimeDecision(
      sessionAuthorized: true,
      routeMatchesLogicalScreen: false,
      currentScreenAcceptsBarcode: false,
    );

    expect(decision.barcodeAdmissionEnabled, isFalse);
    expect(decision.hardwarePrepared, isTrue);
  });
}
