import 'dart:async';

import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_authority.dart';

class WearUiEffectConsumer {
  WearUiEffectConsumer({
    required this.authority,
    required this.kind,
    required this.expectedScreen,
    required this.execute,
  }) {
    _subscription = authority.states.listen((_) => _consumePending());
    unawaited(_consumePending());
  }

  final WearRuntimeAuthority authority;
  final WearUiEffectKind kind;
  final WearScreenId expectedScreen;
  final Future<void> Function(WearUiEffect effect) execute;

  late final StreamSubscription<WearRuntimeState> _subscription;
  bool _consuming = false;
  bool _active = true;

  Future<WearDispatchResult> request({
    WearInputModality modality = WearInputModality.manual,
  }) async {
    final WearDispatchResult result = await authority.dispatchSemanticInput(
      kind: WearSemanticInputKind.requestUiEffect,
      modality: modality,
      expectedScreen: expectedScreen,
      uiEffectKind: kind,
    );
    if (result.accepted) await _consumePending();
    return result;
  }

  Future<void> _consumePending() async {
    if (!_active || _consuming) return;
    final WearAggregatePayload payload = authority.payload;
    if (!payload.lifecycle.phoneUiActive ||
        payload.navigation.logicalScreen != expectedScreen) {
      return;
    }
    WearUiEffect? effect;
    for (final WearUiEffect candidate in payload.uiEffects.effects) {
      if (candidate.kind == kind &&
          candidate.expectedScreen == expectedScreen &&
          candidate.sessionEpoch == authority.state.sessionEpoch &&
          candidate.status == WearUiEffectStatus.pending) {
        effect = candidate;
        break;
      }
    }
    if (effect == null) return;

    _consuming = true;
    try {
      final WearDispatchResult claimed = await authority.claimUiEffect(effect);
      if (!claimed.stateChanged) return;
      if (!_active) {
        await authority.cancelUiEffect(effect);
        return;
      }
      await execute(effect);
    } finally {
      _consuming = false;
    }
  }

  void dispose() {
    _active = false;
    unawaited(_subscription.cancel());
  }
}
