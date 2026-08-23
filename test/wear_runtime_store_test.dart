import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_legacy_snapshot_mirror.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_store.dart';

void main() {
  WearLegacyRuntimeSnapshot snapshot({
    required int sourceRevision,
    WearScreenId screen = WearScreenId.menu,
  }) {
    return WearLegacyRuntimeSnapshot(
      logicalScreen: screen,
      sourceRevision: sourceRevision,
    );
  }

  test('new subscriber receives current snapshot immediately', () async {
    final WearRuntimeStore store = WearRuntimeStore(
      initialState: WearRuntimeState.initial(
        legacy: snapshot(sourceRevision: 0),
      ),
      reducer: const WearRuntimeShellReducer(),
    );
    addTearDown(store.dispose);

    expect(await store.states.first, same(store.state));
  });

  test('no-op intent does not publish or increment revision', () async {
    final WearRuntimeStore store = WearRuntimeStore(
      initialState: WearRuntimeState.initial(
        legacy: snapshot(sourceRevision: 0),
      ),
      reducer: const WearRuntimeShellReducer(),
    );
    addTearDown(store.dispose);
    final List<WearRuntimeState> states = <WearRuntimeState>[];
    final StreamSubscription<WearRuntimeState> subscription =
        store.states.listen(states.add);
    addTearDown(subscription.cancel);
    await Future<void>.delayed(Duration.zero);

    final WearDispatchResult result =
        await store.dispatch(const WearNoopIntent());

    expect(result.accepted, isTrue);
    expect(result.stateChanged, isFalse);
    expect(result.revision, 0);
    expect(store.state.revision, 0);
    expect(states, hasLength(1));
  });

  test('legacy mirror is read-only and revisions are monotonic', () async {
    final WearRuntimeStore store = WearRuntimeStore(
      initialState: WearRuntimeState.initial(
        legacy: snapshot(sourceRevision: 0),
      ),
      reducer: const WearRuntimeShellReducer(),
    );
    addTearDown(store.dispose);

    final WearDispatchResult first = await store.dispatch(
      WearObserveLegacySnapshot(
        snapshot(sourceRevision: 1, screen: WearScreenId.printerSelect),
      ),
    );
    final WearDispatchResult sameSnapshot = await store.dispatch(
      WearObserveLegacySnapshot(
        snapshot(sourceRevision: 1, screen: WearScreenId.printerSelect),
      ),
    );
    final WearDispatchResult stale = await store.dispatch(
      WearObserveLegacySnapshot(snapshot(sourceRevision: 0)),
    );

    expect(first.accepted, isTrue);
    expect(first.stateChanged, isTrue);
    expect(first.revision, 1);
    expect(store.state.legacy.logicalScreen, WearScreenId.printerSelect);
    expect(sameSnapshot.accepted, isTrue);
    expect(sameSnapshot.stateChanged, isFalse);
    expect(sameSnapshot.revision, 1);
    expect(stale.accepted, isFalse);
    expect(stale.rejectReason, WearDispatchRejectReason.staleSnapshot);
    expect(store.state.revision, 1);
  });

  test('new epoch supersedes every revision of the old epoch', () async {
    final WearRuntimeStore store = WearRuntimeStore(
      initialState: WearRuntimeState.initial(
        legacy: snapshot(sourceRevision: 0),
      ),
      reducer: const WearRuntimeShellReducer(),
    );
    addTearDown(store.dispose);

    await store.dispatch(
      WearObserveLegacySnapshot(snapshot(sourceRevision: 1)),
    );
    await store.dispatch(
      WearObserveLegacySnapshot(snapshot(sourceRevision: 2)),
    );
    final WearRuntimeVersion oldVersion = store.state.version;

    final WearDispatchResult result = await store.dispatch(
      WearAdvanceSessionEpoch(legacy: snapshot(sourceRevision: 0)),
    );

    expect(result.accepted, isTrue);
    expect(result.sessionEpoch, 1);
    expect(result.revision, 0);
    expect(result.version.isNewerThan(oldVersion), isTrue);
  });

  test('snapshot commits before effect starts and receipt does not await effect',
      () async {
    late WearRuntimeStore store;
    final Completer<WearIntent?> effectResult = Completer<WearIntent?>();
    late WearRuntimeState stateSeenByEffect;
    final _EffectHandler handler = _EffectHandler((WearEffect effect) {
      stateSeenByEffect = store.state;
      return effectResult.future;
    });
    store = WearRuntimeStore(
      initialState: WearRuntimeState.initial(
        legacy: snapshot(sourceRevision: 0),
      ),
      reducer: const WearRuntimeShellReducer(),
      effectHandler: handler,
    );
    addTearDown(store.dispose);

    const _TestEffect effect = _TestEffect(
      sessionEpoch: 0,
      operationId: 7,
      kind: 'lookup',
    );
    final WearDispatchResult receipt = await store.dispatch(
      const WearBeginOperation(effect: effect),
    );

    expect(receipt.accepted, isTrue);
    expect(receipt.scheduledEffectCount, 1);
    expect(receipt.revision, 1);
    expect(stateSeenByEffect.expectedOperationId('lookup'), 7);
    expect(effectResult.isCompleted, isFalse);

    effectResult.complete(
      const WearOperationResult(
        sessionEpoch: 0,
        operationId: 7,
        kind: 'lookup',
      ),
    );
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(store.state.expectedOperationId('lookup'), isNull);
    expect(store.state.revision, 2);
  });

  test('nested dispatch is queued after current commit', () async {
    late WearRuntimeStore store;
    final List<int> revisionsSeenByEffect = <int>[];
    final _EffectHandler handler = _EffectHandler((WearEffect effect) async {
      revisionsSeenByEffect.add(store.state.revision);
      final WearDispatchResult nested = await store.dispatch(
        WearObserveLegacySnapshot(
          snapshot(sourceRevision: 1, screen: WearScreenId.scanIdle),
        ),
      );
      expect(nested.revision, 2);
      return const WearOperationResult(
        sessionEpoch: 0,
        operationId: 1,
        kind: 'nested',
      );
    });
    store = WearRuntimeStore(
      initialState: WearRuntimeState.initial(
        legacy: snapshot(sourceRevision: 0),
      ),
      reducer: const WearRuntimeShellReducer(),
      effectHandler: handler,
    );
    addTearDown(store.dispose);

    final WearDispatchResult receipt = await store.dispatch(
      const WearBeginOperation(
        effect: _TestEffect(
          sessionEpoch: 0,
          operationId: 1,
          kind: 'nested',
        ),
      ),
    );
    expect(receipt.revision, 1);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(revisionsSeenByEffect, <int>[1]);
    expect(store.state.legacy.logicalScreen, WearScreenId.scanIdle);
    expect(store.state.expectedOperationId('nested'), isNull);
    expect(store.state.revision, 3);
  });

  test('reducer exception rejects one intent without blocking the queue',
      () async {
    final WearRuntimeStore store = WearRuntimeStore(
      initialState: WearRuntimeState.initial(
        legacy: snapshot(sourceRevision: 0),
      ),
      reducer: const _ThrowingReducer(),
    );
    addTearDown(store.dispose);

    final Future<WearDispatchResult> broken =
        store.dispatch(const _ThrowIntent());
    final Future<WearDispatchResult> next = store.dispatch(
      WearObserveLegacySnapshot(snapshot(sourceRevision: 1)),
    );

    expect(
      (await broken).rejectReason,
      WearDispatchRejectReason.internalError,
    );
    expect((await next).accepted, isTrue);
    expect(store.state.revision, 1);
  });

  test('stale operation result is rejected without mutation', () async {
    final WearRuntimeStore store = WearRuntimeStore(
      initialState: WearRuntimeState.initial(
        legacy: snapshot(sourceRevision: 0),
      ),
      reducer: const WearRuntimeShellReducer(),
    );
    addTearDown(store.dispose);

    await store.dispatch(
      const WearBeginOperation(
        effect: _TestEffect(
          sessionEpoch: 0,
          operationId: 2,
          kind: 'print',
        ),
      ),
    );
    final WearDispatchResult stale = await store.dispatch(
      const WearOperationResult(
        sessionEpoch: 0,
        operationId: 1,
        kind: 'print',
      ),
    );

    expect(stale.accepted, isFalse);
    expect(stale.rejectReason, WearDispatchRejectReason.staleOperation);
    expect(store.state.expectedOperationId('print'), 2);
    expect(store.state.revision, 1);
  });

  test('dispose is idempotent and creates a terminal barrier', () async {
    final WearRuntimeStore store = WearRuntimeStore(
      initialState: WearRuntimeState.initial(
        legacy: snapshot(sourceRevision: 0),
      ),
      reducer: const WearRuntimeShellReducer(),
    );
    final Future<void> first = store.dispose();
    final Future<void> second = store.dispose();

    expect(identical(first, second), isTrue);
    await first;

    expect(store.state.terminal, isTrue);
    expect(store.state.sessionEpoch, 1);
    final WearDispatchResult rejected =
        await store.dispatch(const WearNoopIntent());
    expect(rejected.accepted, isFalse);
    expect(rejected.rejectReason, WearDispatchRejectReason.terminal);
  });

  test('legacy mirror forwards source snapshots one way', () async {
    final _LegacySource source = _LegacySource(snapshot(sourceRevision: 0));
    final WearRuntimeStore store = WearRuntimeStore(
      initialState: WearRuntimeState.initial(
        legacy: snapshot(sourceRevision: 0),
      ),
      reducer: const WearRuntimeShellReducer(),
    );
    final WearLegacySnapshotMirror mirror = WearLegacySnapshotMirror(
      source: source,
      store: store,
    );
    addTearDown(source.dispose);
    addTearDown(mirror.dispose);
    addTearDown(store.dispose);

    await mirror.start();
    source.emit(
      snapshot(sourceRevision: 1, screen: WearScreenId.productSelect),
    );
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(store.state.legacy.logicalScreen, WearScreenId.productSelect);
    expect(store.state.legacy.sourceRevision, 1);
  });

  test('legacy mirror fails when its initial snapshot is rejected', () async {
    final _LegacySource source = _LegacySource(snapshot(sourceRevision: 0));
    final WearRuntimeStore store = WearRuntimeStore(
      initialState: WearRuntimeState.initial(
        legacy: snapshot(sourceRevision: 1),
      ),
      reducer: const WearRuntimeShellReducer(),
    );
    final WearLegacySnapshotMirror mirror = WearLegacySnapshotMirror(
      source: source,
      store: store,
    );
    addTearDown(source.dispose);
    addTearDown(mirror.dispose);
    addTearDown(store.dispose);

    await expectLater(mirror.start(), throwsStateError);
  });

  test('legacy mirror reports rejected updates after attachment', () async {
    final _LegacySource source = _LegacySource(snapshot(sourceRevision: 1));
    final WearRuntimeStore store = WearRuntimeStore(
      initialState: WearRuntimeState.initial(
        legacy: snapshot(sourceRevision: 0),
      ),
      reducer: const WearRuntimeShellReducer(),
    );
    final WearLegacySnapshotMirror mirror = WearLegacySnapshotMirror(
      source: source,
      store: store,
    );
    addTearDown(source.dispose);
    addTearDown(mirror.dispose);
    addTearDown(store.dispose);

    await mirror.start();
    final Future<Object> error = mirror.errors.first;
    source.emit(snapshot(sourceRevision: 0));

    expect(await error, isA<StateError>());
    expect(store.state.legacy.sourceRevision, 1);
  });
}

class _TestEffect extends WearEffect {
  const _TestEffect({
    required super.sessionEpoch,
    required super.operationId,
    required super.kind,
  });
}

class _EffectHandler implements WearEffectHandler {
  const _EffectHandler(this.callback);

  final Future<WearIntent?> Function(WearEffect effect) callback;

  @override
  Future<WearIntent?> handle(WearEffect effect) => callback(effect);
}

class _ThrowIntent extends WearIntent {
  const _ThrowIntent();
}

class _ThrowingReducer implements WearRuntimeReducer {
  const _ThrowingReducer();

  @override
  WearReduction reduce(WearRuntimeState state, WearIntent intent) {
    if (intent is _ThrowIntent) throw StateError('expected reducer failure');
    return const WearRuntimeShellReducer().reduce(state, intent);
  }
}

class _LegacySource implements WearLegacySnapshotSource {
  _LegacySource(this._current);

  WearLegacyRuntimeSnapshot _current;
  final StreamController<WearLegacyRuntimeSnapshot> _controller =
      StreamController<WearLegacyRuntimeSnapshot>.broadcast();

  @override
  WearLegacyRuntimeSnapshot get currentSnapshot => _current;

  @override
  Stream<WearLegacyRuntimeSnapshot> get snapshots => _controller.stream;

  void emit(WearLegacyRuntimeSnapshot snapshot) {
    _current = snapshot;
    _controller.add(snapshot);
  }

  Future<void> dispose() => _controller.close();
}
