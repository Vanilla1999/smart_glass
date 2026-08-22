import 'dart:async';
import 'dart:collection';

import 'package:smart_glasses/modules/wear/application/runtime/wear_runtime_contract.dart';
import 'package:smart_glasses/modules/wear/application/runtime/wear_runtime_reducer.dart';
import 'package:smart_glasses/modules/wear/application/runtime/wear_runtime_state.dart';

abstract interface class WearRuntimeStore {
  WearRuntimeState get state;

  Stream<WearRuntimeState> get states;

  Future<WearDispatchResult> dispatch(WearIntent intent);

  Future<void> dispose();
}

final class SerializedWearRuntimeStore implements WearRuntimeStore {
  SerializedWearRuntimeStore({
    required WearRuntimeState initialState,
    required WearRuntimeReducer reducer,
    required WearRuntimeEffectRunner effectRunner,
    void Function(Object error, StackTrace stackTrace)? onInfrastructureError,
  })  : _state = initialState,
        _reducer = reducer,
        _effectRunner = effectRunner,
        _onInfrastructureError = onInfrastructureError;

  final WearRuntimeReducer _reducer;
  final WearRuntimeEffectRunner _effectRunner;
  final void Function(Object error, StackTrace stackTrace)?
      _onInfrastructureError;
  final StreamController<WearRuntimeState> _stateEvents =
      StreamController<WearRuntimeState>.broadcast();
  final Queue<_QueuedDispatch> _queue = Queue<_QueuedDispatch>();

  WearRuntimeState _state;
  bool _accepting = true;
  bool _draining = false;
  Completer<void>? _disposeCompleter;

  @override
  WearRuntimeState get state => _state;

  @override
  Stream<WearRuntimeState> get states {
    if (_stateEvents.isClosed) {
      return Stream<WearRuntimeState>.value(_state);
    }
    return Stream<WearRuntimeState>.multi(
      (MultiStreamController<WearRuntimeState> controller) {
        final WearRuntimeState initial = _state;
        controller.add(initial);
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

  @override
  Future<WearDispatchResult> dispatch(WearIntent intent) {
    if (!_accepting || _state.terminal) {
      return Future<WearDispatchResult>.value(
        WearDispatchResult.rejected(
          version: _state.version,
          reason: WearDispatchRejectReason.terminal,
        ),
      );
    }

    final Completer<WearDispatchResult> completer =
        Completer<WearDispatchResult>();
    _queue.add(_QueuedDispatch(intent: intent, completer: completer));
    _scheduleDrain();
    return completer.future;
  }

  void _scheduleDrain() {
    if (_draining) return;
    _draining = true;
    scheduleMicrotask(_drain);
  }

  void _drain() {
    try {
      while (_queue.isNotEmpty) {
        final _QueuedDispatch queued = _queue.removeFirst();
        if (!_accepting || _state.terminal) {
          queued.complete(
            WearDispatchResult.rejected(
              version: _state.version,
              reason: WearDispatchRejectReason.terminal,
            ),
          );
          continue;
        }

        try {
          final WearRuntimeReduction reduction =
              _reducer.reduce(_state, queued.intent);
          if (reduction.status == WearDispatchStatus.rejected) {
            queued.complete(
              WearDispatchResult.rejected(
                version: _state.version,
                reason: reduction.rejectReason ??
                    WearDispatchRejectReason.invalidState,
                message: reduction.message,
              ),
            );
            continue;
          }

          if (!reduction.stateChanged) {
            queued.complete(
              WearDispatchResult.noChange(version: _state.version),
            );
            continue;
          }

          final WearRuntimeVersion nextVersion = _state.version.nextRevision();
          _state = reduction.candidateState.withVersion(nextVersion);
          if (!_stateEvents.isClosed) _stateEvents.add(_state);

          int scheduledEffects = 0;
          for (final WearRuntimeEffect effect in reduction.effects) {
            try {
              _effectRunner.schedule(effect, _dispatchEffectResult);
              scheduledEffects += 1;
            } catch (error, stackTrace) {
              _reportInfrastructureError(error, stackTrace);
            }
          }

          queued.complete(
            WearDispatchResult.accepted(
              version: _state.version,
              scheduledEffectCount: scheduledEffects,
            ),
          );
        } catch (error, stackTrace) {
          _reportInfrastructureError(error, stackTrace);
          queued.complete(
            WearDispatchResult.rejected(
              version: _state.version,
              reason: WearDispatchRejectReason.internalError,
              message: error.toString(),
            ),
          );
        }
      }
    } finally {
      _draining = false;
      if (_queue.isNotEmpty) _scheduleDrain();
    }
  }

  Future<WearDispatchResult> _dispatchEffectResult(WearIntent intent) {
    return dispatch(intent);
  }

  void _reportInfrastructureError(Object error, StackTrace stackTrace) {
    final handler = _onInfrastructureError;
    if (handler != null) {
      handler(error, stackTrace);
      return;
    }
    Zone.current.handleUncaughtError(error, stackTrace);
  }

  @override
  Future<void> dispose() {
    final Completer<void>? existing = _disposeCompleter;
    if (existing != null) return existing.future;

    final Completer<void> completer = Completer<void>();
    _disposeCompleter = completer;
    _accepting = false;

    if (!_state.terminal) {
      _state = _state
          .copyWith(
            terminal: true,
            expectedOperations: _state.expectedOperations.clearAll(),
          )
          .withVersion(_state.version.nextRevision());
      if (!_stateEvents.isClosed) _stateEvents.add(_state);
    }

    while (_queue.isNotEmpty) {
      _queue.removeFirst().complete(
            WearDispatchResult.rejected(
              version: _state.version,
              reason: WearDispatchRejectReason.terminal,
            ),
          );
    }

    unawaited(
      Future<void>.sync(_effectRunner.dispose).whenComplete(() async {
        if (!_stateEvents.isClosed) await _stateEvents.close();
        if (!completer.isCompleted) completer.complete();
      }),
    );
    return completer.future;
  }
}

final class _QueuedDispatch {
  _QueuedDispatch({
    required this.intent,
    required this.completer,
  });

  final WearIntent intent;
  final Completer<WearDispatchResult> completer;

  void complete(WearDispatchResult result) {
    if (!completer.isCompleted) completer.complete(result);
  }
}
