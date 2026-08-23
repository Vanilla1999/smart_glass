import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_core_slices.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_printer_slice.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_store.dart';

class WearPrinterNavigationFailureGuard implements WearSliceReducer {
  const WearPrinterNavigationFailureGuard();

  @override
  WearReduction? reduceSlice(WearRuntimeState state, WearIntent intent) {
    if (intent is! WearPrinterNavigationFailed) return null;
    if (intent.sessionEpoch != state.sessionEpoch) return null;
    if (state.expectedOperationId(
          WearNavigateAfterPrinterSelectionEffect.navigationOperationKind,
        ) !=
        intent.operationId) {
      return null;
    }
    final WearAggregatePayload aggregate =
        state.payloadAs<WearAggregatePayload>();
    if (aggregate.navigation.logicalScreen != WearScreenId.scanIdle) {
      return WearReduction.reject(WearDispatchRejectReason.staleScreen);
    }
    return null;
  }
}
