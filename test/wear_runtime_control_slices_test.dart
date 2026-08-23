import 'package:flutter_test/flutter_test.dart';
import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/domain/auth/model/authenticated_user.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_authority.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_store.dart';

void main() {
  AuthenticatedUser user() => AuthenticatedUser(
        idUser: 1,
        idEmployee: 2,
        name: 'Сотрудник',
      );

  test('voice observation stores only coarse control state', () async {
    final WearRuntimeAuthority authority = WearRuntimeAuthority();
    addTearDown(authority.dispose);

    final WearDispatchResult result = await authority.observeVoiceFromEpoch(
      sessionEpoch: authority.state.sessionEpoch,
      observationRevision: 1,
      phase: WearVoiceRuntimePhase.ready,
      commandsEnabled: true,
      captureEpoch: 3,
    );

    expect(result.accepted, isTrue);
    expect(authority.controls.voice.phase, WearVoiceRuntimePhase.ready);
    expect(authority.controls.voice.acceptsCommands, isTrue);
    expect(authority.controls.voice.captureEpoch, 3);
    expect(authority.controls.voice.toString(), isNot(contains('pcm')));
  });

  test('stale voice observation and capture epoch are rejected', () async {
    final WearRuntimeAuthority authority = WearRuntimeAuthority();
    addTearDown(authority.dispose);
    await authority.observeVoiceFromEpoch(
      sessionEpoch: authority.state.sessionEpoch,
      observationRevision: 2,
      phase: WearVoiceRuntimePhase.ready,
      commandsEnabled: true,
      captureEpoch: 5,
    );

    final WearDispatchResult oldRevision = await authority.store.dispatch(
      const WearVoiceControlObserved(
        sessionEpoch: 0,
        observationRevision: 1,
        phase: WearVoiceRuntimePhase.unavailable,
        commandsEnabled: false,
        captureEpoch: 5,
      ),
    );
    final WearDispatchResult oldCapture = await authority.store.dispatch(
      const WearVoiceControlObserved(
        sessionEpoch: 0,
        observationRevision: 3,
        phase: WearVoiceRuntimePhase.ready,
        commandsEnabled: true,
        captureEpoch: 4,
      ),
    );

    expect(oldRevision.rejectReason, WearDispatchRejectReason.staleOperation);
    expect(oldCapture.rejectReason, WearDispatchRejectReason.staleOperation);
    expect(authority.controls.voice.captureEpoch, 5);
  });

  test('scanner hardware and barcode admission are independent', () async {
    final WearRuntimeAuthority authority = WearRuntimeAuthority();
    addTearDown(authority.dispose);
    await authority.authorize(user());
    final int epoch = authority.state.sessionEpoch;
    await authority.setPhoneUiActive(false);
    await authority.requestNavigation(WearScreenId.scanIdle);

    await authority.observeScannerHardwareFromEpoch(
      sessionEpoch: epoch,
      observationRevision: 1,
      phase: WearScannerHardwarePhase.preparing,
    );
    await authority.evaluateScannerAdmissionFromEpoch(
      sessionEpoch: epoch,
      logicalScreen: WearScreenId.scanIdle,
      screenAcceptsBarcode: true,
    );
    expect(authority.controls.scanner.barcodeAdmissionEnabled, isFalse);

    await authority.observeScannerHardwareFromEpoch(
      sessionEpoch: epoch,
      observationRevision: 2,
      phase: WearScannerHardwarePhase.prepared,
    );
    await authority.evaluateScannerAdmissionFromEpoch(
      sessionEpoch: epoch,
      logicalScreen: WearScreenId.scanIdle,
      screenAcceptsBarcode: true,
    );

    expect(authority.controls.scanner.hardwarePrepared, isTrue);
    expect(authority.controls.scanner.barcodeAdmissionEnabled, isTrue);
  });

  test(
      'active route drift blocks barcode while background logical route admits',
      () async {
    final WearRuntimeAuthority authority = WearRuntimeAuthority();
    addTearDown(authority.dispose);
    await authority.authorize(user());
    final int epoch = authority.state.sessionEpoch;
    await authority.observeScannerHardwareFromEpoch(
      sessionEpoch: epoch,
      observationRevision: 1,
      phase: WearScannerHardwarePhase.prepared,
    );
    final WearRuntimeNavigationAdapter navigation =
        authority.navigationAdapter();
    await navigation.observePhoneRoute(WearScreenId.menu);
    await authority.requestNavigation(WearScreenId.scanIdle);
    await authority.setPhoneUiActive(true);

    await authority.evaluateScannerAdmissionFromEpoch(
      sessionEpoch: epoch,
      logicalScreen: WearScreenId.scanIdle,
      screenAcceptsBarcode: true,
    );
    expect(authority.controls.scanner.barcodeAdmissionEnabled, isFalse);

    await authority.setPhoneUiActive(false);
    await authority.evaluateScannerAdmissionFromEpoch(
      sessionEpoch: epoch,
      logicalScreen: WearScreenId.scanIdle,
      screenAcceptsBarcode: true,
    );
    expect(authority.controls.scanner.barcodeAdmissionEnabled, isTrue);
  });

  test('barcode delivery is accepted once for expected logical screen',
      () async {
    final WearRuntimeAuthority authority = WearRuntimeAuthority();
    addTearDown(authority.dispose);
    await authority.authorize(user());
    final int epoch = authority.state.sessionEpoch;
    await authority.requestNavigation(WearScreenId.scanIdle);
    await authority.observeScannerHardwareFromEpoch(
      sessionEpoch: epoch,
      observationRevision: 1,
      phase: WearScannerHardwarePhase.prepared,
    );
    await authority.evaluateScannerAdmissionFromEpoch(
      sessionEpoch: epoch,
      logicalScreen: WearScreenId.scanIdle,
      screenAcceptsBarcode: true,
    );

    final WearDispatchResult first =
        await authority.acceptBarcodeDeliveryFromEpoch(
      sessionEpoch: epoch,
      deliveryId: 7,
      logicalScreen: WearScreenId.scanIdle,
    );
    final WearDispatchResult duplicate =
        await authority.acceptBarcodeDeliveryFromEpoch(
      sessionEpoch: epoch,
      deliveryId: 7,
      logicalScreen: WearScreenId.scanIdle,
    );

    expect(first.accepted, isTrue);
    expect(duplicate.accepted, isFalse);
    expect(duplicate.rejectReason, WearDispatchRejectReason.duplicate);
  });

  test('connectivity observations are monotonic and versioned', () async {
    final WearRuntimeAuthority authority = WearRuntimeAuthority();
    addTearDown(authority.dispose);
    await authority.observeConnectivityFromEpoch(
      sessionEpoch: authority.state.sessionEpoch,
      observationRevision: 2,
      phase: WearConnectivityPhase.online,
    );

    final WearDispatchResult stale = await authority.store.dispatch(
      const WearConnectivityObserved(
        sessionEpoch: 0,
        observationRevision: 1,
        phase: WearConnectivityPhase.offline,
      ),
    );

    expect(stale.rejectReason, WearDispatchRejectReason.staleOperation);
    expect(authority.controls.connectivity.phase, WearConnectivityPhase.online);
  });

  test('session clear atomically closes previous-epoch control admission',
      () async {
    final WearRuntimeAuthority authority = WearRuntimeAuthority();
    addTearDown(authority.dispose);
    await authority.authorize(user());
    final int epoch = authority.state.sessionEpoch;
    await authority.requestNavigation(WearScreenId.scanIdle);
    await authority.observeScannerHardwareFromEpoch(
      sessionEpoch: epoch,
      observationRevision: 1,
      phase: WearScannerHardwarePhase.prepared,
    );
    await authority.evaluateScannerAdmissionFromEpoch(
      sessionEpoch: epoch,
      logicalScreen: WearScreenId.scanIdle,
      screenAcceptsBarcode: true,
    );
    await authority.observeVoiceFromEpoch(
      sessionEpoch: epoch,
      observationRevision: 1,
      phase: WearVoiceRuntimePhase.ready,
      commandsEnabled: true,
      captureEpoch: 1,
    );

    await authority.clearSession();

    expect(authority.state.sessionEpoch, epoch + 1);
    expect(authority.controls.voice.acceptsCommands, isFalse);
    expect(
      authority.controls.scanner.hardwarePhase,
      WearScannerHardwarePhase.released,
    );
    expect(authority.controls.scanner.barcodeAdmissionEnabled, isFalse);
  });
}
