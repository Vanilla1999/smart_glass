import 'package:smart_glasses/modules/wear/runtime/wear_runtime_authority.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_store.dart';
import 'package:smart_glasses/modules/wear/services/voice_state.dart';

class WearRuntimeControlAdapter {
  WearRuntimeControlAdapter(this._authority);

  final WearRuntimeAuthority _authority;

  int _voiceObservationRevision = 0;
  int _scannerObservationRevision = 0;
  int _connectivityObservationRevision = 0;

  Future<WearDispatchResult> observeVoiceState(VoiceState state) {
    return _authority.observeVoice(
      observationRevision: ++_voiceObservationRevision,
      phase: _mapVoicePhase(state.phase),
      commandsEnabled: state.acceptsCommands,
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
    return _authority.observeScannerHardware(
      observationRevision: ++_scannerObservationRevision,
      phase: phase,
      error: error,
    );
  }

  Future<WearDispatchResult> observeConnectivity(
    WearConnectivityPhase phase, {
    String? message,
  }) {
    return _authority.observeConnectivity(
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
