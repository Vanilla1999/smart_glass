import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/domain/price_tag_print/model/barcode_product_info.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_core_slices.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_printer_slice.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_scan_slice.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_store.dart';

class WearScanResultAdmissionReducer implements WearSliceReducer {
  const WearScanResultAdmissionReducer();

  @override
  WearReduction? reduceSlice(WearRuntimeState state, WearIntent intent) {
    final WearAggregatePayload aggregate =
        state.payloadAs<WearAggregatePayload>();
    final WearFeaturePayload rawFeatures = aggregate.features;
    if (rawFeatures is! WearRuntimeFeaturePayload ||
        rawFeatures.scan is! WearScanTaskSlice) {
      return null;
    }
    final WearScanTaskSlice scan = rawFeatures.scan as WearScanTaskSlice;

    if (intent is WearBarcodeLookupSucceeded ||
        intent is WearBarcodeLookupFailed) {
      if (aggregate.navigation.logicalScreen != WearScreenId.scanIdle ||
          scan.screen != WearScreenId.scanIdle) {
        return WearReduction.reject(WearDispatchRejectReason.staleScreen);
      }
    }

    if (intent is WearPriceTagPrintSucceeded ||
        intent is WearPriceTagPrintFailed) {
      if (aggregate.navigation.logicalScreen != scan.screen ||
          (scan.screen != WearScreenId.scanIdle &&
              scan.screen != WearScreenId.productSelect)) {
        return WearReduction.reject(WearDispatchRejectReason.staleScreen);
      }
    }

    if (intent is WearScanStatusElapsed ||
        intent is WearScanStatusPresentationFailed) {
      if (aggregate.navigation.logicalScreen != WearScreenId.status ||
          scan.screen != WearScreenId.status) {
        return WearReduction.reject(WearDispatchRejectReason.staleScreen);
      }
    }

    if (intent is WearBarcodeLookupSucceeded) {
      final Set<int> ids = <int>{};
      for (final BarcodeProductInfo product in intent.products) {
        if (!ids.add(product.id)) {
          return const WearScanSliceReducer().reduceSlice(
            state,
            WearBarcodeLookupFailed(
              sessionEpoch: intent.sessionEpoch,
              operationId: intent.operationId,
              message: 'Ответ поиска содержит повторяющийся ID товара',
            ),
          );
        }
      }
    }

    return null;
  }
}

class WearReviewedScanSliceReducer implements WearSliceReducer {
  const WearReviewedScanSliceReducer();

  static const List<WearSliceReducer> _reducers = <WearSliceReducer>[
    WearScanResultAdmissionReducer(),
    WearScanSliceReducer(),
  ];

  @override
  WearReduction? reduceSlice(WearRuntimeState state, WearIntent intent) {
    for (final WearSliceReducer reducer in _reducers) {
      final WearReduction? reduction = reducer.reduceSlice(state, intent);
      if (reduction != null) return reduction;
    }
    return null;
  }
}
