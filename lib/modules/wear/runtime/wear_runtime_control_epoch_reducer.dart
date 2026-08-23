import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_core_slices.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_store.dart';

/// Handles session reset before the generic core reducer so control admission
/// from the previous epoch cannot survive into the anonymous session.
class WearControlEpochResetReducer implements WearSliceReducer {
  const WearControlEpochResetReducer();

  @override
  WearReduction? reduceSlice(WearRuntimeState state, WearIntent intent) {
    if (intent is! WearSessionCleared) return null;
    final WearAggregatePayload aggregate =
        state.payloadAs<WearAggregatePayload>();
    if (!aggregate.session.isAuthorized) return WearReduction.accept();

    final WearNavigationSlice previousNavigation = aggregate.navigation;
    final WearNavigationSlice resetNavigation = WearNavigationSlice(
      logicalScreen: WearScreenId.main,
      actualPhoneScreen: null,
      pending: null,
      history: const <WearScreenId>[WearScreenId.main],
      routeObservationRevision:
          previousNavigation.routeObservationRevision,
      nextRequestId: previousNavigation.nextRequestId,
    );
    final WearAggregatePayload nextPayload = aggregate.copyWith(
      session: const WearSessionSlice.anonymous(),
      lifecycle: aggregate.lifecycle.copyWith(runtimeActive: false),
      navigation: resetNavigation,
      controls: aggregate.controls.toTerminalControls(),
    );
    return WearReduction.accept(
      nextState: state.beginNextEpoch(
        legacy: WearLegacyRuntimeSnapshot(
          logicalScreen: WearScreenId.main,
          sourceRevision: state.legacy.sourceRevision + 1,
        ),
        payload: nextPayload,
      ),
    );
  }
}
