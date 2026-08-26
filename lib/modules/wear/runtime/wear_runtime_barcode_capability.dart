import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_availability_slice.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_core_slices.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_printer_slice.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_scan_slice.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_store.dart';

bool selectWearBarcodeCapability(WearRuntimeState state) {
  if (state.terminal) return false;
  final WearAggregatePayload aggregate =
      state.payloadAs<WearAggregatePayload>();
  if (aggregate.lifecycle.terminal || !aggregate.lifecycle.runtimeActive) {
    return false;
  }
  final WearScreenId screen = aggregate.navigation.logicalScreen;
  final WearRuntimeFeaturePayload features =
      aggregate.features as WearRuntimeFeaturePayload;
  if (screen == WearScreenId.scanIdle) {
    final WearScanTaskSlice task = features.scan as WearScanTaskSlice;
    return task.screen == screen && task.phase == WearScanTaskPhase.waiting;
  }
  final availability = features.availability;
  return availability is WearAvailabilityTaskSlice &&
      availability.acceptsBarcode(screen);
}
