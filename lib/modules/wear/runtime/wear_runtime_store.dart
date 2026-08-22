import 'dart:async';
import 'dart:collection';

import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';

/// Monotonic version of an aggregate Wear snapshot.
///
/// Revisions are compared only inside one session epoch. A newer epoch always
/// supersedes every revision of an older epoch.
class WearRuntimeVersion implements Comparable<WearRuntimeVersion> {
  const WearRuntimeVersion({
    required this.sessionEpoch,
    required this.revision,
  })  : assert(sessionEpoch >= 0),
        assert(revision >= 0);

  final int sessionEpoch;
  final int revision;

  @override
  int compareTo(WearRuntimeVersion other) {
    final int epochOrder = sessionEpoch.compareTo(other.sessionEpoch);
    if (epochOrder != 0) return epochOrder;
    return revision.compareTo(other.revision);
  }

  bool isNewerThan(WearRuntimeVersion other) => compareTo(other) > 0;

  @override
  bool operator ==(Object other) {
    return other is WearRuntimeVersion &&
        other.sessionEpoch == sessionEpoch &&
        other.revision == revision;
  }

  @override
  int get hashCode => Object.hash(sessionEpoch, revision);

  @override
  String toString() => 'WearRuntimeVersion($sessionEpoch, $revision)';
}

/// Read-only view of values still owned by the legacy runtime.
///
/// The shell may publish this snapshot, but it exposes no mutation path and is
/// not allowed to become a second writable owner of legacy business values.
class WearLegacyRuntimeSnapshot {
  WearLegacyRuntimeSnapshot({
    required this.logicalScreen,
    required this.sourceRevision,
    Map<String, String> diagnostics = const <String, String>{},
  })  : assert(sourceRevision >= 0),
        diagnostics = UnmodifiableMapView<String, String>(
          Map<String, String>.of(diagnostics),
        );

  final WearScreenId logicalScreen;
  final int sourceRevision;
  final UnmodifiableMapView<String, String> diagnostics;

  bool sameContentAs(WearLegacyRuntimeSnapshot other) {
    if (logicalScreen != other.logicalScreen ||
        sourceRevision != other.sourceRevision ||
        diagnostics.length != other.diagnostics.length) {
      return false;
    }
    for (final MapEntry<String, String> entry in diagnostics.entries) {
      if (other.diagnostics[entry.key] != entry.value) return false;
    }
    return true;
  }
}

/// Immutable aggregate root introduced by MR-S1.
///
/// Feature business state intentionally remains legacy-owned in this MR. The
/// root contains only version/terminal primitives, operation identities and a
/// read-only compatibility snapshot.
class WearRuntimeState {
  WearRuntimeState._({
    required this.sessionEpoch,
    required this.revision,
    required this.terminal,
    required this.legacy,
    required Map<String, int> expectedOperationIds,
  })  : assert(sessionEpoch >= 0),
        assert(revision >= 0),
        expectedOperationIds = UnmodifiableMapView<String, int>(
          Map<String, int>.of(expectedOperationIds),
        );

  factory WearRuntimeState.initial({
    required WearLegacyRuntimeSnapshot legacy,
    int sessionEpoch = 0,
  }) {
    return WearRuntimeState._(
      sessionEpoch: sessionEpoch,
      revision: 0,
      terminal: false,
      legacy: legacy,
      expectedOperationIds: const <String, int>{},
    );
  }

  final int sessionEpoch;
  final int revision;
  final bool terminal;
  final WearLegacyRuntimeSnapshot legacy;
  final UnmodifiableMapView<String, int> expectedOperationIds;

  WearRuntimeVersion get version => WearRuntimeVersion(
        sessionEpoch: sessionEpoch,
        revision: revision,
      );

  int? expectedOperationId(String kind) => expectedOperationIds[kind];

  WearRuntimeState withLegacy(WearLegacyRuntimeSnapshot snapshot) {
    return WearRuntimeState._(
      sessionEpoch: sessionEpoch,
      revision: revision,
      terminal: terminal,
      legacy: snapshot,
      expectedOperationIds: expectedOperationIds,
    );
  }

  WearRuntimeState expectOperation({
    required String kind,
    required int operationId,
  }) {
    if (operationId < 0) {
      throw ArgumentError.value(operationId, 'operationId');
    }
    return WearRuntimeState._(
      sessionEpoch: sessionEpoch,
      revision: revision,
      terminal: terminal,
      legacy: legacy,
      expectedOperationIds: <String, int>{
        ...expectedOperationIds,
        kind: operationId,
      },
    );
  }

  WearRuntimeState clearExpectedOperation(String kind) {
    if (!expectedOperationIds.containsKey(kind)) return this;
    final Map<String, int> next = Map<String, int>.of(expectedOperationIds)
      ..remove(kind);
    return WearRuntimeState._(
      sessionEpoch: sessionEpoch,
      revision: revision,
      terminal: terminal,
      legacy: legacy,
      expectedOperationIds: next,
    );
  }

  WearRuntimeState beginNextEpoch({
    required WearLegacyRuntimeSnapshot legacy,
    bool terminal = false,
  }) {
    return WearRuntimeState._(
      sessionEpoch: sessionEpoch + 1,
      revision: 0,
      terminal: terminal,
      legacy: legacy,
      expectedOperationIds: const <String, int>{},
    );
  }

  WearRuntimeState asTerminal() {
    if (terminal && expectedOperationIds.isEmpty) return this;
    return WearRuntimeState._(
      sessionEpoch: sessionEpoch + 1,
      revision: 0,
      terminal: true,
      legacy: legacy,
      expectedOperationIds: const <String, int>{},
    );
  }

  WearRuntimeState _withCommittedVersion({
    required int sessionEpoch,
    required int revision,
  }) {
    return WearRuntimeState._(
      sessionEpoch: sessionEpoch,
      revision: revision,
      terminal: terminal,
      legacy: legacy,
      expectedOperationIds: expectedOperationIds,
    );
  }
}

abstract class WearIntent {
  const WearIntent();
}

class WearObserveLegacySnapshot extends WearIntent {
  const WearObserveLegacySnapshot(this.snapshot);

  final WearLegacyRuntimeSnapshot snapshot;
}

class WearBeginOperation extends WearIntent {
  const WearBeginOperation({
    required this.effect,
  });

  final WearEffect effect;
}

class WearOperationResult extends WearIntent {
  const WearOperationResult({
    required this.sessionEpoch,
    required this.operationId,
    required this.kind,
  });

  final int sessionEpoch;
  final int operationId;
  final String kind;
}

class WearAdvanceSessionEpoch extends WearIntent {
  const WearAdvanceSessionEpoch({
    required this.legacy,
  });

  final WearLegacyRuntimeSnapshot legacy;
}

class WearNoopIntent extends WearIntent {
  const WearNoopIntent();
}

enum WearDispatchRejectReason {
  terminal,
  unsupported,
  busy,
  duplicate,
  staleEpoch,
  staleOperation,
  staleScreen,
  staleSnapshot,
  internalError,
}

class WearDispatchResult {
  const WearDispatchResult({
    required this.accepted,
    required this.stateChanged,
    required this.sessionEpoch,
    required this.revision,
    required this.scheduledEffectCount,
    this.rejectReason,
  });

  final bool accepted;
  final bool stateChanged;
  final int sessionEpoch;
  final int revision;
  final int scheduledEffectCount;
  final WearDispatchRejectReason? rejectReason;

  WearRuntimeVersion get version => WearRuntimeVersion(
        sessionEpoch: sessionEpoch,
        revision: revision,
      );
}

abstract class WearEffect {
  const WearEffect({
    required this.sessionEpoch,
    required this.operationId,
    required this.kind,
  });

  final int sessionEpoch;
  final int operationId;
  final String kind;
}

abstract interface class WearEffectHandler {
  Future<WearIntent?> handle(WearEffect effect);
}

class WearNoopEffectHandler implements WearEffectHandler {
  const WearNoopEffectHandler();

  @override
  Future<WearIntent?> handle(WearEffect effect) async => null;
}

class WearReduction {
  WearReduction._({
    required this.accepted,
    required this.nextState,
    required Iterable<WearEffect> effects,
    required this.rejectReason,
  }) : effects = List<WearEffect>.unmodifiable(effects);

  factory WearReduction.accept({
    WearRuntimeState? nextState,
    Iterable<WearEffect> effects = const <WearEffect>[],
  }) {
    return WearReduction._(
      accepted: true,
      nextState: nextState,
      effects: effects,
      rejectReason: null,
    );
  }

  factory WearReduction.reject(WearDispatchRejectReason reason) {
    return WearReduction._(
      accepted: false,
      nextState: null,
      effects: const <WearEffect>[],
      rejectReason: reason,
    );
  }

  final bool accepted;
  final WearRuntimeState? nextState;
  final List<WearEffect> effects;
  final WearDispatchRejectReason? rejectReason;
}

abstract interface class WearRuntimeReducer {
  WearReduction reduce(WearRuntimeState state, WearIntent intent);
}

/// Minimal reducer for the MR-S1 shell contract.
///
/// It mirrors legacy snapshots read-only, allocates expected operation
/// identities and validates generic effect results. Feature reducers replace
/// these generic intents slice by slice in later MRs.
class WearRuntimeShellReducer implements WearRuntimeReducer {
  const WearRuntimeShellReducer();

  @override
  WearReduction reduce(WearRuntimeState state, WearIntent intent) {
    if (state.terminal) {
      return WearReduction.reject(WearDispatchRejectReason.terminal);
    }
    if (intent is WearObserveLegacySnapshot) {
      final WearLegacyRuntimeSnapshot current = state.legacy;
      if (intent.snapshot.sourceRevision < current.sourceRevision) {
        return WearReduction.reject(WearDispatchRejectReason.staleSnapshot);
      }
      if (intent.snapshot.sameContentAs(current)) {
        return WearReduction.accept();
      }
      return WearReduction.accept(nextState: state.withLegacy(intent.snapshot));
    }
    if (intent is WearBeginOperation) {
      final WearEffect effect = intent.effect;
      if (effect.sessionEpoch != state.sessionEpoch) {
        return WearReduction.reject(WearDispatchRejectReason.staleEpoch);
      }
      final int? current = state.expectedOperationId(effect.kind);
      if (current != null && effect.operationId <= current) {
        return WearReduction.reject(WearDispatchRejectReason.duplicate);
      }
      return WearReduction.accept(
        nextState: state.expectOperation(
          kind: effect.kind,
          operationId: effect.operationId,
        ),
        effects: <WearEffect>[effect],
      );
    }
    if (intent is WearOperationResult) {
      if (intent.sessionEpoch != state.sessionEpoch) {
        return WearReduction.reject(WearDispatchRejectReason.staleEpoch);
      }
      if (state.expectedOperationId(intent.kind) != intent.operationId) {
        return WearReduction.reject(WearDispatchRejectReason.staleOperation);
      }
      return WearReduction.accept(
        nextState: state.clearExpectedOperation(intent.kind),
      );
    }
    if (intent is WearAdvanceSessionEpoch) {
      return WearReduction.accept(
        nextState: state.beginNextEpoch(legacy: intent.legacy),
      );
    }
    if (intent is WearNoopIntent) {
      return WearReduction.accept();
    }
    return WearReduction.reject(WearDispatchRejectReason.unsupported);
  }
}

/// Serialized reducer queue with independently running versioned effects.
class WearRuntimeStore {
  WearRuntimeStore({
    required WearRuntimeState initialState,
    required WearRuntimeReducer reducer,
    WearEffectHandler effectHandler = const WearNoopEffectHandler(),
    void Function(Object error, StackTrace stackTrace)? onReducerError,
    void Function(
      WearEffect effect,
      Object error,
      StackTrace stackTrace,
    )? onEffectError,
  })  : _state = initialState,
        _reducer = reducer,
        _effectHandler = effectHandler,
        _onReducerError = onReducerError,
        _onEffectError = onEffectError;

  WearRuntimeState _state;
  final WearRuntimeReducer _reducer;
  final WearEffectHandler _effectHandler;
  final void Function(Object error, StackTrace stackTrace)? _onReducerError;
  final void Function(
    WearEffect effect,
    Object error,
    StackTrace stackTrace,
  )? _onEffectError;

  final Queue<_QueuedWearIntent> _queue = Queue<_QueuedWearIntent>();
  final StreamController<WearRuntimeState> _stateEvents =
      StreamController<WearRuntimeState>.broadcast(sync: true);

  bool _draining = false;
  bool _terminalBarrier = false;
  bool _disposed = false;
  Future<void>? _disposeFuture;

  WearRuntimeState get state => _state;

  /// Replayable state stream: every subscriber receives current state first.
  Stream<WearRuntimeState> get states {
    return Stream<WearRuntimeState>.multi(
      (MultiStreamController<WearRuntimeState> controller) {
        controller.add(_state);
        if (_disposed) {
          controller.close();
          return;
        }
        final StreamSubscription<WearRuntimeState> subscription =
            _stateEvents.stream.listen(
          controller.add,
          onError: controller.addError,
          onDone: controller.close,
        );
        controller.onCancel = subscription.cancel;
      },
      isBroadcast: true,
    );
  }

  Future<WearDispatchResult> dispatch(WearIntent intent) {
    if (_terminalBarrier || _disposed || _state.terminal) {
      return Future<WearDispatchResult>.value(_terminalRejection());
    }
    final Completer<WearDispatchResult> completer =
        Completer<WearDispatchResult>();
    _queue.add(_QueuedWearIntent(intent: intent, completer: completer));
    _scheduleDrain();
    return completer.future;
  }

  void _scheduleDrain() {
    if (_draining || _terminalBarrier) return;
    _draining = true;
    scheduleMicrotask(_drainQueue);
  }

  void _drainQueue() {
    try {
      while (_queue.isNotEmpty && !_terminalBarrier) {
        final _QueuedWearIntent queued = _queue.removeFirst();
        try {
          final WearReduction reduction = _reducer.reduce(
            _state,
            queued.intent,
          );
          if (!reduction.accepted) {
            queued.completer.complete(
              WearDispatchResult(
                accepted: false,
                stateChanged: false,
                sessionEpoch: _state.sessionEpoch,
                revision: _state.revision,
                scheduledEffectCount: 0,
                rejectReason: reduction.rejectReason ??
                    WearDispatchRejectReason.internalError,
              ),
            );
            continue;
          }

          final bool changed = reduction.nextState != null;
          if (changed) _commit(reduction.nextState!);
          _validateAndScheduleEffects(reduction.effects);
          queued.completer.complete(
            WearDispatchResult(
              accepted: true,
              stateChanged: changed,
              sessionEpoch: _state.sessionEpoch,
              revision: _state.revision,
              scheduledEffectCount: reduction.effects.length,
            ),
          );
        } catch (error, stackTrace) {
          _onReducerError?.call(error, stackTrace);
          if (!queued.completer.isCompleted) {
            queued.completer.complete(
              WearDispatchResult(
                accepted: false,
                stateChanged: false,
                sessionEpoch: _state.sessionEpoch,
                revision: _state.revision,
                scheduledEffectCount: 0,
                rejectReason: WearDispatchRejectReason.internalError,
              ),
            );
          }
        }
      }
    } finally {
      _draining = false;
      if (_queue.isNotEmpty && !_terminalBarrier) _scheduleDrain();
    }
  }

  void _commit(WearRuntimeState proposed) {
    if (proposed.sessionEpoch < _state.sessionEpoch) {
      throw StateError('Runtime epoch cannot move backwards');
    }
    final WearRuntimeState committed;
    if (proposed.sessionEpoch == _state.sessionEpoch) {
      committed = proposed._withCommittedVersion(
        sessionEpoch: _state.sessionEpoch,
        revision: _state.revision + 1,
      );
    } else {
      committed = proposed._withCommittedVersion(
        sessionEpoch: proposed.sessionEpoch,
        revision: 0,
      );
    }
    _state = committed;
    if (!_stateEvents.isClosed) _stateEvents.add(committed);
  }

  void _validateAndScheduleEffects(List<WearEffect> effects) {
    for (final WearEffect effect in effects) {
      if (effect.sessionEpoch != _state.sessionEpoch ||
          _state.expectedOperationId(effect.kind) != effect.operationId) {
        throw StateError(
          'Effect must be represented by committed expected operation state',
        );
      }
      _scheduleEffect(effect);
    }
  }

  void _scheduleEffect(WearEffect effect) {
    unawaited(
      Future<WearIntent?>.sync(() => _effectHandler.handle(effect)).then(
        (WearIntent? resultIntent) {
          if (resultIntent == null) return;
          unawaited(dispatch(resultIntent));
        },
        onError: (Object error, StackTrace stackTrace) {
          _onEffectError?.call(effect, error, stackTrace);
        },
      ),
    );
  }

  WearDispatchResult _terminalRejection() {
    return WearDispatchResult(
      accepted: false,
      stateChanged: false,
      sessionEpoch: _state.sessionEpoch,
      revision: _state.revision,
      scheduledEffectCount: 0,
      rejectReason: WearDispatchRejectReason.terminal,
    );
  }

  Future<void> dispose() {
    final Future<void>? existing = _disposeFuture;
    if (existing != null) return existing;

    final Completer<void> completer = Completer<void>();
    _disposeFuture = completer.future;
    _terminalBarrier = true;

    while (_queue.isNotEmpty) {
      final _QueuedWearIntent queued = _queue.removeFirst();
      if (!queued.completer.isCompleted) {
        queued.completer.complete(_terminalRejection());
      }
    }

    if (!_state.terminal) {
      _commit(_state.asTerminal());
    }

    Future<void>.sync(() async {
      if (!_stateEvents.isClosed) await _stateEvents.close();
      _disposed = true;
      completer.complete();
    }).catchError((Object error, StackTrace stackTrace) {
      if (!completer.isCompleted) completer.completeError(error, stackTrace);
    });

    return completer.future;
  }
}

class _QueuedWearIntent {
  const _QueuedWearIntent({
    required this.intent,
    required this.completer,
  });

  final WearIntent intent;
  final Completer<WearDispatchResult> completer;
}
