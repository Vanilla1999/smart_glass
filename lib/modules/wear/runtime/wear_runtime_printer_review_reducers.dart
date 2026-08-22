import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/models/wear_printer.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_core_slices.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_printer_slice.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_store.dart';

class WearPrinterInputValidationReducer implements WearSliceReducer {
  const WearPrinterInputValidationReducer();

  @override
  WearReduction? reduceSlice(WearRuntimeState state, WearIntent intent) {
    if (intent is WearPrinterEntered && intent.loadOperationId <= 0) {
      return WearReduction.reject(WearDispatchRejectReason.unsupported);
    }
    if (intent is WearPrinterReloadRequested && intent.operationId <= 0) {
      return WearReduction.reject(WearDispatchRejectReason.unsupported);
    }
    if (intent is WearPrinterSelected && intent.navigationOperationId <= 0) {
      return WearReduction.reject(WearDispatchRejectReason.unsupported);
    }
    if (intent is WearPrinterSelectionImported) {
      final String whiteId = intent.selection.whitePrinter.id.trim();
      final String yellowId = intent.selection.yellowPrinter.id.trim();
      if (whiteId.isEmpty || yellowId.isEmpty || whiteId == yellowId) {
        return WearReduction.reject(WearDispatchRejectReason.unsupported);
      }
    }
    if (intent is WearPrintersLoaded) {
      final Set<String> ids = <String>{};
      for (final WearPrinter printer in intent.printers) {
        final String id = printer.id.trim();
        if (id.isEmpty || id != printer.id || !ids.add(id)) {
          return _invalidLoadedResult(
            state,
            intent,
            'Список принтеров содержит пустой или повторяющийся ID',
          );
        }
      }
    }
    return null;
  }

  WearReduction _invalidLoadedResult(
    WearRuntimeState state,
    WearPrintersLoaded intent,
    String message,
  ) {
    final WearAggregatePayload aggregate =
        state.payloadAs<WearAggregatePayload>();
    final WearFeaturePayload rawFeatures = aggregate.features;
    if (rawFeatures is! WearRuntimeFeaturePayload ||
        intent.sessionEpoch != state.sessionEpoch ||
        state.expectedOperationId(WearLoadPrintersEffect.loadOperationKind) !=
            intent.operationId) {
      return WearReduction.reject(WearDispatchRejectReason.staleOperation);
    }
    final WearPrinterTaskSlice failed = rawFeatures.printer.copyWith(
      phase: WearPrinterTaskPhase.error,
      error: message,
    );
    return WearReduction.accept(
      nextState: state
          .clearExpectedOperation(WearLoadPrintersEffect.loadOperationKind)
          .withPayload(
            aggregate.copyWith(
              features: rawFeatures.copyWith(printer: failed),
            ),
          ),
    );
  }
}

/// Handles entry from another logical screen before the normal printer
/// reducer. Any pending load/navigation identity from the abandoned visit is
/// superseded atomically with the new printer entry.
class WearPrinterReentryReducer implements WearSliceReducer {
  const WearPrinterReentryReducer();

  @override
  WearReduction? reduceSlice(WearRuntimeState state, WearIntent intent) {
    if (intent is! WearPrinterEntered) return null;
    final WearAggregatePayload aggregate =
        state.payloadAs<WearAggregatePayload>();
    if (aggregate.navigation.logicalScreen == WearScreenId.printerSelect) {
      return null;
    }
    final WearFeaturePayload rawFeatures = aggregate.features;
    if (rawFeatures is! WearRuntimeFeaturePayload) return null;

    WearPrinterTaskSlice printer = rawFeatures.printer.copyWith(
      returnSelection: intent.returnSelection,
      clearError: true,
    );
    WearRuntimeState nextState = state
        .clearExpectedOperation(WearLoadPrintersEffect.loadOperationKind)
        .clearExpectedOperation(
          WearNavigateAfterPrinterSelectionEffect.navigationOperationKind,
        );
    if (printer.isLoading) {
      printer = printer.copyWith(phase: WearPrinterTaskPhase.idle);
    }

    final WearNavigationSlice navigation = aggregate.navigation.request(
      WearScreenId.printerSelect,
    );
    WearAggregatePayload nextAggregate = aggregate.copyWith(
      navigation: navigation,
      features: rawFeatures.copyWith(printer: printer),
    );
    nextState = nextState
        .withLegacy(
          WearLegacyRuntimeSnapshot(
            logicalScreen: WearScreenId.printerSelect,
            sourceRevision: state.legacy.sourceRevision + 1,
          ),
        )
        .withPayload(nextAggregate);

    if (printer.printers.isNotEmpty) {
      return WearReduction.accept(
        nextState: nextState.withPayload(
          nextAggregate.copyWith(
            features: rawFeatures.copyWith(
              printer: printer.copyWith(phase: WearPrinterTaskPhase.ready),
            ),
          ),
        ),
      );
    }

    final WearPrinterTaskSlice loading = printer.copyWith(
      phase: WearPrinterTaskPhase.loading,
    );
    nextAggregate = nextAggregate.copyWith(
      features: rawFeatures.copyWith(printer: loading),
    );
    nextState = nextState
        .withPayload(nextAggregate)
        .expectOperation(
          kind: WearLoadPrintersEffect.loadOperationKind,
          operationId: intent.loadOperationId,
        );
    return WearReduction.accept(
      nextState: nextState,
      effects: <WearEffect>[
        WearLoadPrintersEffect(
          sessionEpoch: state.sessionEpoch,
          operationId: intent.loadOperationId,
        ),
      ],
    );
  }
}
