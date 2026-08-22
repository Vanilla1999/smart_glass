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
  Future<void>? _startFuture;
  bool _disposed = false;

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
    Future<void>.sync(() async {
      await _store.dispatch(
        WearObserveLegacySnapshot(_source.currentSnapshot),
      );
      if (_disposed) {
        completer.complete();
        return;
      }
      _subscription = _source.snapshots.listen(
        (WearLegacyRuntimeSnapshot snapshot) {
          unawaited(
            _store.dispatch(WearObserveLegacySnapshot(snapshot)),
          );
        },
      );
      completer.complete();
    }).catchError((Object error, StackTrace stackTrace) {
      if (!completer.isCompleted) completer.completeError(error, stackTrace);
    });
    return completer.future;
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _subscription?.cancel();
    _subscription = null;
  }
}
