import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_authority_impl.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_scan_slice.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_store.dart';

extension WearRuntimeScanAuthority on WearRuntimeAuthority {
  WearScanTaskSlice get scanTask => features.scan as WearScanTaskSlice;

  Future<WearDispatchResult> enterScanScreen(
    WearScreenId screen, {
    Object? extra,
  }) {
    return store.dispatch(WearScanEntered(screen: screen, extra: extra));
  }

  Future<WearDispatchResult> submitScanBarcode(String barcode) {
    return store.dispatch(WearScanBarcodeReceived(barcode));
  }

  Future<WearDispatchResult> focusScanProduct(int index) {
    return store.dispatch(WearScanFocusChanged(index));
  }

  Future<WearDispatchResult> moveScanFocus(int delta) {
    return store.dispatch(WearScanFocusMoved(delta));
  }

  Future<WearDispatchResult> moveScanPage(int delta) {
    return store.dispatch(WearScanPageMoved(delta));
  }

  Future<WearDispatchResult> selectScanProduct(int productId) {
    return store.dispatch(WearScanProductSelected(productId));
  }

  Future<WearDispatchResult> resetScanTask() {
    return store.dispatch(const WearScanTaskReset());
  }
}
