import 'dart:async';

import 'package:smart_glasses/modules/wear/runtime/wear_runtime_store.dart';

abstract interface class WearLegacySnapshotSource {
  WearLegacyRuntimeSnapshot get currentSnapshot;

  Stream<WearLegacyRuntimeSnapshot> get snapshots;
}

/// One-way compatibility adapter from the current legacy owner into the new
/// aggregate shell.
///
/// The adapter has no API that can write back into the legacy source. Later
/// migration MRs remove one mirror at a time when ownership is transferred.
class WearLegacySnapshotMirror {
  WearLegacySnapshotMirror({
    required WearLegacySnapshotSource source,
    required WearRuntimeStore store,
  })  : _source = source,
        _store = store;

  final WearLegacySnapshotSource _source;
  final WearRuntimeStore _store;

  StreamSubscription<WearLegacyRuntimeSnapshot>? _subscription;
  final StreamController<Object> _errorsController =
      StreamController<Object>.broadcast(sync: true);
  Future<void>? _startFuture;
  bool _disposed = false;

  Stream<Object> get errors => _errorsController.stream;

  Future<void> start() {
    final Future<void>? existing = _startFuture;
    if (existing != null) return existing;
    if (_disposed) {
      return Future<void>.error(
        StateError('Cannot start a disposed legacy snapshot mirror'),
      );
    }

    final Completer<void> completer = Completer<void>();
    _startFuture = completer.future;
    unawaited(
      Future<void>.sync(() async {
        final WearDispatchResult initial = await _store.dispatch(
          WearObserveLegacySnapshot(_source.currentSnapshot),
        );
        if (!initial.accepted) {
          throw StateError(
            'Cannot attach mirror: ${initial.rejectReason}',
          );
        }
        if (_disposed) {
          completer.complete();
          return;
        }
        _subscription = _source.snapshots.listen(
          (WearLegacyRuntimeSnapshot snapshot) {
            unawaited(
              _forward(snapshot),
            );
          },
          onError: (Object error, StackTrace stackTrace) {
            if (!completer.isCompleted) {
              completer.completeError(error, stackTrace);
            } else if (!_errorsController.isClosed) {
              _errorsController.add(error);
            }
          },
        );
        completer.complete();
      }).catchError((Object error, StackTrace stackTrace) {
        _startFuture = null;
        if (!completer.isCompleted) completer.completeError(error, stackTrace);
      }),
    );
    return completer.future;
  }

  Future<void> _forward(WearLegacyRuntimeSnapshot snapshot) async {
    try {
      final WearDispatchResult result = await _store.dispatch(
        WearObserveLegacySnapshot(snapshot),
      );
      if (!result.accepted && !_errorsController.isClosed) {
        _errorsController.add(
          StateError('Legacy snapshot rejected: ${result.rejectReason}'),
        );
      }
    } on Object catch (error) {
      if (!_errorsController.isClosed) _errorsController.add(error);
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _subscription?.cancel();
    _subscription = null;
    await _errorsController.close();
  }
}
