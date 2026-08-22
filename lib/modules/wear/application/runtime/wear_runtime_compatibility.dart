import 'dart:async';

import 'package:smart_glasses/modules/wear/application/runtime/wear_runtime_contract.dart';
import 'package:smart_glasses/modules/wear/application/runtime/wear_runtime_state.dart';
import 'package:smart_glasses/modules/wear/application/runtime/wear_runtime_store.dart';
import 'package:smart_glasses/modules/wear/application/wear_flow_controller.dart';
import 'package:smart_glasses/modules/wear/application/wear_flow_state.dart';

abstract interface class WearLegacyRuntimeSnapshotSource {
  WearLegacyRuntimeView read();

  Stream<WearLegacyRuntimeView> get changes;
}

final class WearFlowControllerSnapshotSource
    implements WearLegacyRuntimeSnapshotSource {
  WearFlowControllerSnapshotSource(this._controller);

  final WearFlowController _controller;
  int _sourceRevision = 0;

  @override
  WearLegacyRuntimeView read() {
    return _snapshot(_controller.state);
  }

  @override
  Stream<WearLegacyRuntimeView> get changes {
    return _controller.stateStream.map(_snapshot);
  }

  WearLegacyRuntimeView _snapshot(WearFlowState flow) {
    return WearLegacyRuntimeView(
      flow: flow,
      sourceRevision: _sourceRevision++,
    );
  }
}

final class WearRuntimeCompatibilityFacade {
  WearRuntimeCompatibilityFacade({
    required WearRuntimeStore store,
    required WearLegacyRuntimeSnapshotSource source,
  })  : _store = store,
        _source = source;

  final WearRuntimeStore _store;
  final WearLegacyRuntimeSnapshotSource _source;
  StreamSubscription<WearLegacyRuntimeView>? _subscription;
  bool _disposed = false;

  Future<WearDispatchResult> synchronize() {
    if (_disposed) {
      return Future<WearDispatchResult>.value(
        WearDispatchResult.rejected(
          version: _store.state.version,
          reason: WearDispatchRejectReason.terminal,
        ),
      );
    }
    return _store.dispatch(WearLegacySnapshotObserved(_source.read()));
  }

  Future<void> start() async {
    if (_disposed || _subscription != null) return;
    _subscription = _source.changes.listen(
      (WearLegacyRuntimeView snapshot) {
        unawaited(_store.dispatch(WearLegacySnapshotObserved(snapshot)));
      },
    );
    await synchronize();
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _subscription?.cancel();
    _subscription = null;
  }
}
