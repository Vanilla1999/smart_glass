import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_control_slices.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_core_slices.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_store.dart';

/// Preserves badge-scanner admission before a Wear session exists.
///
/// The ordinary control reducer intentionally requires an authorized runtime.
/// Badge authorization is the one exception: it is allowed only when both the
/// aggregate logical screen and observed phone route are `main`, the hardware is
/// prepared, and the registered screen capability accepts a barcode.
class WearPreAuthScannerAdmissionReducer implements WearSliceReducer {
  const WearPreAuthScannerAdmissionReducer();

  @override
  WearReduction? reduceSlice(WearRuntimeState state, WearIntent intent) {
    if (intent is! WearScannerAdmissionEvaluated) return null;

    final WearAggregatePayload aggregate =
        state.payloadAs<WearAggregatePayload>();
    final WearControlPayload rawControls = aggregate.controls;
    if (rawControls is! WearRuntimeControlPayload ||
        aggregate.session.isAuthorized ||
        aggregate.navigation.logicalScreen != WearScreenId.main) {
      return null;
    }
    if (intent.sessionEpoch != state.sessionEpoch) {
      return WearReduction.reject(WearDispatchRejectReason.staleEpoch);
    }
    if (intent.logicalScreen != WearScreenId.main) {
      return WearReduction.reject(WearDispatchRejectReason.staleScreen);
    }

    final WearScannerControlSlice scanner = rawControls.scanner;
    final bool routeMatches = aggregate.lifecycle.phoneUiActive &&
        aggregate.navigation.actualPhoneScreen == WearScreenId.main;
    final bool enabled = !state.terminal &&
        !aggregate.lifecycle.terminal &&
        routeMatches &&
        scanner.hardwarePrepared &&
        intent.screenAcceptsBarcode;
    if (scanner.barcodeAdmissionEnabled == enabled &&
        scanner.expectedLogicalScreen == WearScreenId.main) {
      return WearReduction.accept();
    }

    return WearReduction.accept(
      nextState: state.withPayload(aggregate.copyWith(
        controls: rawControls.copyWith(
          scanner: scanner.copyWith(
            barcodeAdmissionEnabled: enabled,
            expectedLogicalScreen: WearScreenId.main,
          ),
        ),
      )),
    );
  }
}
