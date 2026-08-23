import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_authority.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_store.dart';
import 'package:smart_glasses/modules/wear/services/voice_state.dart';

/// One adapter instance belongs to exactly one session epoch.
///
/// After session clear, callbacks from this instance are stale by construction;
/// the next session must create a new adapter.
class WearRuntimeControlAdapter {
  WearRuntimeControlAdapter(this._authority)
      : _sessionEpoch = _authority.state.sessionEpoch,
        _voiceObservationRevision =
            _authority.controls.voice.observationRevision,
        _scannerObservationRevision =
            _authority.controls.scanner.observationRevision,
        _connectivityObservationRevision =
            _authority.controls.connectivity.observationRevision;

  final WearRuntimeAuthority _authority;
  final int _sessionEpoch;

  int _voiceObservationRevision;
  int _scannerObservationRevision;
  int _connectivityObservationRevision;

  int get sessionEpoch => _sessionEpoch;

  Future<WearDispatchResult> observeVoiceState(
    VoiceState state, {
    bool? commandsEnabled,
  }) {
    return _authority.observeVoiceFromEpoch(
      sessionEpoch: _sessionEpoch,
      observationRevision: ++_voiceObservationRevision,
      phase: _mapVoicePhase(state.phase),
      commandsEnabled: commandsEnabled ?? state.acceptsCommands,
      captureEpoch: state.captureEpoch,
      error: state.lastError,
    );
  }

  Future<WearDispatchResult> observeScannerPreparing() {
    return _observeScanner(WearScannerHardwarePhase.preparing);
  }

  Future<WearDispatchResult> observeScannerPrepared() {
    return _observeScanner(WearScannerHardwarePhase.prepared);
  }

  Future<WearDispatchResult> observeScannerPausing() {
    return _observeScanner(WearScannerHardwarePhase.pausing);
  }

  Future<WearDispatchResult> observeScannerReleased() {
    return _observeScanner(WearScannerHardwarePhase.released);
  }

  Future<WearDispatchResult> observeScannerError(Object error) {
    return _observeScanner(
      WearScannerHardwarePhase.error,
      error: error.toString(),
    );
  }

  Future<WearDispatchResult> _observeScanner(
    WearScannerHardwarePhase phase, {
    String? error,
  }) {
    return _authority.observeScannerHardwareFromEpoch(
      sessionEpoch: _sessionEpoch,
      observationRevision: ++_scannerObservationRevision,
      phase: phase,
      error: error,
    );
  }

  Future<WearDispatchResult> evaluateScannerAdmission({
    required WearScreenId logicalScreen,
    required bool screenAcceptsBarcode,
  }) {
    return _authority.evaluateScannerAdmissionFromEpoch(
      sessionEpoch: _sessionEpoch,
      logicalScreen: logicalScreen,
      screenAcceptsBarcode: screenAcceptsBarcode,
    );
  }

  Future<WearDispatchResult> acceptBarcodeDelivery({
    required int deliveryId,
    required WearScreenId logicalScreen,
  }) {
    return _authority.acceptBarcodeDeliveryFromEpoch(
      sessionEpoch: _sessionEpoch,
      deliveryId: deliveryId,
      logicalScreen: logicalScreen,
    );
  }

  Future<WearDispatchResult> observeConnectivity(
    WearConnectivityPhase phase, {
    String? message,
  }) {
    return _authority.observeConnectivityFromEpoch(
      sessionEpoch: _sessionEpoch,
      observationRevision: ++_connectivityObservationRevision,
      phase: phase,
      message: message,
    );
  }

  WearVoiceRuntimePhase _mapVoicePhase(VoicePhase phase) {
    return switch (phase) {
      VoicePhase.disabled => WearVoiceRuntimePhase.disabled,
      VoicePhase.loadingModel ||
      VoicePhase.startingRecorder ||
      VoicePhase.waitingForAudioRoute =>
        WearVoiceRuntimePhase.starting,
      VoicePhase.ready => WearVoiceRuntimePhase.ready,
      VoicePhase.suspendedBySystem || VoicePhase.reconnecting =>
        WearVoiceRuntimePhase.reconnecting,
      VoicePhase.unavailable || VoicePhase.microphoneReconnectRequired =>
        WearVoiceRuntimePhase.unavailable,
    };
  }
}
