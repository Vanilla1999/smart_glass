import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_authority.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_store.dart';

extension WearRuntimeEpochBoundControls on WearRuntimeAuthority {
  Future<WearDispatchResult> observeVoiceFromEpoch({
    required int sessionEpoch,
    required int observationRevision,
    required WearVoiceRuntimePhase phase,
    required bool commandsEnabled,
    required int captureEpoch,
    String? error,
  }) {
    return store.dispatch(
      WearVoiceControlObserved(
        sessionEpoch: sessionEpoch,
        observationRevision: observationRevision,
        phase: phase,
        commandsEnabled: commandsEnabled,
        captureEpoch: captureEpoch,
        error: error,
      ),
    );
  }

  Future<WearDispatchResult> observeScannerHardwareFromEpoch({
    required int sessionEpoch,
    required int observationRevision,
    required WearScannerHardwarePhase phase,
    String? error,
  }) {
    return store.dispatch(
      WearScannerHardwareObserved(
        sessionEpoch: sessionEpoch,
        observationRevision: observationRevision,
        phase: phase,
        error: error,
      ),
    );
  }

  Future<WearDispatchResult> evaluateScannerAdmissionFromEpoch({
    required int sessionEpoch,
    required WearScreenId logicalScreen,
    required bool screenAcceptsBarcode,
  }) {
    return store.dispatch(
      WearScannerAdmissionEvaluated(
        sessionEpoch: sessionEpoch,
        logicalScreen: logicalScreen,
        screenAcceptsBarcode: screenAcceptsBarcode,
      ),
    );
  }

  Future<WearDispatchResult> acceptBarcodeDeliveryFromEpoch({
    required int sessionEpoch,
    required int deliveryId,
    required WearScreenId logicalScreen,
  }) {
    return store.dispatch(
      WearBarcodeDeliveryAccepted(
        sessionEpoch: sessionEpoch,
        deliveryId: deliveryId,
        logicalScreen: logicalScreen,
      ),
    );
  }

  Future<WearDispatchResult> observeConnectivityFromEpoch({
    required int sessionEpoch,
    required int observationRevision,
    required WearConnectivityPhase phase,
    String? message,
  }) {
    return store.dispatch(
      WearConnectivityObserved(
        sessionEpoch: sessionEpoch,
        observationRevision: observationRevision,
        phase: phase,
        message: message,
      ),
    );
  }
}
