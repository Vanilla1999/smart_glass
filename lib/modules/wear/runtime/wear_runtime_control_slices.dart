import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_core_slices.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_store.dart';

enum WearVoiceRuntimePhase {
  disabled,
  starting,
  ready,
  reconnecting,
  unavailable,
}

class WearVoiceControlSlice {
  const WearVoiceControlSlice({
    required this.phase,
    required this.commandsEnabled,
    required this.captureEpoch,
    required this.observationRevision,
    this.lastError,
  });

  const WearVoiceControlSlice.initial()
      : phase = WearVoiceRuntimePhase.disabled,
        commandsEnabled = false,
        captureEpoch = 0,
        observationRevision = 0,
        lastError = null;

  final WearVoiceRuntimePhase phase;
  final bool commandsEnabled;
  final int captureEpoch;
  final int observationRevision;
  final String? lastError;

  bool get acceptsCommands =>
      phase == WearVoiceRuntimePhase.ready && commandsEnabled;

  WearVoiceControlSlice copyWith({
    WearVoiceRuntimePhase? phase,
    bool? commandsEnabled,
    int? captureEpoch,
    int? observationRevision,
    String? lastError,
    bool clearError = false,
  }) {
    return WearVoiceControlSlice(
      phase: phase ?? this.phase,
      commandsEnabled: commandsEnabled ?? this.commandsEnabled,
      captureEpoch: captureEpoch ?? this.captureEpoch,
      observationRevision: observationRevision ?? this.observationRevision,
      lastError: clearError ? null : lastError ?? this.lastError,
    );
  }
}

enum WearScannerHardwarePhase {
  released,
  preparing,
  prepared,
  pausing,
  error,
}

class WearScannerControlSlice {
  const WearScannerControlSlice({
    required this.hardwarePhase,
    required this.barcodeAdmissionEnabled,
    required this.expectedLogicalScreen,
    required this.observationRevision,
    this.lastAcceptedDeliveryId,
    this.lastError,
  });

  const WearScannerControlSlice.initial()
      : hardwarePhase = WearScannerHardwarePhase.released,
        barcodeAdmissionEnabled = false,
        expectedLogicalScreen = null,
        observationRevision = 0,
        lastAcceptedDeliveryId = null,
        lastError = null;

  final WearScannerHardwarePhase hardwarePhase;
  final bool barcodeAdmissionEnabled;
  final WearScreenId? expectedLogicalScreen;
  final int observationRevision;
  final int? lastAcceptedDeliveryId;
  final String? lastError;

  bool get hardwarePrepared =>
      hardwarePhase == WearScannerHardwarePhase.prepared;

  WearScannerControlSlice copyWith({
    WearScannerHardwarePhase? hardwarePhase,
    bool? barcodeAdmissionEnabled,
    WearScreenId? expectedLogicalScreen,
    int? observationRevision,
    int? lastAcceptedDeliveryId,
    String? lastError,
    bool clearExpectedScreen = false,
    bool clearDelivery = false,
    bool clearError = false,
  }) {
    return WearScannerControlSlice(
      hardwarePhase: hardwarePhase ?? this.hardwarePhase,
      barcodeAdmissionEnabled:
          barcodeAdmissionEnabled ?? this.barcodeAdmissionEnabled,
      expectedLogicalScreen: clearExpectedScreen
          ? null
          : expectedLogicalScreen ?? this.expectedLogicalScreen,
      observationRevision: observationRevision ?? this.observationRevision,
      lastAcceptedDeliveryId: clearDelivery
          ? null
          : lastAcceptedDeliveryId ?? this.lastAcceptedDeliveryId,
      lastError: clearError ? null : lastError ?? this.lastError,
    );
  }
}

enum WearConnectivityPhase { unknown, offline, online, degraded }

class WearConnectivityControlSlice {
  const WearConnectivityControlSlice({
    required this.phase,
    required this.observationRevision,
    this.message,
  });

  const WearConnectivityControlSlice.initial()
      : phase = WearConnectivityPhase.unknown,
        observationRevision = 0,
        message = null;

  final WearConnectivityPhase phase;
  final int observationRevision;
  final String? message;

  WearConnectivityControlSlice copyWith({
    WearConnectivityPhase? phase,
    int? observationRevision,
    String? message,
    bool clearMessage = false,
  }) {
    return WearConnectivityControlSlice(
      phase: phase ?? this.phase,
      observationRevision: observationRevision ?? this.observationRevision,
      message: clearMessage ? null : message ?? this.message,
    );
  }
}

class WearRuntimeControlPayload implements WearControlPayload {
  const WearRuntimeControlPayload({
    required this.voice,
    required this.scanner,
    required this.connectivity,
  });

  const WearRuntimeControlPayload.initial()
      : voice = const WearVoiceControlSlice.initial(),
        scanner = const WearScannerControlSlice.initial(),
        connectivity = const WearConnectivityControlSlice.initial();

  final WearVoiceControlSlice voice;
  final WearScannerControlSlice scanner;
  final WearConnectivityControlSlice connectivity;

  WearRuntimeControlPayload copyWith({
    WearVoiceControlSlice? voice,
    WearScannerControlSlice? scanner,
    WearConnectivityControlSlice? connectivity,
  }) {
    return WearRuntimeControlPayload(
      voice: voice ?? this.voice,
      scanner: scanner ?? this.scanner,
      connectivity: connectivity ?? this.connectivity,
    );
  }

  @override
  WearControlPayload toTerminalControls() {
    return WearRuntimeControlPayload(
      voice: voice.copyWith(
        phase: WearVoiceRuntimePhase.disabled,
        commandsEnabled: false,
        clearError: true,
      ),
      scanner: scanner.copyWith(
        hardwarePhase: WearScannerHardwarePhase.released,
        barcodeAdmissionEnabled: false,
        clearExpectedScreen: true,
        clearDelivery: true,
        clearError: true,
      ),
      connectivity: connectivity,
    );
  }
}

class WearVoiceControlObserved extends WearIntent {
  const WearVoiceControlObserved({
    required this.sessionEpoch,
    required this.observationRevision,
    required this.phase,
    required this.commandsEnabled,
    required this.captureEpoch,
    this.error,
  });

  final int sessionEpoch;
  final int observationRevision;
  final WearVoiceRuntimePhase phase;
  final bool commandsEnabled;
  final int captureEpoch;
  final String? error;
}

class WearScannerHardwareObserved extends WearIntent {
  const WearScannerHardwareObserved({
    required this.sessionEpoch,
    required this.observationRevision,
    required this.phase,
    this.error,
  });

  final int sessionEpoch;
  final int observationRevision;
  final WearScannerHardwarePhase phase;
  final String? error;
}

class WearScannerAdmissionEvaluated extends WearIntent {
  const WearScannerAdmissionEvaluated({
    required this.sessionEpoch,
    required this.logicalScreen,
    required this.screenAcceptsBarcode,
  });

  final int sessionEpoch;
  final WearScreenId logicalScreen;
  final bool screenAcceptsBarcode;
}

class WearBarcodeDeliveryAccepted extends WearIntent {
  const WearBarcodeDeliveryAccepted({
    required this.sessionEpoch,
    required this.deliveryId,
    required this.logicalScreen,
  });

  final int sessionEpoch;
  final int deliveryId;
  final WearScreenId logicalScreen;
}

class WearConnectivityObserved extends WearIntent {
  const WearConnectivityObserved({
    required this.sessionEpoch,
    required this.observationRevision,
    required this.phase,
    this.message,
  });

  final int sessionEpoch;
  final int observationRevision;
  final WearConnectivityPhase phase;
  final String? message;
}

class WearControlSliceReducer implements WearSliceReducer {
  const WearControlSliceReducer();

  @override
  WearReduction? reduceSlice(WearRuntimeState state, WearIntent intent) {
    final WearAggregatePayload aggregate =
        state.payloadAs<WearAggregatePayload>();
    final WearControlPayload rawControls = aggregate.controls;
    if (rawControls is! WearRuntimeControlPayload) return null;
    final WearRuntimeControlPayload controls = rawControls;

    if (intent is WearVoiceControlObserved) {
      if (intent.sessionEpoch != state.sessionEpoch) {
        return WearReduction.reject(WearDispatchRejectReason.staleEpoch);
      }
      if (intent.observationRevision <= controls.voice.observationRevision ||
          intent.captureEpoch < controls.voice.captureEpoch) {
        return WearReduction.reject(WearDispatchRejectReason.staleOperation);
      }
      final bool commandsEnabled =
          intent.phase == WearVoiceRuntimePhase.ready && intent.commandsEnabled;
      final WearVoiceControlSlice nextVoice = controls.voice.copyWith(
        phase: intent.phase,
        commandsEnabled: commandsEnabled,
        captureEpoch: intent.captureEpoch,
        observationRevision: intent.observationRevision,
        lastError: intent.error,
        clearError: intent.error == null,
      );
      return _commitControls(
        state,
        aggregate,
        controls.copyWith(voice: nextVoice),
      );
    }

    if (intent is WearScannerHardwareObserved) {
      if (intent.sessionEpoch != state.sessionEpoch) {
        return WearReduction.reject(WearDispatchRejectReason.staleEpoch);
      }
      if (intent.observationRevision <= controls.scanner.observationRevision) {
        return WearReduction.reject(WearDispatchRejectReason.staleOperation);
      }
      final bool prepared = intent.phase == WearScannerHardwarePhase.prepared;
      final WearScannerControlSlice nextScanner = controls.scanner.copyWith(
        hardwarePhase: intent.phase,
        barcodeAdmissionEnabled:
            prepared && controls.scanner.barcodeAdmissionEnabled,
        observationRevision: intent.observationRevision,
        lastError: intent.error,
        clearError: intent.error == null,
      );
      return _commitControls(
        state,
        aggregate,
        controls.copyWith(scanner: nextScanner),
      );
    }

    if (intent is WearScannerAdmissionEvaluated) {
      if (intent.sessionEpoch != state.sessionEpoch) {
        return WearReduction.reject(WearDispatchRejectReason.staleEpoch);
      }
      if (intent.logicalScreen != aggregate.navigation.logicalScreen) {
        return WearReduction.reject(WearDispatchRejectReason.staleScreen);
      }
      final bool routeAllows = !aggregate.lifecycle.phoneUiActive ||
          aggregate.navigation.actualPhoneScreen == intent.logicalScreen;
      final bool enabled = aggregate.session.isAuthorized &&
          aggregate.lifecycle.runtimeActive &&
          controls.scanner.hardwarePrepared &&
          intent.screenAcceptsBarcode &&
          routeAllows;
      if (controls.scanner.barcodeAdmissionEnabled == enabled &&
          controls.scanner.expectedLogicalScreen == intent.logicalScreen) {
        return WearReduction.accept();
      }
      return _commitControls(
        state,
        aggregate,
        controls.copyWith(
          scanner: controls.scanner.copyWith(
            barcodeAdmissionEnabled: enabled,
            expectedLogicalScreen: intent.logicalScreen,
          ),
        ),
      );
    }

    if (intent is WearBarcodeDeliveryAccepted) {
      if (intent.sessionEpoch != state.sessionEpoch) {
        return WearReduction.reject(WearDispatchRejectReason.staleEpoch);
      }
      final WearScannerControlSlice scanner = controls.scanner;
      if (!scanner.barcodeAdmissionEnabled ||
          scanner.expectedLogicalScreen != intent.logicalScreen ||
          aggregate.navigation.logicalScreen != intent.logicalScreen) {
        return WearReduction.reject(WearDispatchRejectReason.staleScreen);
      }
      final int? lastDelivery = scanner.lastAcceptedDeliveryId;
      if (lastDelivery != null && intent.deliveryId <= lastDelivery) {
        return WearReduction.reject(WearDispatchRejectReason.duplicate);
      }
      return _commitControls(
        state,
        aggregate,
        controls.copyWith(
          scanner: scanner.copyWith(lastAcceptedDeliveryId: intent.deliveryId),
        ),
      );
    }

    if (intent is WearConnectivityObserved) {
      if (intent.sessionEpoch != state.sessionEpoch) {
        return WearReduction.reject(WearDispatchRejectReason.staleEpoch);
      }
      if (intent.observationRevision <=
          controls.connectivity.observationRevision) {
        return WearReduction.reject(WearDispatchRejectReason.staleOperation);
      }
      return _commitControls(
        state,
        aggregate,
        controls.copyWith(
          connectivity: controls.connectivity.copyWith(
            phase: intent.phase,
            observationRevision: intent.observationRevision,
            message: intent.message,
            clearMessage: intent.message == null,
          ),
        ),
      );
    }

    return null;
  }

  WearReduction _commitControls(
    WearRuntimeState state,
    WearAggregatePayload aggregate,
    WearRuntimeControlPayload controls,
  ) {
    return WearReduction.accept(
      nextState: state.withPayload(aggregate.copyWith(controls: controls)),
    );
  }
}

class WearScannerControlDecision {
  const WearScannerControlDecision({
    required this.hardwareShouldBePrepared,
    required this.barcodeAdmissionEnabled,
  });

  final bool hardwareShouldBePrepared;
  final bool barcodeAdmissionEnabled;
}

WearScannerControlDecision selectScannerControlDecision(
  WearRuntimeState state, {
  required bool screenAcceptsBarcode,
}) {
  final WearAggregatePayload aggregate =
      state.payloadAs<WearAggregatePayload>();
  final WearRuntimeControlPayload controls =
      aggregate.controls as WearRuntimeControlPayload;
  if (state.terminal || aggregate.lifecycle.terminal) {
    return const WearScannerControlDecision(
      hardwareShouldBePrepared: false,
      barcodeAdmissionEnabled: false,
    );
  }
  final bool routeAllows = !aggregate.lifecycle.phoneUiActive ||
      aggregate.navigation.actualPhoneScreen ==
          aggregate.navigation.logicalScreen;
  final bool hardwareShouldBePrepared = aggregate.session.isAuthorized &&
      aggregate.lifecycle.runtimeActive &&
      screenAcceptsBarcode &&
      routeAllows;
  return WearScannerControlDecision(
    hardwareShouldBePrepared: hardwareShouldBePrepared,
    barcodeAdmissionEnabled: hardwareShouldBePrepared &&
        controls.scanner.hardwarePrepared &&
        screenAcceptsBarcode &&
        routeAllows,
  );
}
