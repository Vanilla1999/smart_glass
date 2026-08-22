import 'package:smart_glasses/modules/wear/application/runtime/wear_runtime_contract.dart';
import 'package:smart_glasses/modules/wear/application/runtime/wear_runtime_state.dart';

class WearRuntimeReduction {
  WearRuntimeReduction._({
    required this.candidateState,
    required this.stateChanged,
    required this.status,
    required List<WearRuntimeEffect> effects,
    this.rejectReason,
    this.message,
  }) : effects = List<WearRuntimeEffect>.unmodifiable(effects);

  factory WearRuntimeReduction.accepted({
    required WearRuntimeState candidateState,
    List<WearRuntimeEffect> effects = const <WearRuntimeEffect>[],
  }) {
    return WearRuntimeReduction._(
      candidateState: candidateState,
      stateChanged: true,
      status: WearDispatchStatus.accepted,
      effects: effects,
    );
  }

  factory WearRuntimeReduction.noChange(WearRuntimeState state) {
    return WearRuntimeReduction._(
      candidateState: state,
      stateChanged: false,
      status: WearDispatchStatus.noChange,
      effects: const <WearRuntimeEffect>[],
    );
  }

  factory WearRuntimeReduction.rejected(
    WearRuntimeState state, {
    required WearDispatchRejectReason reason,
    String? message,
  }) {
    return WearRuntimeReduction._(
      candidateState: state,
      stateChanged: false,
      status: WearDispatchStatus.rejected,
      effects: const <WearRuntimeEffect>[],
      rejectReason: reason,
      message: message,
    );
  }

  final WearRuntimeState candidateState;
  final bool stateChanged;
  final WearDispatchStatus status;
  final List<WearRuntimeEffect> effects;
  final WearDispatchRejectReason? rejectReason;
  final String? message;
}

abstract interface class WearRuntimeReducer {
  WearRuntimeReduction reduce(
    WearRuntimeState state,
    WearIntent intent,
  );
}

final class WearRuntimeShellReducer implements WearRuntimeReducer {
  const WearRuntimeShellReducer();

  @override
  WearRuntimeReduction reduce(
    WearRuntimeState state,
    WearIntent intent,
  ) {
    if (state.terminal) {
      return WearRuntimeReduction.rejected(
        state,
        reason: WearDispatchRejectReason.terminal,
      );
    }

    if (intent is WearRuntimeNoOpIntent) {
      return WearRuntimeReduction.noChange(state);
    }

    if (intent is WearLegacySnapshotObserved) {
      if (state.legacy.representsSameSourceSnapshot(intent.snapshot)) {
        return WearRuntimeReduction.noChange(state);
      }
      return WearRuntimeReduction.accepted(
        candidateState: state.copyWith(legacy: intent.snapshot),
      );
    }

    return WearRuntimeReduction.rejected(
      state,
      reason: WearDispatchRejectReason.unsupported,
      message: 'Unsupported intent: ${intent.debugLabel}',
    );
  }
}
