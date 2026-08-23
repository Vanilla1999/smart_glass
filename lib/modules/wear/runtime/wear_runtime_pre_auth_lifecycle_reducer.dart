import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_core_slices.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_store.dart';

/// Allows the application runtime to prepare badge scanning before a user
/// session exists, without opening anonymous runtime activity on other screens.
class WearPreAuthLifecycleReducer implements WearSliceReducer {
  const WearPreAuthLifecycleReducer();

  @override
  WearReduction? reduceSlice(WearRuntimeState state, WearIntent intent) {
    if (intent is! WearRuntimeActiveChanged || !intent.active) return null;

    final WearAggregatePayload aggregate =
        state.payloadAs<WearAggregatePayload>();
    if (aggregate.session.isAuthorized) return null;
    if (aggregate.navigation.logicalScreen != WearScreenId.main) {
      return WearReduction.reject(WearDispatchRejectReason.unsupported);
    }
    if (aggregate.lifecycle.runtimeActive) return WearReduction.accept();

    return WearReduction.accept(
      nextState: state.withPayload(aggregate.copyWith(
        lifecycle: aggregate.lifecycle.copyWith(runtimeActive: true),
      )),
    );
  }
}
