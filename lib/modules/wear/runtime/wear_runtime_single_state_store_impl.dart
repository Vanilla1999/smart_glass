import 'dart:async';
import 'dart:collection';

import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';

abstract interface class WearRuntimePayload {
  WearRuntimePayload toTerminalPayload();
}

class WearEmptyRuntimePayload implements WearRuntimePayload {
  const WearEmptyRuntimePayload();

  @override
  WearRuntimePayload toTerminalPayload() => this;
}

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
    final int epoch = sessionEpoch.compareTo(other.sessionEpoch);
    return epoch == 0 ? revision.compareTo(other.revision) : epoch;
  }

  bool isNewerThan(WearRuntimeVersion other) => compareTo(other) > 0;

  @override
  bool operator ==(Object other) =>
      other is WearRuntimeVersion &&
      other.sessionEpoch == sessionEpoch &&
      other.revision == revision;

  @override
  int get hashCode => Object.hash(sessionEpoch, revision);
}

class WearOperationIdGenerator {
  WearOperationIdGenerator({int initialValue = 0}) : _value = initialValue {
    if (initialValue < 0) {
      throw ArgumentError.value(initialValue, 'initialValue');
    }
  }

  int _value;

  int next() => ++_value;
}

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

class WearRuntimeState {
  WearRuntimeState._({
    required this.sessionEpoch,
    required this.revision,
    required this.terminal,
    required this.legacy,
    required this.payload,
    required Map<String, int> expectedOperationIds,
  })  : assert(sessionEpoch >= 0),
        assert(revision >= 0),
        expectedOperationIds = UnmodifiableMapView<String, int>(
          Map<String, int>.of(expectedOperationIds),
        );

  factory WearRuntimeState.initial({
    required WearLegacyRuntimeSnapshot legacy,
    WearRuntimePayload payload = const WearEmptyRuntimePayload(),
    int sessionEpoch = 0,
  }) {
    return WearRuntimeState._(
      sessionEpoch: sessionEpoch,
      revision: 0,
      terminal: false,
      legacy: legacy,
      payload: payload,
      expectedOperationIds: const <String, int>{},
    );
  }

  final int sessionEpoch;
  final int revision;
  final bool terminal;
  final WearLegacyRuntimeSnapshot legacy;
  final WearRuntimePayload payload;
  final UnmodifiableMapView<String, int> expectedOperationIds;

  WearRuntimeVersion get version => WearRuntimeVersion(
        sessionEpoch: sessionEpoch,
        revision: revision,
      );

  T payloadAs<T extends WearRuntimePayload>() {
    final WearRuntimePayload current = payload;
    if (current is! T) {
      throw StateError(
        'Expected payload $T but current payload is ${current.runtimeType}',
      );
    }
    return current;
  }

  int? expectedOperationId(String kind) => expectedOperationIds[kind];

  WearRuntimeState withLegacy(WearLegacyRuntimeSnapshot value) {
    return _copy(legacy: value);
  }

  WearRuntimeState withPayload(WearRuntimePayload value) {
    return identical(value, payload) ? this : _copy(payload: value);
  }

  WearRuntimeState expectOperation({
    required String kind,
    required int operationId,
  }) {
    if (kind.trim().isEmpty || kind != kind.trim()) {
      throw ArgumentError.value(
          kind, 'kind', 'Operation kind is not normalized');
    }
    if (operationId <= 0) {
      throw ArgumentError.value(operationId, 'operationId');
    }
    return _copy(
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
    return _copy(expectedOperationIds: next);
  }

  WearRuntimeState beginNextEpoch({
    required WearLegacyRuntimeSnapshot legacy,
    WearRuntimePayload? payload,
    bool terminal = false,
  }) {
    return WearRuntimeState._(
      sessionEpoch: sessionEpoch + 1,
      revision: 0,
      terminal: terminal,
      legacy: legacy,
      payload: payload ?? this.payload,
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
      payload: payload.toTerminalPayload(),
      expectedOperationIds: const <String, int>{},
    );
  }

  WearRuntimeState _copy({
    WearLegacyRuntimeSnapshot? legacy,
    WearRuntimePayload? payload,
    Map<String, int>? expectedOperationIds,
  }) {
    return WearRuntimeState._(
      sessionEpoch: sessionEpoch,
      revision: revision,
      terminal: terminal,
      legacy: legacy ?? this.legacy,
      payload: payload ?? this.payload,
      expectedOperationIds: expectedOperationIds ?? this.expectedOperationIds,
    );
  }

  WearRuntimeState _committed({
    required int sessionEpoch,
    required int revision,
  }) {
    return WearRuntimeState._(
      sessionEpoch: sessionEpoch,
      revision: revision,
      terminal: terminal,
      legacy: legacy,
      payload: payload,
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
  const WearBeginOperation({required this.effect});
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
    this.payload,
    this.terminal = false,
  });

  final WearLegacyRuntimeSnapshot legacy;
  final WearRuntimePayload? payload;
  final bool terminal;
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

typedef WearEffectErrorIntentFactory = WearIntent? Function(
  WearEffect effect,
  Object error,
  StackTrace stackTrace,
);

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

class WearRuntimeShellReducer implements WearRuntimeReducer {
  const WearRuntimeShellReducer();

  @override
  WearReduction reduce(WearRuntimeState state, WearIntent intent) {
    if (state.terminal) {
      return WearReduction.reject(WearDispatchRejectReason.terminal);
    }
    if (intent is WearObserveLegacySnapshot) {
      if (intent.snapshot.sourceRevision < state.legacy.sourceRevision) {
        return WearReduction.reject(WearDispatchRejectReason.staleSnapshot);
      }
      return intent.snapshot.sameContentAs(state.legacy)
          ? WearReduction.accept()
          : WearReduction.accept(nextState: state.withLegacy(intent.snapshot));
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
        nextState: state.beginNextEpoch(
          legacy: intent.legacy,
          payload: intent.payload,
          terminal: intent.terminal,
        ),
      );
    }
    if (intent is WearNoopIntent) return WearReduction.accept();
    return WearReduction.reject(WearDispatchRejectReason.unsupported);
  }
}

class WearRuntimeStore {
  WearRuntimeStore({
    required WearRuntimeState initialState,
    required WearRuntimeReducer reducer,
    WearEffectHandler effectHandler = const WearNoopEffectHandler(),
    WearEffectErrorIntentFactory? effectErrorIntentFactory,
    void Function(Object error, StackTrace stackTrace)? onReducerError,
    void Function(WearEffect, Object, StackTrace)? onEffectError,
  })  : _state = initialState,
        _reducer = reducer,
        _effectHandler = effectHandler,
        _effectErrorIntentFactory = effectErrorIntentFactory,
        _onReducerError = onReducerError,
        _onEffectError = onEffectError;

  WearRuntimeState _state;
  final WearRuntimeReducer _reducer;
  final WearEffectHandler _effectHandler;
  final WearEffectErrorIntentFactory? _effectErrorIntentFactory;
  final void Function(Object, StackTrace)? _onReducerError;
  final void Function(WearEffect, Object, StackTrace)? _onEffectError;
  final Queue<_QueuedWearIntent> _queue = Queue<_QueuedWearIntent>();
  final StreamController<WearRuntimeState> _events =
      StreamController<WearRuntimeState>.broadcast(sync: true);

  bool _draining = false;
  bool _terminalBarrier = false;
  bool _disposed = false;
  Future<void>? _disposeFuture;

  WearRuntimeState get state => _state;

  Stream<WearRuntimeState> get states {
    return Stream<WearRuntimeState>.multi(
      (MultiStreamController<WearRuntimeState> controller) {
        controller.add(_state);
        if (_disposed) {
          controller.close();
          return;
        }
        final StreamSubscription<WearRuntimeState> subscription =
            _events.stream.listen(
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
      return Future<WearDispatchResult>.value(_rejected(
        WearDispatchRejectReason.terminal,
      ));
    }
    final Completer<WearDispatchResult> completer =
        Completer<WearDispatchResult>();
    _queue.add(_QueuedWearIntent(intent, completer));
    _drainIfNeeded();
    return completer.future;
  }

  void _drainIfNeeded() {
    if (_draining || _terminalBarrier) return;
    _draining = true;
    _drainQueue();
  }

  void _drainQueue() {
    try {
      while (_queue.isNotEmpty && !_terminalBarrier) {
        final _QueuedWearIntent queued = _queue.removeFirst();
        try {
          final WearReduction reduction =
              _reducer.reduce(_state, queued.intent);
          if (!reduction.accepted) {
            queued.complete(_rejected(
              reduction.rejectReason ?? WearDispatchRejectReason.internalError,
            ));
            continue;
          }

          final bool changed = reduction.nextState != null;
          final WearRuntimeState candidate =
              changed ? _prepareCommit(reduction.nextState!) : _state;
          _validateEffects(reduction.effects, candidate);
          if (changed) _publish(candidate);
          final WearRuntimeVersion receiptVersion = _state.version;
          _scheduleEffects(reduction.effects);
          queued.complete(WearDispatchResult(
            accepted: true,
            stateChanged: changed,
            sessionEpoch: receiptVersion.sessionEpoch,
            revision: receiptVersion.revision,
            scheduledEffectCount: reduction.effects.length,
          ));
        } catch (error, stackTrace) {
          _onReducerError?.call(error, stackTrace);
          queued.complete(_rejected(WearDispatchRejectReason.internalError));
        }
      }
    } finally {
      _draining = false;
      if (_queue.isNotEmpty && !_terminalBarrier) _drainIfNeeded();
    }
  }

  WearRuntimeState _prepareCommit(WearRuntimeState proposed) {
    if (proposed.sessionEpoch < _state.sessionEpoch ||
        proposed.sessionEpoch > _state.sessionEpoch + 1) {
      throw StateError('Invalid Wear session epoch transition');
    }
    return proposed.sessionEpoch == _state.sessionEpoch
        ? proposed._committed(
            sessionEpoch: _state.sessionEpoch,
            revision: _state.revision + 1,
          )
        : proposed._committed(
            sessionEpoch: proposed.sessionEpoch,
            revision: 0,
          );
  }

  void _validateEffects(
    List<WearEffect> effects,
    WearRuntimeState candidate,
  ) {
    for (final WearEffect effect in effects) {
      if (effect.kind.trim().isEmpty || effect.kind != effect.kind.trim()) {
        throw StateError('Effect kind is not normalized');
      }
      if (effect.sessionEpoch != candidate.sessionEpoch ||
          candidate.expectedOperationId(effect.kind) != effect.operationId) {
        throw StateError('Effect identity is not committed in candidate state');
      }
    }
  }

  void _publish(WearRuntimeState value) {
    _state = value;
    if (!_events.isClosed) _events.add(value);
  }

  void _scheduleEffects(List<WearEffect> effects) {
    for (final WearEffect effect in effects) {
      unawaited(
        Future<WearIntent?>.sync(() => _effectHandler.handle(effect)).then(
          (WearIntent? result) {
            if (result != null) unawaited(dispatch(result));
          },
          onError: (Object error, StackTrace stackTrace) {
            _onEffectError?.call(effect, error, stackTrace);
            final WearIntent? mapped =
                _effectErrorIntentFactory?.call(effect, error, stackTrace);
            if (mapped != null) unawaited(dispatch(mapped));
          },
        ),
      );
    }
  }

  WearDispatchResult _rejected(WearDispatchRejectReason reason) {
    return WearDispatchResult(
      accepted: false,
      stateChanged: false,
      sessionEpoch: _state.sessionEpoch,
      revision: _state.revision,
      scheduledEffectCount: 0,
      rejectReason: reason,
    );
  }

  Future<void> dispose() {
    final Future<void>? existing = _disposeFuture;
    if (existing != null) return existing;
    final Completer<void> completer = Completer<void>();
    _disposeFuture = completer.future;
    _terminalBarrier = true;
    if (!_state.terminal) _publish(_prepareCommit(_state.asTerminal()));
    while (_queue.isNotEmpty) {
      _queue.removeFirst().complete(_rejected(
            WearDispatchRejectReason.terminal,
          ));
    }
    unawaited(Future<void>.sync(() async {
      if (!_events.isClosed) await _events.close();
      _disposed = true;
      if (!completer.isCompleted) completer.complete();
    }).catchError((Object error, StackTrace stackTrace) {
      if (!completer.isCompleted) completer.completeError(error, stackTrace);
    }));
    return completer.future;
  }
}

class _QueuedWearIntent {
  _QueuedWearIntent(this.intent, this.completer);

  final WearIntent intent;
  final Completer<WearDispatchResult> completer;

  void complete(WearDispatchResult result) {
    if (!completer.isCompleted) completer.complete(result);
  }
}
