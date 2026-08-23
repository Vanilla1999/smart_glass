import 'package:smart_glasses/modules/wear/runtime/wear_runtime_core_slices.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_printer_navigation_guard.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_printer_review_reducers.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_printer_slice.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_store.dart';

class WearReviewedPrinterSliceReducer implements WearSliceReducer {
  const WearReviewedPrinterSliceReducer();

  static const List<WearSliceReducer> _reducers = <WearSliceReducer>[
    WearPrinterInputValidationReducer(),
    WearPrinterReentryReducer(),
    WearPrinterNavigationFailureGuard(),
    WearPrinterSliceReducer(),
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
