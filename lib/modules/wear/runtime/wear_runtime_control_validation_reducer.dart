import 'package:smart_glasses/modules/wear/runtime/wear_runtime_control_slices.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_core_slices.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_store.dart';

class WearControlInputValidationReducer implements WearSliceReducer {
  const WearControlInputValidationReducer();

  @override
  WearReduction? reduceSlice(WearRuntimeState state, WearIntent intent) {
    if (intent is WearBarcodeDeliveryAccepted && intent.deliveryId < 0) {
      return WearReduction.reject(WearDispatchRejectReason.unsupported);
    }
    if (intent is WearVoiceControlObserved &&
        (intent.observationRevision <= 0 || intent.captureEpoch < 0)) {
      return WearReduction.reject(WearDispatchRejectReason.unsupported);
    }
    if (intent is WearScannerHardwareObserved &&
        intent.observationRevision <= 0) {
      return WearReduction.reject(WearDispatchRejectReason.unsupported);
    }
    if (intent is WearConnectivityObserved && intent.observationRevision <= 0) {
      return WearReduction.reject(WearDispatchRejectReason.unsupported);
    }
    return null;
  }
}
