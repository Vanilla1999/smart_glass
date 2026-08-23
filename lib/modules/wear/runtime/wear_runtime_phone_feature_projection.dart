import 'dart:collection';

import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/domain/price_tag_print/model/barcode_product_info.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/status/wear_status_args.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_core_slices.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_printer_slice.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_scan_slice.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_store.dart';
import 'package:smart_glasses/modules/wear/theme/wear_images.dart';

/// Immutable phone projection of the authoritative aggregate scan slice.
///
/// This projection owns no state and never advances the runtime revision. It is
/// intentionally richer than the generic phone list projection because scan
/// screens need typed products and status data rather than strings only.
class WearScanPhoneProjection {
  WearScanPhoneProjection({
    required this.version,
    required this.logicalScreen,
    required this.phase,
    required this.barcode,
    required Iterable<BarcodeProductInfo> products,
    required this.focusedIndex,
    required this.productName,
    required this.status,
  }) : products = UnmodifiableListView<BarcodeProductInfo>(
          List<BarcodeProductInfo>.unmodifiable(products),
        );

  factory WearScanPhoneProjection.fromState(WearRuntimeState state) {
    final WearAggregatePayload aggregate =
        state.payloadAs<WearAggregatePayload>();
    final WearRuntimeFeaturePayload features =
        aggregate.features as WearRuntimeFeaturePayload;
    final WearScanTaskSlice scan = features.scan as WearScanTaskSlice;
    final int focusedIndex = scan.products.isEmpty
        ? 0
        : scan.focusedIndex.clamp(0, scan.products.length - 1);
    return WearScanPhoneProjection(
      version: state.version,
      logicalScreen: aggregate.navigation.logicalScreen,
      phase: scan.phase,
      barcode: scan.barcode,
      products: scan.products,
      focusedIndex: focusedIndex,
      productName: scan.productName,
      status: scan.status,
    );
  }

  final WearRuntimeVersion version;
  final WearScreenId logicalScreen;
  final WearScanTaskPhase phase;
  final String? barcode;
  final UnmodifiableListView<BarcodeProductInfo> products;
  final int focusedIndex;
  final String? productName;
  final WearStatusScreenArgs? status;

  bool get isLoading =>
      phase == WearScanTaskPhase.lookingUp ||
      phase == WearScanTaskPhase.printing;

  String get loadingText => phase == WearScanTaskPhase.printing
      ? 'Печатаю ценник...'
      : 'ШК отсканирован, распознаю...';

  String get loadingIcon => phase == WearScanTaskPhase.printing
      ? WearImages.printer
      : WearImages.barcode;

  BarcodeProductInfo? productById(int productId) {
    for (final BarcodeProductInfo product in products) {
      if (product.id == productId) return product;
    }
    return null;
  }
}
