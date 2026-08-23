import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/status/wear_status_args.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_core_slices.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_printer_slice.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_scan_slice.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_store.dart';

class WearScanPrinterSelectionGuard implements WearSliceReducer {
  const WearScanPrinterSelectionGuard();

  @override
  WearReduction? reduceSlice(WearRuntimeState state, WearIntent intent) {
    final WearAggregatePayload aggregate =
        state.payloadAs<WearAggregatePayload>();
    final WearFeaturePayload rawFeatures = aggregate.features;
    if (rawFeatures is! WearRuntimeFeaturePayload ||
        rawFeatures.scan is! WearScanTaskSlice ||
        rawFeatures.printer.selection != null) {
      return null;
    }
    final WearScanTaskSlice scan = rawFeatures.scan as WearScanTaskSlice;

    if (intent is WearBarcodeLookupSucceeded && intent.products.length == 1) {
      if (intent.sessionEpoch != state.sessionEpoch) {
        return WearReduction.reject(WearDispatchRejectReason.staleEpoch);
      }
      if (aggregate.navigation.logicalScreen != WearScreenId.scanIdle ||
          scan.screen != WearScreenId.scanIdle) {
        return WearReduction.reject(WearDispatchRejectReason.staleScreen);
      }
      if (scan.phase != WearScanTaskPhase.lookingUp ||
          state.expectedOperationId(WearLookupBarcodeEffect.operationKind) !=
              intent.operationId) {
        return WearReduction.reject(WearDispatchRejectReason.staleOperation);
      }
      return _enterMissingPrinterStatus(
        state.clearExpectedOperation(WearLookupBarcodeEffect.operationKind),
        aggregate,
        rawFeatures,
        scan,
      );
    }

    if (intent is WearScanProductSelected) {
      if (aggregate.navigation.logicalScreen != WearScreenId.productSelect ||
          scan.screen != WearScreenId.productSelect ||
          scan.phase != WearScanTaskPhase.selecting) {
        return WearReduction.reject(WearDispatchRejectReason.staleScreen);
      }
      if (!scan.products.any((item) => item.id == intent.productId)) {
        return WearReduction.reject(WearDispatchRejectReason.unsupported);
      }
      return _enterMissingPrinterStatus(
        state,
        aggregate,
        rawFeatures,
        scan,
      );
    }

    return null;
  }

  WearReduction _enterMissingPrinterStatus(
    WearRuntimeState state,
    WearAggregatePayload aggregate,
    WearRuntimeFeaturePayload features,
    WearScanTaskSlice scan,
  ) {
    final ({WearScanTaskSlice task, int operationId}) allocation =
        scan.allocateOperation();
    const WearStatusScreenArgs args = WearStatusScreenArgs(
      kind: WearStatusKind.error,
      title: 'Ошибка печати',
      message: 'Выбор принтеров больше не актуален',
      autoAfter: Duration(seconds: 3),
      autoExtra: WearScreenId.scanIdle,
      autoAction: WearStatusAutoAction.none,
    );
    final WearScanTaskSlice status = allocation.task.copyWith(
      phase: WearScanTaskPhase.status,
      screen: WearScreenId.status,
      status: args,
    );
    final WearNavigationSlice navigation =
        aggregate.navigation.logicalScreen == WearScreenId.status
            ? aggregate.navigation
            : aggregate.navigation.request(WearScreenId.status);
    final WearRuntimeState next = state
        .clearExpectedOperation(WearPresentScanStatusEffect.operationKind)
        .clearExpectedOperation(WearScanStatusDelayEffect.operationKind)
        .withLegacy(
          WearLegacyRuntimeSnapshot(
            logicalScreen: WearScreenId.status,
            sourceRevision: state.legacy.sourceRevision + 1,
          ),
        )
        .withPayload(
          aggregate.copyWith(
            navigation: navigation,
            features: features.copyWith(scan: status),
          ),
        )
        .expectOperation(
          kind: WearPresentScanStatusEffect.operationKind,
          operationId: allocation.operationId,
        );
    return WearReduction.accept(
      nextState: next,
      effects: <WearEffect>[
        WearPresentScanStatusEffect(
          sessionEpoch: state.sessionEpoch,
          operationId: allocation.operationId,
          args: args,
        ),
      ],
    );
  }
}
