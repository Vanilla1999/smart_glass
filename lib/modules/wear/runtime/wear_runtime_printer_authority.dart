import 'package:smart_glasses/modules/wear/models/wear_printer.dart';
import 'package:smart_glasses/modules/wear/models/wear_printer_selection.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_authority_impl.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_printer_slice.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_store.dart';

extension WearRuntimePrinterAuthority on WearRuntimeAuthority {
  WearPrinterTaskSlice get printerTask => features.printer;

  Future<WearDispatchResult> enterPrinterScreen({
    bool returnSelection = false,
  }) {
    return store.dispatch(
      WearPrinterEntered(
        returnSelection: returnSelection,
        loadOperationId: allocateOperationId(),
      ),
    );
  }

  Future<WearDispatchResult> reloadPrinters() {
    return store.dispatch(
      WearPrinterReloadRequested(operationId: allocateOperationId()),
    );
  }

  Future<WearDispatchResult> focusPrinter(int index) {
    return store.dispatch(WearPrinterFocusChanged(index));
  }

  Future<WearDispatchResult> movePrinterFocus(int delta) {
    return store.dispatch(WearPrinterFocusMoved(delta));
  }

  Future<WearDispatchResult> movePrinterPage(int delta) {
    return store.dispatch(WearPrinterPageMoved(delta));
  }

  Future<WearDispatchResult> selectPrinterById(String printerId) {
    return store.dispatch(
      WearPrinterSelected(
        printerId: printerId,
        navigationOperationId: allocateOperationId(),
      ),
    );
  }

  Future<WearDispatchResult> selectPrinter(WearPrinter printer) {
    return selectPrinterById(printer.id);
  }

  Future<WearDispatchResult> importPrinterSelection(
    WearPrinterSelection selection,
  ) {
    return store.dispatch(WearPrinterSelectionImported(selection));
  }

  Future<WearDispatchResult> clearPrinterSelection() {
    return store.dispatch(const WearPrinterSelectionCleared());
  }

  Future<WearDispatchResult> resetPrinterTask() {
    return store.dispatch(const WearPrinterTaskReset());
  }
}
