import 'dart:async';

import 'package:smart_glasses/modules/wear/application/voice_clarification_args.dart';
import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/application/wear_status_state.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/status/wear_status_args.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_core_slices.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_store.dart';

const String wearGenericStatusOperationKind = 'presentation.genericStatus';

/// Aggregate-owned presentation state which preserves the original focus API.
///
/// Older snapshots containing only [WearPresentationFocusSlice] are upgraded
/// lazily on the first presentation intent; no parallel writable root is
/// introduced.
class WearRuntimePresentationSlice extends WearPresentationFocusSlice {
  WearRuntimePresentationSlice({
    super.focusedIndices,
    this.clarificationArgs,
    this.clarificationFocusedIndex = 0,
    this.clarificationNotice,
    this.statusArgs,
    this.statusCompletion,
    this.statusOperationId,
    this.statusDeadline,
  });

  factory WearRuntimePresentationSlice.from(
    WearPresentationPayload payload,
  ) {
    if (payload is WearRuntimePresentationSlice) return payload;
    if (payload is WearPresentationFocusSlice) {
      return WearRuntimePresentationSlice(
        focusedIndices: payload.focusedIndices,
      );
    }
    return WearRuntimePresentationSlice();
  }

  final VoiceClarificationArgs? clarificationArgs;
  final int clarificationFocusedIndex;
  final String? clarificationNotice;
  final WearStatusScreenArgs? statusArgs;
  final WearStatusCompletion? statusCompletion;
  final int? statusOperationId;
  final DateTime? statusDeadline;

  bool get hasClarification => clarificationArgs != null;
  bool get hasGenericStatus => statusArgs != null;

  @override
  WearRuntimePresentationSlice withFocus(WearScreenId screen, int index) {
    return copyWith(
      focusedIndices: <WearScreenId, int>{
        ...focusedIndices,
        screen: index,
      },
    );
  }

  WearRuntimePresentationSlice copyWith({
    Map<WearScreenId, int>? focusedIndices,
    VoiceClarificationArgs? clarificationArgs,
    bool clearClarification = false,
    int? clarificationFocusedIndex,
    String? clarificationNotice,
    bool clearClarificationNotice = false,
    WearStatusScreenArgs? statusArgs,
    WearStatusCompletion? statusCompletion,
    int? statusOperationId,
    DateTime? statusDeadline,
    bool clearStatus = false,
  }) {
    return WearRuntimePresentationSlice(
      focusedIndices: focusedIndices ?? this.focusedIndices,
      clarificationArgs: clearClarification
          ? null
          : clarificationArgs ?? this.clarificationArgs,
      clarificationFocusedIndex: clearClarification
          ? 0
          : clarificationFocusedIndex ?? this.clarificationFocusedIndex,
      clarificationNotice: clearClarification || clearClarificationNotice
          ? null
          : clarificationNotice ?? this.clarificationNotice,
      statusArgs: clearStatus ? null : statusArgs ?? this.statusArgs,
      statusCompletion:
          clearStatus ? null : statusCompletion ?? this.statusCompletion,
      statusOperationId:
          clearStatus ? null : statusOperationId ?? this.statusOperationId,
      statusDeadline:
          clearStatus ? null : statusDeadline ?? this.statusDeadline,
    );
  }

  WearRuntimePresentationSlice reset() {
    return WearRuntimePresentationSlice(
      focusedIndices: focusedIndices,
    );
  }
}

class WearVoiceClarificationContextChanged extends WearIntent {
  const WearVoiceClarificationContextChanged({
    required this.sessionEpoch,
    required this.expectedScreen,
    required this.args,
  });

  final int sessionEpoch;
  final WearScreenId expectedScreen;
  final VoiceClarificationArgs args;
}

class WearVoiceClarificationFocusChanged extends WearIntent {
  const WearVoiceClarificationFocusChanged({
    required this.sessionEpoch,
    required this.index,
  });

  final int sessionEpoch;
  final int index;
}

class WearVoiceClarificationNoticeChanged extends WearIntent {
  const WearVoiceClarificationNoticeChanged({
    required this.sessionEpoch,
    this.notice,
  });

  final int sessionEpoch;
  final String? notice;
}

class WearVoiceClarificationCleared extends WearIntent {
  const WearVoiceClarificationCleared({required this.sessionEpoch});

  final int sessionEpoch;
}

class WearGenericStatusShown extends WearIntent {
  const WearGenericStatusShown({
    required this.sessionEpoch,
    required this.operationId,
    required this.expectedScreen,
    required this.args,
    required this.completion,
    required this.deadline,
  });

  final int sessionEpoch;
  final int operationId;
  final WearScreenId expectedScreen;
  final WearStatusScreenArgs args;
  final WearStatusCompletion completion;
  final DateTime? deadline;
}

class WearGenericStatusElapsed extends WearIntent {
  const WearGenericStatusElapsed({
    required this.sessionEpoch,
    required this.operationId,
  });

  final int sessionEpoch;
  final int operationId;
}

class WearGenericStatusCleared extends WearIntent {
  const WearGenericStatusCleared({required this.sessionEpoch});

  final int sessionEpoch;
}

class WearRuntimePresentationReducer implements WearSliceReducer {
  const WearRuntimePresentationReducer();

  @override
  WearReduction? reduceSlice(WearRuntimeState state, WearIntent intent) {
    final WearAggregatePayload aggregate =
        state.payloadAs<WearAggregatePayload>();
    final WearRuntimePresentationSlice presentation =
        WearRuntimePresentationSlice.from(aggregate.presentation);

    if (intent is WearVoiceClarificationContextChanged) {
      final WearReduction? rejection = _validate(
        state,
        aggregate,
        sessionEpoch: intent.sessionEpoch,
        expectedScreen: intent.expectedScreen,
      );
      if (rejection != null) return rejection;
      if (intent.args.matches.isEmpty) {
        return WearReduction.reject(WearDispatchRejectReason.unsupported);
      }
      return WearReduction.accept(
        nextState: state.withPayload(aggregate.copyWith(
          presentation: presentation.copyWith(
            clarificationArgs: intent.args,
            clarificationFocusedIndex: 0,
            clearClarificationNotice: true,
          ),
        )),
      );
    }

    if (intent is WearVoiceClarificationFocusChanged) {
      if (intent.sessionEpoch != state.sessionEpoch) {
        return WearReduction.reject(WearDispatchRejectReason.staleEpoch);
      }
      if (aggregate.navigation.logicalScreen !=
          WearScreenId.voiceClarification) {
        return WearReduction.reject(WearDispatchRejectReason.staleScreen);
      }
      final VoiceClarificationArgs? args = presentation.clarificationArgs;
      if (args == null || args.matches.isEmpty || intent.index < 0) {
        return WearReduction.reject(WearDispatchRejectReason.unsupported);
      }
      final int next = intent.index.clamp(0, args.matches.length - 1);
      if (presentation.clarificationFocusedIndex == next) {
        return WearReduction.accept();
      }
      return WearReduction.accept(
        nextState: state.withPayload(aggregate.copyWith(
          presentation: presentation.copyWith(
            clarificationFocusedIndex: next,
            clearClarificationNotice: true,
          ),
        )),
      );
    }

    if (intent is WearVoiceClarificationNoticeChanged) {
      if (intent.sessionEpoch != state.sessionEpoch) {
        return WearReduction.reject(WearDispatchRejectReason.staleEpoch);
      }
      if (aggregate.navigation.logicalScreen !=
              WearScreenId.voiceClarification ||
          presentation.clarificationArgs == null) {
        return WearReduction.reject(WearDispatchRejectReason.staleScreen);
      }
      final String? notice = intent.notice?.trim();
      final String? normalized = notice == null || notice.isEmpty ? null : notice;
      if (presentation.clarificationNotice == normalized) {
        return WearReduction.accept();
      }
      return WearReduction.accept(
        nextState: state.withPayload(aggregate.copyWith(
          presentation: presentation.copyWith(
            clarificationNotice: normalized,
            clearClarificationNotice: normalized == null,
          ),
        )),
      );
    }

    if (intent is WearVoiceClarificationCleared) {
      if (intent.sessionEpoch != state.sessionEpoch) {
        return WearReduction.reject(WearDispatchRejectReason.staleEpoch);
      }
      if (!presentation.hasClarification) return WearReduction.accept();
      return WearReduction.accept(
        nextState: state.withPayload(aggregate.copyWith(
          presentation: presentation.copyWith(clearClarification: true),
        )),
      );
    }

    if (intent is WearGenericStatusShown) {
      final WearReduction? rejection = _validate(
        state,
        aggregate,
        sessionEpoch: intent.sessionEpoch,
        expectedScreen: intent.expectedScreen,
      );
      if (rejection != null) return rejection;
      if (intent.operationId <= 0) {
        return WearReduction.reject(WearDispatchRejectReason.unsupported);
      }
      final WearNavigationSlice navigation = aggregate.navigation.request(
        WearScreenId.status,
        kind: WearPendingNavigationKind.push,
      );
      return WearReduction.accept(
        nextState: state
            .expectOperation(
              kind: wearGenericStatusOperationKind,
              operationId: intent.operationId,
            )
            .withPayload(aggregate.copyWith(
              navigation: navigation,
              presentation: presentation.copyWith(
                statusArgs: intent.args,
                statusCompletion: intent.completion,
                statusOperationId: intent.operationId,
                statusDeadline: intent.deadline,
              ),
            )),
      );
    }

    if (intent is WearGenericStatusElapsed) {
      if (intent.sessionEpoch != state.sessionEpoch) {
        return WearReduction.reject(WearDispatchRejectReason.staleEpoch);
      }
      if (aggregate.navigation.logicalScreen != WearScreenId.status) {
        return WearReduction.reject(WearDispatchRejectReason.staleScreen);
      }
      if (state.expectedOperationId(wearGenericStatusOperationKind) !=
              intent.operationId ||
          presentation.statusOperationId != intent.operationId) {
        return WearReduction.reject(WearDispatchRejectReason.staleOperation);
      }
      final WearStatusCompletion? completion = presentation.statusCompletion;
      final WearScreenId? target = completion?.target;
      WearNavigationSlice navigation = aggregate.navigation;
      if (completion != null &&
          completion.kind != WearStatusCompletionKind.stay &&
          target != null) {
        navigation = navigation.request(
          target,
          kind: completion.kind == WearStatusCompletionKind.returnTo
              ? WearPendingNavigationKind.pop
              : WearPendingNavigationKind.replace,
        );
      }
      return WearReduction.accept(
        nextState: state
            .clearExpectedOperation(wearGenericStatusOperationKind)
            .withPayload(aggregate.copyWith(
              navigation: navigation,
              presentation: presentation.copyWith(clearStatus: true),
            )),
      );
    }

    if (intent is WearGenericStatusCleared) {
      if (intent.sessionEpoch != state.sessionEpoch) {
        return WearReduction.reject(WearDispatchRejectReason.staleEpoch);
      }
      if (!presentation.hasGenericStatus) return WearReduction.accept();
      return WearReduction.accept(
        nextState: state
            .clearExpectedOperation(wearGenericStatusOperationKind)
            .withPayload(aggregate.copyWith(
              presentation: presentation.copyWith(clearStatus: true),
            )),
      );
    }

    if (intent is WearLogicalNavigationRequested) {
      final WearReduction? navigationReduction =
          const WearCoreSliceReducer().reduceSlice(state, intent);
      if (navigationReduction == null || !navigationReduction.accepted) {
        return navigationReduction;
      }
      final WearRuntimeState? navigated = navigationReduction.nextState;
      if (navigated == null) return navigationReduction;
      final WearAggregatePayload nextAggregate =
          navigated.payloadAs<WearAggregatePayload>();
      WearRuntimePresentationSlice nextPresentation =
          WearRuntimePresentationSlice.from(nextAggregate.presentation);
      WearRuntimeState nextState = navigated;
      if (intent.screen != WearScreenId.voiceClarification &&
          nextPresentation.hasClarification) {
        nextPresentation =
            nextPresentation.copyWith(clearClarification: true);
      }
      if (intent.screen != WearScreenId.status &&
          nextPresentation.hasGenericStatus) {
        nextPresentation = nextPresentation.copyWith(clearStatus: true);
        nextState =
            nextState.clearExpectedOperation(wearGenericStatusOperationKind);
      }
      return WearReduction.accept(
        nextState: nextState.withPayload(nextAggregate.copyWith(
          presentation: nextPresentation,
        )),
        effects: navigationReduction.effects,
      );
    }

    return null;
  }

  WearReduction? _validate(
    WearRuntimeState state,
    WearAggregatePayload aggregate, {
    required int sessionEpoch,
    required WearScreenId expectedScreen,
  }) {
    if (sessionEpoch != state.sessionEpoch) {
      return WearReduction.reject(WearDispatchRejectReason.staleEpoch);
    }
    if (aggregate.navigation.logicalScreen != expectedScreen) {
      return WearReduction.reject(WearDispatchRejectReason.staleScreen);
    }
    return null;
  }
}

/// Timer adapter for aggregate generic status operations.
///
/// The deadline and operation identity remain in [WearRuntimeState]. This class
/// owns only the cancellable host timer and can never navigate or mutate a slice
/// directly.
class WearRuntimePresentationScheduler {
  WearRuntimePresentationScheduler(this._authority) {
    _subscription = _authority.states.listen(_onState);
  }

  final dynamic _authority;
  late final StreamSubscription<WearRuntimeState> _subscription;
  Timer? _timer;
  ({int epoch, int operationId})? _scheduled;

  void _onState(WearRuntimeState state) {
    if (state.terminal) {
      _cancel();
      return;
    }
    final WearAggregatePayload aggregate =
        state.payloadAs<WearAggregatePayload>();
    final WearRuntimePresentationSlice presentation =
        WearRuntimePresentationSlice.from(aggregate.presentation);
    final int? operationId = presentation.statusOperationId;
    final DateTime? deadline = presentation.statusDeadline;
    if (aggregate.navigation.logicalScreen != WearScreenId.status ||
        operationId == null ||
        deadline == null) {
      _cancel();
      return;
    }
    final ({int epoch, int operationId}) key = (
      epoch: state.sessionEpoch,
      operationId: operationId,
    );
    if (_scheduled == key) return;
    _cancel();
    _scheduled = key;
    final Duration delay = deadline.difference(DateTime.now());
    _timer = Timer(delay.isNegative ? Duration.zero : delay, () {
      if (_scheduled != key) return;
      _timer = null;
      _scheduled = null;
      unawaited(_authority.store.dispatch(WearGenericStatusElapsed(
        sessionEpoch: key.epoch,
        operationId: key.operationId,
      )));
    });
  }

  void _cancel() {
    _timer?.cancel();
    _timer = null;
    _scheduled = null;
  }

  Future<void> dispose() async {
    _cancel();
    await _subscription.cancel();
  }
}
