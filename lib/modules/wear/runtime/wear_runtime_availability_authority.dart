import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_authority_impl.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_availability_slice.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_store.dart';

extension WearRuntimeAvailabilityAuthority on WearRuntimeAuthority {
  WearAvailabilityTaskSlice get availabilityTask =>
      features.availability as WearAvailabilityTaskSlice;

  Future<WearDispatchResult> enterAvailabilityScreen(
    WearScreenId screen, {
    Object? extra,
  }) {
    return store.dispatch(WearAvailabilityEntered(screen: screen, extra: extra));
  }

  Future<WearDispatchResult> focusAvailabilityItem(int index) {
    return store.dispatch(WearAvailabilityFocusChanged(index));
  }

  Future<WearDispatchResult> moveAvailabilityFocus(int delta) {
    return store.dispatch(WearAvailabilityFocusMoved(delta));
  }

  Future<WearDispatchResult> moveAvailabilityPage(int delta) {
    return store.dispatch(WearAvailabilityPageMoved(delta));
  }

  Future<WearDispatchResult> selectAvailabilityItem(String itemId) {
    return store.dispatch(WearAvailabilityItemSelected(itemId));
  }

  Future<WearDispatchResult> submitAvailabilityBarcode(String barcode) {
    return store.dispatch(WearAvailabilityBarcodeReceived(barcode));
  }

  Future<WearDispatchResult> answerAvailability(bool available) {
    return store.dispatch(WearAvailabilityAnswered(available));
  }

  Future<WearDispatchResult> printAvailabilityPriceTag() {
    return store.dispatch(const WearAvailabilityPrintRequested());
  }

  Future<WearDispatchResult> captureAvailabilityPhoto() {
    return store.dispatch(const WearAvailabilityPhotoRequested());
  }

  Future<WearDispatchResult> completeAvailability() {
    return store.dispatch(const WearAvailabilityCompleteRequested());
  }

  Future<WearDispatchResult> resetAvailabilityFill() {
    return store.dispatch(const WearAvailabilityFillResetRequested());
  }

  Future<WearDispatchResult> returnAvailabilityToList() {
    return store.dispatch(const WearAvailabilityBackToListRequested());
  }

  Future<WearDispatchResult> resetAvailabilityTask() {
    return store.dispatch(const WearAvailabilityTaskReset());
  }
}
