import 'dart:async';

import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_authority_impl.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_core_slices.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_presentation_slice.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_store.dart';

/// Host timer adapter for aggregate generic-status operations.
///
/// The deadline and operation identity remain in [WearRuntimeState]. This class
/// owns only a cancellable timer and can return one typed elapsed intent.
class WearRuntimePresentationScheduler {
  WearRuntimePresentationScheduler(
    this._authority, {
    DateTime Function()? now,
    FutureOr<void> Function()? onElapsedAccepted,
  }) : _now = now ?? DateTime.now {
    _onElapsedAccepted = onElapsedAccepted;
    _subscription = _authority.states.listen(_onState);
  }

  final WearRuntimeAuthority _authority;
  final DateTime Function() _now;
  late final FutureOr<void> Function()? _onElapsedAccepted;
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
    final Duration delay = deadline.difference(_now());
    _timer = Timer(delay.isNegative ? Duration.zero : delay, () {
      if (_scheduled != key) return;
      _timer = null;
      _scheduled = null;
      unawaited(_dispatchElapsed(key));
    });
  }

  Future<void> _dispatchElapsed(
    ({int epoch, int operationId}) key,
  ) async {
    final WearDispatchResult result =
        await _authority.store.dispatch(WearGenericStatusElapsed(
      sessionEpoch: key.epoch,
      operationId: key.operationId,
    ));
    if (result.accepted) await _onElapsedAccepted?.call();
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
