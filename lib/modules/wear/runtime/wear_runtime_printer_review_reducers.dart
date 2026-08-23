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
      final WearPrinter white = intent.selection.whitePrinter;
      final WearPrinter yellow = intent.selection.yellowPrinter;
      if (!_validPrinter(white) ||
          !_validPrinter(yellow) ||
          white.id == yellow.id) {
        return WearReduction.reject(WearDispatchRejectReason.unsupported);
      }
    }
    if (intent is WearPrintersLoaded) {
      final Set<String> ids = <String>{};
      for (final WearPrinter printer in intent.printers) {
        if (!_validPrinter(printer) || !ids.add(printer.id)) {
          return _invalidLoadedResult(
            state,
            intent,
            'Список принтеров содержит пустой, ненормализованный или повторяющийся элемент',
          );
        }
      }
    }
    return null;
  }

  bool _validPrinter(WearPrinter printer) {
    final String id = printer.id.trim();
    final String name = printer.name.trim();
    return id.isNotEmpty &&
        id == printer.id &&
        name.isNotEmpty &&
        name == printer.name;
  }

  WearReduction _invalidLoadedResult(
    WearRuntimeState state,
    WearPrintersLoaded intent,
    String message,
  ) {
    final WearAggregatePayload aggregate =
        state.payloadAs<WearAggregatePayload>();
    final WearFeaturePayload rawFeatures = aggregate.features;
    if (rawFeatures is! WearRuntimeFeaturePayload) {
      return WearReduction.reject(WearDispatchRejectReason.unsupported);
    }
    if (intent.sessionEpoch != state.sessionEpoch) {
      return WearReduction.reject(WearDispatchRejectReason.staleEpoch);
    }
    if (aggregate.navigation.logicalScreen != WearScreenId.printerSelect) {
      return WearReduction.reject(WearDispatchRejectReason.staleScreen);
    }
    final WearPrinterTaskSlice printer = rawFeatures.printer;
    if (!printer.isLoading ||
        state.expectedOperationId(WearLoadPrintersEffect.loadOperationKind) !=
            intent.operationId) {
      return WearReduction.reject(WearDispatchRejectReason.staleOperation);
    }
    final WearPrinterTaskSlice failed = printer.copyWith(
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
