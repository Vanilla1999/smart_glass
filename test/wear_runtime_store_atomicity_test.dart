import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_store.dart';

void main() {
  WearRuntimeState initialState() {
    return WearRuntimeState.initial(
      legacy: WearLegacyRuntimeSnapshot(
        logicalScreen: WearScreenId.menu,
        sourceRevision: 0,
      ),
    );
  }

  test('invalid effect identity cannot publish a partial snapshot', () async {
    final WearRuntimeStore store = WearRuntimeStore(
      initialState: initialState(),
      reducer: const _InvalidEffectReducer(),
    );
    addTearDown(store.dispose);

    final WearDispatchResult result =
        await store.dispatch(const _InvalidEffectIntent());

    expect(result.accepted, isFalse);
    expect(result.rejectReason, WearDispatchRejectReason.internalError);
    expect(store.state.revision, 0);
    expect(store.state.expectedOperationIds, isEmpty);
  });

  test('unexpected effect error can be converted to a typed result intent',
      () async {
    final WearRuntimeStore store = WearRuntimeStore(
      initialState: initialState(),
      reducer: const WearRuntimeShellReducer(),
      effectHandler: const _ThrowingEffectHandler(),
      effectErrorIntentFactory: (
        WearEffect effect,
        Object _,
        StackTrace __,
      ) {
        return WearOperationResult(
          sessionEpoch: effect.sessionEpoch,
          operationId: effect.operationId,
          kind: effect.kind,
        );
      },
    );
    addTearDown(store.dispose);

    final WearDispatchResult receipt = await store.dispatch(
      const WearBeginOperation(
        effect: _TestEffect(
          sessionEpoch: 0,
          operationId: 1,
          kind: 'recoverable',
        ),
      ),
    );
    expect(receipt.accepted, isTrue);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(store.state.expectedOperationId('recoverable'), isNull);
    expect(store.state.revision, 2);
  });

  test('dispose creates terminal barrier without awaiting a blocked effect',
      () async {
    final Completer<WearIntent?> blocked = Completer<WearIntent?>();
    final WearRuntimeStore store = WearRuntimeStore(
      initialState: initialState(),
      reducer: const WearRuntimeShellReducer(),
      effectHandler: _BlockingEffectHandler(blocked.future),
    );

    await store.dispatch(
      const WearBeginOperation(
        effect: _TestEffect(
          sessionEpoch: 0,
          operationId: 1,
          kind: 'blocked',
        ),
      ),
    );
    await store.dispose();

    expect(blocked.isCompleted, isFalse);
    expect(store.state.terminal, isTrue);
    expect(store.state.expectedOperationIds, isEmpty);
    final WearDispatchResult late =
        await store.dispatch(const WearNoopIntent());
    expect(late.rejectReason, WearDispatchRejectReason.terminal);

    blocked.complete(
      const WearOperationResult(
        sessionEpoch: 0,
        operationId: 1,
        kind: 'blocked',
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(store.state.terminal, isTrue);
    expect(store.state.sessionEpoch, 1);
  });

  test('operation ids are monotonic', () {
    final WearOperationIdGenerator ids = WearOperationIdGenerator();

    expect(ids.next(), 1);
    expect(ids.next(), 2);
    expect(ids.next(), 3);
  });

  test('runtime maps are immutable snapshots', () {
    final WearRuntimeState state = initialState().expectOperation(
      kind: 'lookup',
      operationId: 1,
    );

    expect(
      () => state.expectedOperationIds['other'] = 2,
      throwsUnsupportedError,
    );
    expect(
      () => state.legacy.diagnostics['other'] = 'value',
      throwsUnsupportedError,
    );
  });
}

class _InvalidEffectIntent extends WearIntent {
  const _InvalidEffectIntent();
}

class _InvalidEffectReducer implements WearRuntimeReducer {
  const _InvalidEffectReducer();

  @override
  WearReduction reduce(WearRuntimeState state, WearIntent intent) {
    if (intent is! _InvalidEffectIntent) {
      return WearReduction.reject(WearDispatchRejectReason.unsupported);
    }
    return WearReduction.accept(
      nextState: state.expectOperation(kind: 'expected', operationId: 1),
      effects: const <WearEffect>[
        _TestEffect(
          sessionEpoch: 0,
          operationId: 1,
          kind: 'different',
        ),
      ],
    );
  }
}

class _TestEffect extends WearEffect {
  const _TestEffect({
    required super.sessionEpoch,
    required super.operationId,
    required super.kind,
  });
}

class _ThrowingEffectHandler implements WearEffectHandler {
  const _ThrowingEffectHandler();

  @override
  Future<WearIntent?> handle(WearEffect effect) {
    throw StateError('expected effect failure');
  }
}

class _BlockingEffectHandler implements WearEffectHandler {
  const _BlockingEffectHandler(this.result);

  final Future<WearIntent?> result;

  @override
  Future<WearIntent?> handle(WearEffect effect) => result;
}
