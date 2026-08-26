import 'package:flutter_test/flutter_test.dart';
import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_authority.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_control_adapter.dart';
import 'package:smart_glasses/modules/wear/services/wear_scanner_runtime_policy.dart';

import 'support/wear_runtime_test_helper.dart';

void main() {
  test('authorized barcode admission opens only after scanner preparation',
      () async {
    final WearRuntimeAuthority authority =
        await createActiveWearRuntimeAuthority(
      initialScreen: WearScreenId.scanIdle,
    );
    addTearDown(authority.dispose);
    await authority
        .navigationAdapter()
        .observePhoneRoute(WearScreenId.scanIdle);

    final WearScannerRuntimeDecision decision =
        resolveWearScannerDecisionFromState(
      authority.state,
      currentScreenAcceptsBarcode: true,
    );

    expect(decision.hardwarePrepared, isTrue);
    expect(decision.barcodeAdmissionEnabled, isFalse);

    final WearRuntimeControlAdapter controls =
        WearRuntimeControlAdapter(authority);
    await controls.observeScannerPreparing();
    await controls.observeScannerPrepared();
    await controls.evaluateScannerAdmission(
      logicalScreen: WearScreenId.scanIdle,
      screenAcceptsBarcode: true,
    );
    final WearScannerRuntimeDecision afterPreparation =
        resolveWearScannerDecisionFromState(
      authority.state,
      currentScreenAcceptsBarcode: true,
    );

    expect(afterPreparation.barcodeAdmissionEnabled, isTrue);
  });

  test('authorized route drift closes scanner preparation and admission',
      () async {
    final WearRuntimeAuthority authority =
        await createActiveWearRuntimeAuthority(
      initialScreen: WearScreenId.scanIdle,
    );
    addTearDown(authority.dispose);
    await authority.navigationAdapter().observePhoneRoute(WearScreenId.help);

    final WearScannerRuntimeDecision decision =
        resolveWearScannerDecisionFromState(
      authority.state,
      currentScreenAcceptsBarcode: true,
    );

    expect(decision.hardwarePrepared, isFalse);
    expect(decision.barcodeAdmissionEnabled, isFalse);
  });

  test('inactive phone UI ignores a stale actual route', () async {
    final WearRuntimeAuthority authority =
        await createActiveWearRuntimeAuthority(
      initialScreen: WearScreenId.scanIdle,
    );
    addTearDown(authority.dispose);
    await authority.navigationAdapter().observePhoneRoute(WearScreenId.help);
    await authority.setPhoneUiActive(false);

    final WearScannerRuntimeDecision decision =
        resolveWearScannerDecisionFromState(
      authority.state,
      currentScreenAcceptsBarcode: true,
    );

    expect(decision.hardwarePrepared, isTrue);
  });

  test('non-barcode screen keeps scanner paused', () async {
    final WearRuntimeAuthority authority =
        await createActiveWearRuntimeAuthority(
      initialScreen: WearScreenId.menu,
    );
    addTearDown(authority.dispose);

    final WearScannerRuntimeDecision decision =
        resolveWearScannerDecisionFromState(
      authority.state,
      currentScreenAcceptsBarcode: false,
    );

    expect(decision.hardwarePrepared, isFalse);
    expect(decision.barcodeAdmissionEnabled, isFalse);
  });

  test('terminal runtime disables scanner unconditionally', () async {
    final WearRuntimeAuthority authority =
        await createActiveWearRuntimeAuthority(
      initialScreen: WearScreenId.scanIdle,
    );
    addTearDown(authority.dispose);
    await authority.terminate();

    final WearScannerRuntimeDecision decision =
        resolveWearScannerDecisionFromState(
      authority.state,
      currentScreenAcceptsBarcode: true,
    );

    expect(decision.hardwarePrepared, isFalse);
    expect(decision.barcodeAdmissionEnabled, isFalse);
  });
}
