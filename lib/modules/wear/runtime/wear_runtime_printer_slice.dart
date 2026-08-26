import 'dart:collection';

import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/models/wear_printer.dart';
import 'package:smart_glasses/modules/wear/models/wear_printer_selection.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_core_slices.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_store.dart';

enum WearPrinterTaskPhase { idle, loading, ready, error }

enum WearPrinterTaskStep { white, yellow }

class WearPrinterTaskSlice {
  WearPrinterTaskSlice({
    required this.phase,
    required Iterable<WearPrinter> printers,
    required this.step,
    required this.focusedIndex,
    required this.whitePrinter,
    required this.selection,
    required this.returnSelection,
    this.selectionRevision = 0,
    this.error,
  }) : printers = UnmodifiableListView<WearPrinter>(
          List<WearPrinter>.of(printers),
        );

  factory WearPrinterTaskSlice.initial() {
    return WearPrinterTaskSlice(
      phase: WearPrinterTaskPhase.idle,
      printers: const <WearPrinter>[],
      step: WearPrinterTaskStep.white,
      focusedIndex: 0,
      whitePrinter: null,
      selection: null,
      returnSelection: false,
    );
  }

  final WearPrinterTaskPhase phase;
  final UnmodifiableListView<WearPrinter> printers;
  final WearPrinterTaskStep step;
  final int focusedIndex;
  final WearPrinter? whitePrinter;
  final WearPrinterSelection? selection;
  final bool returnSelection;
  final int selectionRevision;
  final String? error;

  bool get isLoading => phase == WearPrinterTaskPhase.loading;

  List<WearPrinter> get visiblePrinters {
    final WearPrinter? white = whitePrinter;
    if (step == WearPrinterTaskStep.yellow && white != null) {
      return List<WearPrinter>.unmodifiable(
        printers.where((WearPrinter item) => item.id != white.id),
      );
    }
    return printers;
  }

  WearPrinterTaskSlice copyWith({
    WearPrinterTaskPhase? phase,
    Iterable<WearPrinter>? printers,
    WearPrinterTaskStep? step,
    int? focusedIndex,
    WearPrinter? whitePrinter,
    WearPrinterSelection? selection,
    bool? returnSelection,
    int? selectionRevision,
    String? error,
    bool clearWhite = false,
    bool clearSelection = false,
    bool clearError = false,
  }) {
    return WearPrinterTaskSlice(
      phase: phase ?? this.phase,
      printers: printers ?? this.printers,
      step: step ?? this.step,
      focusedIndex: focusedIndex ?? this.focusedIndex,
      whitePrinter: clearWhite ? null : whitePrinter ?? this.whitePrinter,
      selection: clearSelection ? null : selection ?? this.selection,
      returnSelection: returnSelection ?? this.returnSelection,
      selectionRevision: selectionRevision ?? this.selectionRevision,
      error: clearError ? null : error ?? this.error,
    );
  }

  WearPrinterTaskSlice reset() => WearPrinterTaskSlice.initial();
}

abstract interface class WearScanFeaturePayload {}

class WearLegacyScanFeaturePayload implements WearScanFeaturePayload {
  const WearLegacyScanFeaturePayload();
}

abstract interface class WearAvailabilityFeaturePayload {}

class WearLegacyAvailabilityFeaturePayload
    implements WearAvailabilityFeaturePayload {
  const WearLegacyAvailabilityFeaturePayload();
}

class WearRuntimeFeaturePayload implements WearFeaturePayload {
  const WearRuntimeFeaturePayload({
    required this.printer,
    required this.scan,
    required this.availability,
  });

  factory WearRuntimeFeaturePayload.initial() {
    return WearRuntimeFeaturePayload(
      printer: WearPrinterTaskSlice.initial(),
      scan: const WearLegacyScanFeaturePayload(),
      availability: const WearLegacyAvailabilityFeaturePayload(),
    );
  }

  final WearPrinterTaskSlice printer;
  final WearScanFeaturePayload scan;
  final WearAvailabilityFeaturePayload availability;

  WearRuntimeFeaturePayload copyWith({
    WearPrinterTaskSlice? printer,
    WearScanFeaturePayload? scan,
    WearAvailabilityFeaturePayload? availability,
  }) {
    return WearRuntimeFeaturePayload(
      printer: printer ?? this.printer,
      scan: scan ?? this.scan,
      availability: availability ?? this.availability,
    );
  }
}

class WearPrinterEntered extends WearIntent {
  const WearPrinterEntered({
    required this.returnSelection,
    required this.loadOperationId,
  });

  final bool returnSelection;
  final int loadOperationId;
}

class WearPrinterReloadRequested extends WearIntent {
  const WearPrinterReloadRequested({required this.operationId});

  final int operationId;
}

class WearPrintersLoaded extends WearIntent {
  const WearPrintersLoaded({
    required this.sessionEpoch,
    required this.operationId,
    required this.printers,
  });

  final int sessionEpoch;
  final int operationId;
  final List<WearPrinter> printers;
}

class WearPrintersLoadFailed extends WearIntent {
  const WearPrintersLoadFailed({
    required this.sessionEpoch,
    required this.operationId,
    required this.message,
  });

  final int sessionEpoch;
  final int operationId;
  final String message;
}

class WearPrinterFocusChanged extends WearIntent {
  const WearPrinterFocusChanged(this.index);

  final int index;
}

class WearPrinterFocusMoved extends WearIntent {
  const WearPrinterFocusMoved(this.delta);

  final int delta;
}

class WearPrinterPageMoved extends WearIntent {
  const WearPrinterPageMoved(this.delta);

  final int delta;
}

class WearPrinterSelected extends WearIntent {
  const WearPrinterSelected({
    required this.printerId,
    required this.navigationOperationId,
  });

  final String printerId;
  final int navigationOperationId;
}

class WearPrinterSelectionImported extends WearIntent {
  const WearPrinterSelectionImported(this.selection);

  final WearPrinterSelection selection;
}

class WearPrinterSelectionCleared extends WearIntent {
  const WearPrinterSelectionCleared();
}

class WearPrinterTaskReset extends WearIntent {
  const WearPrinterTaskReset();
}

class WearPrinterReturnSelectionCancelled extends WearIntent {
  const WearPrinterReturnSelectionCancelled();
}

class WearLoadPrintersEffect extends WearEffect {
  const WearLoadPrintersEffect({
    required super.sessionEpoch,
    required super.operationId,
  }) : super(kind: loadOperationKind);

  static const String loadOperationKind = 'printer.load';
}

class WearNavigateAfterPrinterSelectionEffect extends WearEffect {
  const WearNavigateAfterPrinterSelectionEffect({
    required super.sessionEpoch,
    required super.operationId,
    required this.selection,
  }) : super(kind: navigationOperationKind);

  static const String navigationOperationKind = 'printer.navigate.scan';

  final WearPrinterSelection selection;
}

class WearPrinterNavigationFailed extends WearIntent {
  const WearPrinterNavigationFailed({
    required this.sessionEpoch,
    required this.operationId,
    required this.message,
  });

  final int sessionEpoch;
  final int operationId;
  final String message;
}

class WearPrinterSliceReducer implements WearSliceReducer {
  const WearPrinterSliceReducer();

  static const int pageSize = 4;

  @override
  WearReduction? reduceSlice(WearRuntimeState state, WearIntent intent) {
    final WearAggregatePayload aggregate =
        state.payloadAs<WearAggregatePayload>();
    final WearFeaturePayload rawFeatures = aggregate.features;
    if (rawFeatures is! WearRuntimeFeaturePayload) return null;
    final WearRuntimeFeaturePayload features = rawFeatures;
    final WearPrinterTaskSlice printer = features.printer;

    if (intent is WearPrinterEntered) {
      WearRuntimeState nextState =
          _ensurePrinterLogicalScreen(state, aggregate);
      final WearAggregatePayload nextAggregate =
          nextState.payloadAs<WearAggregatePayload>();
      final WearRuntimeFeaturePayload nextFeatures =
          nextAggregate.features as WearRuntimeFeaturePayload;
      final WearPrinterTaskSlice entered = nextFeatures.printer.copyWith(
        returnSelection: intent.returnSelection,
        step: intent.returnSelection ? WearPrinterTaskStep.white : null,
        focusedIndex: intent.returnSelection ? 0 : null,
        clearWhite: intent.returnSelection,
      );
      if (entered.printers.isNotEmpty && !intent.returnSelection) {
        return _commitPrinter(
          nextState,
          nextAggregate,
          nextFeatures,
          entered.copyWith(
            phase: WearPrinterTaskPhase.ready,
            clearError: true,
          ),
        );
      }
      return _startLoad(
        nextState,
        nextAggregate,
        nextFeatures,
        entered,
        operationId: intent.loadOperationId,
      );
    }

    if (intent is WearPrinterReloadRequested) {
      if (aggregate.navigation.logicalScreen != WearScreenId.printerSelect) {
        return WearReduction.reject(WearDispatchRejectReason.staleScreen);
      }
      return _startLoad(
        state,
        aggregate,
        features,
        printer,
        operationId: intent.operationId,
      );
    }

    if (intent is WearPrintersLoaded) {
      final WearDispatchRejectReason? stale = _loadResultRejection(
        state,
        aggregate,
        printer,
        sessionEpoch: intent.sessionEpoch,
        operationId: intent.operationId,
      );
      if (stale != null) return WearReduction.reject(stale);
      final WearPrinterTaskSlice reconciled = _reconcileAfterReload(
        printer,
        intent.printers,
      ).copyWith(
        phase: WearPrinterTaskPhase.ready,
        focusedIndex: 0,
        clearError: true,
      );
      return _commitPrinter(
        state.clearExpectedOperation(WearLoadPrintersEffect.loadOperationKind),
        aggregate,
        features,
        reconciled,
      );
    }

    if (intent is WearPrintersLoadFailed) {
      final WearDispatchRejectReason? stale = _loadResultRejection(
        state,
        aggregate,
        printer,
        sessionEpoch: intent.sessionEpoch,
        operationId: intent.operationId,
      );
      if (stale != null) return WearReduction.reject(stale);
      return _commitPrinter(
        state.clearExpectedOperation(WearLoadPrintersEffect.loadOperationKind),
        aggregate,
        features,
        printer.copyWith(
          phase: WearPrinterTaskPhase.error,
          error: intent.message,
        ),
      );
    }

    if (intent is WearPrinterFocusChanged) {
      if (!_canInteract(aggregate, printer)) {
        return WearReduction.reject(WearDispatchRejectReason.busy);
      }
      final List<WearPrinter> visible = printer.visiblePrinters;
      if (visible.isEmpty) {
        return WearReduction.reject(WearDispatchRejectReason.unsupported);
      }
      final int next = intent.index.clamp(0, visible.length - 1);
      if (next == printer.focusedIndex) return WearReduction.accept();
      return _commitPrinter(
        state,
        aggregate,
        features,
        printer.copyWith(focusedIndex: next),
      );
    }

    if (intent is WearPrinterFocusMoved) {
      return reduceSlice(
        state,
        WearPrinterFocusChanged(printer.focusedIndex + intent.delta),
      );
    }

    if (intent is WearPrinterPageMoved) {
      return reduceSlice(
        state,
        WearPrinterFocusChanged(
          printer.focusedIndex + intent.delta * pageSize,
        ),
      );
    }

    if (intent is WearPrinterSelected) {
      if (!_canInteract(aggregate, printer)) {
        return WearReduction.reject(WearDispatchRejectReason.busy);
      }
      if (state.expectedOperationId(
            WearNavigateAfterPrinterSelectionEffect.navigationOperationKind,
          ) !=
          null) {
        return WearReduction.reject(WearDispatchRejectReason.busy);
      }
      final WearPrinter? selected = _findVisible(printer, intent.printerId);
      if (selected == null) {
        return WearReduction.reject(WearDispatchRejectReason.unsupported);
      }
      if (printer.step == WearPrinterTaskStep.white) {
        return _commitPrinter(
          state,
          aggregate,
          features,
          printer.copyWith(
            whitePrinter: selected,
            step: WearPrinterTaskStep.yellow,
            focusedIndex: 0,
            clearError: true,
          ),
        );
      }
      final WearPrinter? white = printer.whitePrinter;
      if (white == null || white.id == selected.id) {
        return WearReduction.reject(WearDispatchRejectReason.unsupported);
      }
      final WearPrinterSelection selection = WearPrinterSelection(
        whitePrinter: white,
        yellowPrinter: selected,
      );
      final WearPrinterTaskSlice completed = printer.copyWith(
        selection: selection,
        selectionRevision: printer.selectionRevision + 1,
        clearError: true,
      );
      if (printer.returnSelection) {
        return _commitPrinter(
          state,
          aggregate,
          features,
          completed,
        );
      }
      if (intent.navigationOperationId < 0) {
        return WearReduction.reject(WearDispatchRejectReason.unsupported);
      }
      final WearNavigationSlice navigation = aggregate.navigation.request(
        WearScreenId.scanIdle,
      );
      final WearAggregatePayload navigatedAggregate = aggregate.copyWith(
        navigation: navigation,
        features: features.copyWith(printer: completed),
      );
      final WearRuntimeState navigatedState = state
          .withLegacy(
            WearLegacyRuntimeSnapshot(
              logicalScreen: WearScreenId.scanIdle,
              sourceRevision: state.legacy.sourceRevision + 1,
            ),
          )
          .withPayload(navigatedAggregate)
          .expectOperation(
            kind:
                WearNavigateAfterPrinterSelectionEffect.navigationOperationKind,
            operationId: intent.navigationOperationId,
          );
      return WearReduction.accept(
        nextState: navigatedState,
        effects: <WearEffect>[
          WearNavigateAfterPrinterSelectionEffect(
            sessionEpoch: state.sessionEpoch,
            operationId: intent.navigationOperationId,
            selection: selection,
          ),
        ],
      );
    }

    if (intent is WearPrinterSelectionImported) {
      final List<WearPrinter> nextPrinters = <WearPrinter>[
        ...printer.printers.where(
          (WearPrinter item) =>
              item.id != intent.selection.whitePrinter.id &&
              item.id != intent.selection.yellowPrinter.id,
        ),
        intent.selection.whitePrinter,
        intent.selection.yellowPrinter,
      ];
      return _commitPrinter(
        state,
        aggregate,
        features,
        printer.copyWith(
          phase: WearPrinterTaskPhase.ready,
          printers: nextPrinters,
          whitePrinter: intent.selection.whitePrinter,
          selection: intent.selection,
          selectionRevision: printer.selectionRevision + 1,
          step: WearPrinterTaskStep.yellow,
          clearError: true,
        ),
      );
    }

    if (intent is WearPrinterSelectionCleared) {
      if (printer.whitePrinter == null && printer.selection == null) {
        return WearReduction.accept();
      }
      return _commitPrinter(
        state,
        aggregate,
        features,
        printer.copyWith(
          step: WearPrinterTaskStep.white,
          focusedIndex: 0,
          clearWhite: true,
          clearSelection: true,
        ),
      );
    }

    if (intent is WearPrinterReturnSelectionCancelled) {
      if (!printer.returnSelection) return WearReduction.accept();
      final WearPrinterSelection? committed = printer.selection;
      return _commitPrinter(
        state,
        aggregate,
        features,
        printer.copyWith(
          returnSelection: false,
          step: committed == null
              ? WearPrinterTaskStep.white
              : WearPrinterTaskStep.yellow,
          focusedIndex: 0,
          whitePrinter: committed?.whitePrinter,
          clearWhite: committed == null,
          clearError: true,
        ),
      );
    }

    if (intent is WearPrinterNavigationFailed) {
      if (intent.sessionEpoch != state.sessionEpoch) {
        return WearReduction.reject(WearDispatchRejectReason.staleEpoch);
      }
      if (state.expectedOperationId(
            WearNavigateAfterPrinterSelectionEffect.navigationOperationKind,
          ) !=
          intent.operationId) {
        return WearReduction.reject(WearDispatchRejectReason.staleOperation);
      }
      return _commitPrinter(
        state.clearExpectedOperation(
          WearNavigateAfterPrinterSelectionEffect.navigationOperationKind,
        ),
        aggregate,
        features,
        printer.copyWith(
          phase: WearPrinterTaskPhase.error,
          error: intent.message,
        ),
      );
    }

    if (intent is WearPrinterTaskReset) {
      return _commitPrinter(
        state
            .clearExpectedOperation(WearLoadPrintersEffect.loadOperationKind)
            .clearExpectedOperation(
              WearNavigateAfterPrinterSelectionEffect.navigationOperationKind,
            ),
        aggregate,
        features,
        printer.reset(),
      );
    }

    return null;
  }

  WearReduction _startLoad(
    WearRuntimeState state,
    WearAggregatePayload aggregate,
    WearRuntimeFeaturePayload features,
    WearPrinterTaskSlice printer, {
    required int operationId,
  }) {
    if (printer.isLoading ||
        state.expectedOperationId(WearLoadPrintersEffect.loadOperationKind) !=
            null) {
      return WearReduction.reject(WearDispatchRejectReason.busy);
    }
    if (operationId < 0) {
      return WearReduction.reject(WearDispatchRejectReason.unsupported);
    }
    final WearPrinterTaskSlice loading = printer.copyWith(
      phase: WearPrinterTaskPhase.loading,
      clearError: true,
    );
    final WearRuntimeState nextState = state
        .withPayload(
          aggregate.copyWith(features: features.copyWith(printer: loading)),
        )
        .expectOperation(
          kind: WearLoadPrintersEffect.loadOperationKind,
          operationId: operationId,
        );
    return WearReduction.accept(
      nextState: nextState,
      effects: <WearEffect>[
        WearLoadPrintersEffect(
          sessionEpoch: state.sessionEpoch,
          operationId: operationId,
        ),
      ],
    );
  }

  WearDispatchRejectReason? _loadResultRejection(
    WearRuntimeState state,
    WearAggregatePayload aggregate,
    WearPrinterTaskSlice printer, {
    required int sessionEpoch,
    required int operationId,
  }) {
    if (sessionEpoch != state.sessionEpoch) {
      return WearDispatchRejectReason.staleEpoch;
    }
    if (aggregate.navigation.logicalScreen != WearScreenId.printerSelect) {
      return WearDispatchRejectReason.staleScreen;
    }
    if (!printer.isLoading ||
        state.expectedOperationId(WearLoadPrintersEffect.loadOperationKind) !=
            operationId) {
      return WearDispatchRejectReason.staleOperation;
    }
    return null;
  }

  bool _canInteract(
    WearAggregatePayload aggregate,
    WearPrinterTaskSlice printer,
  ) {
    return aggregate.navigation.logicalScreen == WearScreenId.printerSelect &&
        !printer.isLoading;
  }

  WearPrinter? _findVisible(
    WearPrinterTaskSlice printer,
    String id,
  ) {
    for (final WearPrinter item in printer.visiblePrinters) {
      if (item.id == id) return item;
    }
    return null;
  }

  WearRuntimeState _ensurePrinterLogicalScreen(
    WearRuntimeState state,
    WearAggregatePayload aggregate,
  ) {
    if (aggregate.navigation.logicalScreen == WearScreenId.printerSelect) {
      return state;
    }
    return state
        .withLegacy(
          WearLegacyRuntimeSnapshot(
            logicalScreen: WearScreenId.printerSelect,
            sourceRevision: state.legacy.sourceRevision + 1,
          ),
        )
        .withPayload(
          aggregate.copyWith(
            navigation: aggregate.navigation.request(
              WearScreenId.printerSelect,
            ),
          ),
        );
  }

  WearReduction _commitPrinter(
    WearRuntimeState state,
    WearAggregatePayload aggregate,
    WearRuntimeFeaturePayload features,
    WearPrinterTaskSlice printer,
  ) {
    return WearReduction.accept(
      nextState: state.withPayload(
        aggregate.copyWith(features: features.copyWith(printer: printer)),
      ),
    );
  }

  WearPrinterTaskSlice _reconcileAfterReload(
    WearPrinterTaskSlice current,
    List<WearPrinter> refreshed,
  ) {
    final Map<String, WearPrinter> byId = <String, WearPrinter>{
      for (final WearPrinter item in refreshed) item.id: item,
    };
    final WearPrinter? currentWhite = current.whitePrinter;
    final WearPrinterSelection? committed = current.selection;
    if (current.returnSelection && currentWhite == null && committed != null) {
      final WearPrinter? white = byId[committed.whitePrinter.id];
      final WearPrinter? yellow = byId[committed.yellowPrinter.id];
      if (white != null && yellow != null && white.id != yellow.id) {
        return current.copyWith(
          printers: refreshed,
          selection: WearPrinterSelection(
            whitePrinter: white,
            yellowPrinter: yellow,
          ),
          step: WearPrinterTaskStep.white,
        );
      }
    }
    if (currentWhite == null) {
      return current.copyWith(
        printers: refreshed,
        step: current.selection == null
            ? current.step
            : WearPrinterTaskStep.white,
        clearSelection: current.selection != null,
      );
    }
    final WearPrinter? white = byId[currentWhite.id];
    if (white == null) {
      return current.copyWith(
        printers: refreshed,
        step: WearPrinterTaskStep.white,
        clearWhite: true,
        clearSelection: true,
      );
    }
    final WearPrinterSelection? selection = current.selection;
    if (selection == null) {
      return current.copyWith(
        printers: refreshed,
        whitePrinter: white,
        step: WearPrinterTaskStep.yellow,
      );
    }
    final WearPrinter? yellow = byId[selection.yellowPrinter.id];
    if (yellow == null || yellow.id == white.id) {
      return current.copyWith(
        printers: refreshed,
        whitePrinter: white,
        step: WearPrinterTaskStep.yellow,
        clearSelection: true,
      );
    }
    return current.copyWith(
      printers: refreshed,
      whitePrinter: white,
      selection: WearPrinterSelection(
        whitePrinter: white,
        yellowPrinter: yellow,
      ),
      step: WearPrinterTaskStep.yellow,
    );
  }
}
