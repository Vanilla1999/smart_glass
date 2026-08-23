import 'dart:collection';

import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/domain/availability/model/wear_availability_flow_state.dart';
import 'package:smart_glasses/modules/wear/domain/availability/model/wear_availability_group.dart';
import 'package:smart_glasses/modules/wear/domain/availability/model/wear_availability_product.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_core_slices.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_printer_slice.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_store.dart';

enum WearAvailabilityTaskPhase { idle, ready, busy, error }

enum WearAvailabilityOperation {
  start,
  selectGroup,
  selectProduct,
  selectScannedProduct,
  findBarcode,
  answer,
  scanProduct,
  scanPriceTag,
  printPriceTag,
  capturePhoto,
  complete,
  fillAdd,
  fillReset,
  navigate,
}

extension WearAvailabilityOperationKind on WearAvailabilityOperation {
  String get operationKind => 'availability.$name';
}

WearAvailabilityFlowState freezeAvailabilityFlow(
  WearAvailabilityFlowState flow,
) {
  return WearAvailabilityFlowState(
    step: flow.step,
    groups: List<WearAvailabilityGroup>.unmodifiable(flow.groups),
    products: List<WearAvailabilityProduct>.unmodifiable(flow.products),
    duplicateProducts:
        List<WearAvailabilityProduct>.unmodifiable(flow.duplicateProducts),
    selectedGroup: flow.selectedGroup,
    check: flow.check,
    message: flow.message,
    lastBarcode: flow.lastBarcode,
    printedPrinter: flow.printedPrinter,
  );
}

class WearAvailabilityTaskSlice implements WearAvailabilityFeaturePayload {
  WearAvailabilityTaskSlice({
    required this.phase,
    required this.screen,
    required WearAvailabilityFlowState flow,
    required this.focusedIndex,
    required this.savedCount,
    required this.message,
    required this.error,
    required this.lastAcceptedBarcode,
    required this.lastAcceptedStep,
    required this.nextOperationId,
  }) : flow = freezeAvailabilityFlow(flow);

  factory WearAvailabilityTaskSlice.initial() {
    return WearAvailabilityTaskSlice(
      phase: WearAvailabilityTaskPhase.idle,
      screen: WearScreenId.availabilityGroup,
      flow: const WearAvailabilityFlowState(
        step: WearAvailabilityFlowStep.groupSelection,
      ),
      focusedIndex: 0,
      savedCount: 0,
      message: null,
      error: null,
      lastAcceptedBarcode: null,
      lastAcceptedStep: null,
      nextOperationId: 0,
    );
  }

  final WearAvailabilityTaskPhase phase;
  final WearScreenId screen;
  final WearAvailabilityFlowState flow;
  final int focusedIndex;
  final int savedCount;
  final String? message;
  final String? error;
  final String? lastAcceptedBarcode;
  final WearAvailabilityFlowStep? lastAcceptedStep;
  final int nextOperationId;

  bool get isBusy => phase == WearAvailabilityTaskPhase.busy;

  bool get isDuplicateSelection =>
      screen == WearScreenId.availabilityDirectScan &&
      flow.step == WearAvailabilityFlowStep.duplicateSelection;

  List<Object> get listValues {
    if (screen == WearScreenId.availabilityGroup) return flow.groups;
    if (screen == WearScreenId.availabilityProduct) return flow.products;
    if (isDuplicateSelection) return flow.duplicateProducts;
    return const <Object>[];
  }

  bool acceptsBarcode(WearScreenId logicalScreen) {
    if (isBusy || logicalScreen != screen) return false;
    if (screen == WearScreenId.availabilityDirectScan) {
      return !isDuplicateSelection;
    }
    if (screen == WearScreenId.availabilityFill) return true;
    if (screen != WearScreenId.availabilityCheck) return false;
    return flow.step == WearAvailabilityFlowStep.productScan ||
        flow.step == WearAvailabilityFlowStep.priceTagScan;
  }

  WearAvailabilityTaskSlice copyWith({
    WearAvailabilityTaskPhase? phase,
    WearScreenId? screen,
    WearAvailabilityFlowState? flow,
    int? focusedIndex,
    int? savedCount,
    String? message,
    String? error,
    String? lastAcceptedBarcode,
    WearAvailabilityFlowStep? lastAcceptedStep,
    int? nextOperationId,
    bool clearMessage = false,
    bool clearError = false,
    bool clearBarcodeDedupe = false,
  }) {
    return WearAvailabilityTaskSlice(
      phase: phase ?? this.phase,
      screen: screen ?? this.screen,
      flow: flow ?? this.flow,
      focusedIndex: focusedIndex ?? this.focusedIndex,
      savedCount: savedCount ?? this.savedCount,
      message: clearMessage ? null : message ?? this.message,
      error: clearError ? null : error ?? this.error,
      lastAcceptedBarcode: clearBarcodeDedupe
          ? null
          : lastAcceptedBarcode ?? this.lastAcceptedBarcode,
      lastAcceptedStep: clearBarcodeDedupe
          ? null
          : lastAcceptedStep ?? this.lastAcceptedStep,
      nextOperationId: nextOperationId ?? this.nextOperationId,
    );
  }

  ({WearAvailabilityTaskSlice task, int operationId}) allocateOperation() {
    final int operationId = nextOperationId + 1;
    return (
      task: copyWith(nextOperationId: operationId),
      operationId: operationId,
    );
  }

  WearAvailabilityTaskSlice reset() => WearAvailabilityTaskSlice.initial();
}

class WearAvailabilityEntered extends WearIntent {
  const WearAvailabilityEntered({required this.screen, this.extra});

  final WearScreenId screen;
  final Object? extra;
}

class WearAvailabilityFocusChanged extends WearIntent {
  const WearAvailabilityFocusChanged(this.index);
  final int index;
}

class WearAvailabilityFocusMoved extends WearIntent {
  const WearAvailabilityFocusMoved(this.delta);
  final int delta;
}

class WearAvailabilityPageMoved extends WearIntent {
  const WearAvailabilityPageMoved(this.delta);
  final int delta;
}

class WearAvailabilityItemSelected extends WearIntent {
  const WearAvailabilityItemSelected(this.itemId);
  final String itemId;
}

class WearAvailabilityBarcodeReceived extends WearIntent {
  const WearAvailabilityBarcodeReceived(this.barcode);
  final String barcode;
}

class WearAvailabilityAnswered extends WearIntent {
  const WearAvailabilityAnswered(this.available);
  final bool available;
}

class WearAvailabilityPrintRequested extends WearIntent {
  const WearAvailabilityPrintRequested();
}

class WearAvailabilityPhotoRequested extends WearIntent {
  const WearAvailabilityPhotoRequested();
}

class WearAvailabilityCompleteRequested extends WearIntent {
  const WearAvailabilityCompleteRequested();
}

class WearAvailabilityFillResetRequested extends WearIntent {
  const WearAvailabilityFillResetRequested();
}

class WearAvailabilityBackToListRequested extends WearIntent {
  const WearAvailabilityBackToListRequested();
}

class WearAvailabilityTaskReset extends WearIntent {
  const WearAvailabilityTaskReset();
}

class WearAvailabilityOperationEffect extends WearEffect {
  const WearAvailabilityOperationEffect({
    required super.sessionEpoch,
    required super.operationId,
    required this.operation,
    required this.flow,
    this.group,
    this.product,
    this.barcode,
    this.available,
    this.targetScreen,
    this.navigationExtra,
    this.replaceCurrent = false,
  }) : super(kind: 'availability.${operation.name}');

  final WearAvailabilityOperation operation;
  final WearAvailabilityFlowState flow;
  final WearAvailabilityGroup? group;
  final WearAvailabilityProduct? product;
  final String? barcode;
  final bool? available;
  final WearScreenId? targetScreen;
  final Object? navigationExtra;
  final bool replaceCurrent;
}

class WearAvailabilityOperationSucceeded extends WearIntent {
  const WearAvailabilityOperationSucceeded({
    required this.sessionEpoch,
    required this.operationId,
    required this.operation,
    required this.flow,
    this.addedCount = 0,
    this.message,
  });

  final int sessionEpoch;
  final int operationId;
  final WearAvailabilityOperation operation;
  final WearAvailabilityFlowState flow;
  final int addedCount;
  final String? message;
}

class WearAvailabilityOperationFailed extends WearIntent {
  const WearAvailabilityOperationFailed({
    required this.sessionEpoch,
    required this.operationId,
    required this.operation,
    required this.message,
  });

  final int sessionEpoch;
  final int operationId;
  final WearAvailabilityOperation operation;
  final String message;
}

class WearAvailabilitySliceReducer implements WearSliceReducer {
  const WearAvailabilitySliceReducer();

  static const int pageSize = 4;
  static const Set<WearScreenId> screens = <WearScreenId>{
    WearScreenId.availabilityGroup,
    WearScreenId.availabilityProduct,
    WearScreenId.availabilityDirectScan,
    WearScreenId.availabilityCheck,
    WearScreenId.availabilityFill,
  };

  @override
  WearReduction? reduceSlice(WearRuntimeState state, WearIntent intent) {
    final WearAggregatePayload aggregate =
        state.payloadAs<WearAggregatePayload>();
    final WearFeaturePayload rawFeatures = aggregate.features;
    if (rawFeatures is! WearRuntimeFeaturePayload ||
        rawFeatures.availability is! WearAvailabilityTaskSlice) {
      return null;
    }
    final WearRuntimeFeaturePayload features = rawFeatures;
    final WearAvailabilityTaskSlice task =
        features.availability as WearAvailabilityTaskSlice;

    if (intent is WearAvailabilityEntered) {
      if (!screens.contains(intent.screen)) {
        return WearReduction.reject(WearDispatchRejectReason.unsupported);
      }
      return _enter(state, aggregate, features, task, intent);
    }

    if (intent is WearAvailabilityTaskReset) {
      if (task.phase == WearAvailabilityTaskPhase.idle &&
          task.savedCount == 0) {
        return WearReduction.accept();
      }
      return WearReduction.accept(
        nextState: _replaceTask(
          state,
          aggregate,
          features,
          task.reset(),
        ).clearExpectedOperationPrefix('availability.'),
      );
    }

    if (!screens.contains(aggregate.navigation.logicalScreen) ||
        aggregate.navigation.logicalScreen != task.screen) {
      if (_isAvailabilityInput(intent)) {
        return WearReduction.reject(WearDispatchRejectReason.staleScreen);
      }
      return null;
    }

    if (intent is WearAvailabilityFocusChanged) {
      return _focus(state, aggregate, features, task, intent.index);
    }
    if (intent is WearAvailabilityFocusMoved) {
      return _focus(
        state,
        aggregate,
        features,
        task,
        task.focusedIndex + intent.delta,
      );
    }
    if (intent is WearAvailabilityPageMoved) {
      return _focus(
        state,
        aggregate,
        features,
        task,
        task.focusedIndex + intent.delta * pageSize,
      );
    }
    if (intent is WearAvailabilityItemSelected) {
      return _selectItem(
        state,
        aggregate,
        features,
        task,
        intent.itemId,
      );
    }
    if (intent is WearAvailabilityBarcodeReceived) {
      return _barcode(
        state,
        aggregate,
        features,
        task,
        intent.barcode,
      );
    }
    if (intent is WearAvailabilityAnswered) {
      if (task.flow.step != WearAvailabilityFlowStep.productQuestion) {
        return WearReduction.reject(WearDispatchRejectReason.unsupported);
      }
      return _startEffect(
        state,
        aggregate,
        features,
        task,
        operation: WearAvailabilityOperation.answer,
        available: intent.available,
      );
    }
    if (intent is WearAvailabilityPrintRequested) {
      if (task.flow.step != WearAvailabilityFlowStep.priceTagOutdated) {
        return WearReduction.reject(WearDispatchRejectReason.unsupported);
      }
      return _startEffect(
        state,
        aggregate,
        features,
        task,
        operation: WearAvailabilityOperation.printPriceTag,
      );
    }
    if (intent is WearAvailabilityPhotoRequested) {
      if (task.flow.step != WearAvailabilityFlowStep.photoCapture) {
        return WearReduction.reject(WearDispatchRejectReason.unsupported);
      }
      return _startEffect(
        state,
        aggregate,
        features,
        task,
        operation: WearAvailabilityOperation.capturePhoto,
      );
    }
    if (intent is WearAvailabilityCompleteRequested) {
      if (task.flow.step != WearAvailabilityFlowStep.readyToComplete &&
          task.flow.step != WearAvailabilityFlowStep.manualInventoryRequired) {
        return WearReduction.reject(WearDispatchRejectReason.unsupported);
      }
      return _startEffect(
        state,
        aggregate,
        features,
        task,
        operation: WearAvailabilityOperation.complete,
      );
    }
    if (intent is WearAvailabilityFillResetRequested) {
      if (task.screen != WearScreenId.availabilityFill) {
        return WearReduction.reject(WearDispatchRejectReason.unsupported);
      }
      return _startEffect(
        state,
        aggregate,
        features,
        task,
        operation: WearAvailabilityOperation.fillReset,
      );
    }
    if (intent is WearAvailabilityBackToListRequested) {
      return _startNavigation(
        state,
        aggregate,
        features,
        task,
        target: WearScreenId.availabilityGroup,
      );
    }
    if (intent is WearAvailabilityOperationSucceeded) {
      return _success(state, aggregate, features, task, intent);
    }
    if (intent is WearAvailabilityOperationFailed) {
      return _failure(state, aggregate, features, task, intent);
    }

    return null;
  }

  bool _isAvailabilityInput(WearIntent intent) {
    return intent is WearAvailabilityFocusChanged ||
        intent is WearAvailabilityFocusMoved ||
        intent is WearAvailabilityPageMoved ||
        intent is WearAvailabilityItemSelected ||
        intent is WearAvailabilityBarcodeReceived ||
        intent is WearAvailabilityAnswered ||
        intent is WearAvailabilityPrintRequested ||
        intent is WearAvailabilityPhotoRequested ||
        intent is WearAvailabilityCompleteRequested ||
        intent is WearAvailabilityFillResetRequested ||
        intent is WearAvailabilityBackToListRequested;
  }

  WearReduction _enter(
    WearRuntimeState state,
    WearAggregatePayload aggregate,
    WearRuntimeFeaturePayload features,
    WearAvailabilityTaskSlice current,
    WearAvailabilityEntered intent,
  ) {
    final bool sameScreen = current.screen == intent.screen &&
        aggregate.navigation.logicalScreen == intent.screen;
    if (sameScreen && current.isBusy) {
      return WearReduction.reject(WearDispatchRejectReason.busy);
    }

    WearAvailabilityTaskSlice next = current.copyWith(
      phase: WearAvailabilityTaskPhase.ready,
      screen: intent.screen,
      focusedIndex: 0,
      clearError: true,
      clearBarcodeDedupe: !sameScreen,
    );
    if (intent.screen == WearScreenId.availabilityFill) {
      next = next.copyWith(
        message: next.message ?? 'Сканируйте товары с полки',
      );
    }

    WearRuntimeState entered = _replaceTask(
      state,
      aggregate.copyWith(
        navigation: aggregate.navigation.request(intent.screen),
      ),
      features,
      next,
    );
    entered = entered.withLegacy(
      WearLegacyRuntimeSnapshot(
        logicalScreen: intent.screen,
        sourceRevision: state.legacy.sourceRevision + 1,
      ),
    );

    if (intent.screen == WearScreenId.availabilityGroup &&
        next.flow.groups.isEmpty) {
      return _startEffectFromState(
        entered,
        operation: WearAvailabilityOperation.start,
      );
    }
    if (intent.screen == WearScreenId.availabilityProduct &&
        intent.extra is WearAvailabilityGroup) {
      final WearAvailabilityGroup group =
          intent.extra as WearAvailabilityGroup;
      if (next.flow.selectedGroup?.id != group.id ||
          next.flow.products.isEmpty) {
        return _startEffectFromState(
          entered,
          operation: WearAvailabilityOperation.selectGroup,
          group: group,
        );
      }
    }
    if (intent.screen == WearScreenId.availabilityCheck &&
        intent.extra is WearAvailabilityProduct &&
        next.flow.selectedProduct?.id !=
            (intent.extra as WearAvailabilityProduct).id) {
      return _startEffectFromState(
        entered,
        operation: WearAvailabilityOperation.selectProduct,
        product: intent.extra as WearAvailabilityProduct,
      );
    }
    return WearReduction.accept(nextState: entered);
  }

  WearReduction _focus(
    WearRuntimeState state,
    WearAggregatePayload aggregate,
    WearRuntimeFeaturePayload features,
    WearAvailabilityTaskSlice task,
    int index,
  ) {
    if (task.isBusy || task.listValues.isEmpty) {
      return WearReduction.reject(
        task.isBusy
            ? WearDispatchRejectReason.busy
            : WearDispatchRejectReason.unsupported,
      );
    }
    final int next = index.clamp(0, task.listValues.length - 1);
    if (next == task.focusedIndex) return WearReduction.accept();
    return WearReduction.accept(
      nextState: _replaceTask(
        state,
        aggregate,
        features,
        task.copyWith(focusedIndex: next),
      ),
    );
  }

  WearReduction _selectItem(
    WearRuntimeState state,
    WearAggregatePayload aggregate,
    WearRuntimeFeaturePayload features,
    WearAvailabilityTaskSlice task,
    String itemId,
  ) {
    if (task.isBusy) return WearReduction.reject(WearDispatchRejectReason.busy);
    Object? selected;
    for (final Object value in task.listValues) {
      final String id = switch (value) {
        WearAvailabilityGroup group => group.id.toString(),
        WearAvailabilityProduct product => product.id.toString(),
        _ => '',
      };
      if (id == itemId) {
        selected = value;
        break;
      }
    }
    if (selected is WearAvailabilityGroup) {
      return _startEffect(
        state,
        aggregate,
        features,
        task,
        operation: WearAvailabilityOperation.selectGroup,
        group: selected,
      );
    }
    if (selected is WearAvailabilityProduct) {
      return _startEffect(
        state,
        aggregate,
        features,
        task,
        operation: task.isDuplicateSelection
            ? WearAvailabilityOperation.selectScannedProduct
            : WearAvailabilityOperation.selectProduct,
        product: selected,
        barcode: task.flow.lastBarcode,
      );
    }
    return WearReduction.reject(WearDispatchRejectReason.unsupported);
  }

  WearReduction _barcode(
    WearRuntimeState state,
    WearAggregatePayload aggregate,
    WearRuntimeFeaturePayload features,
    WearAvailabilityTaskSlice task,
    String raw,
  ) {
    final String barcode = raw.trim();
    if (barcode.isEmpty) {
      return WearReduction.reject(WearDispatchRejectReason.unsupported);
    }
    if (!task.acceptsBarcode(aggregate.navigation.logicalScreen)) {
      return WearReduction.reject(
        task.isBusy
            ? WearDispatchRejectReason.busy
            : WearDispatchRejectReason.unsupported,
      );
    }
    if (task.lastAcceptedBarcode == barcode &&
        task.lastAcceptedStep == task.flow.step) {
      return WearReduction.reject(WearDispatchRejectReason.duplicate);
    }
    final WearAvailabilityTaskSlice accepted = task.copyWith(
      lastAcceptedBarcode: barcode,
      lastAcceptedStep: task.flow.step,
    );
    final WearRuntimeState acceptedState =
        _replaceTask(state, aggregate, features, accepted);
    if (task.screen == WearScreenId.availabilityFill) {
      return _startEffectFromState(
        acceptedState,
        operation: WearAvailabilityOperation.fillAdd,
        barcode: barcode,
      );
    }
    if (task.screen == WearScreenId.availabilityDirectScan) {
      return _startEffectFromState(
        acceptedState,
        operation: WearAvailabilityOperation.findBarcode,
        barcode: barcode,
      );
    }
    if (task.flow.step == WearAvailabilityFlowStep.productScan) {
      return _startEffectFromState(
        acceptedState,
        operation: WearAvailabilityOperation.scanProduct,
        barcode: barcode,
      );
    }
    if (task.flow.step == WearAvailabilityFlowStep.priceTagScan) {
      return _startEffectFromState(
        acceptedState,
        operation: WearAvailabilityOperation.scanPriceTag,
        barcode: barcode,
      );
    }
    return WearReduction.reject(WearDispatchRejectReason.unsupported);
  }

  WearReduction _startEffect(
    WearRuntimeState state,
    WearAggregatePayload aggregate,
    WearRuntimeFeaturePayload features,
    WearAvailabilityTaskSlice task, {
    required WearAvailabilityOperation operation,
    WearAvailabilityGroup? group,
    WearAvailabilityProduct? product,
    String? barcode,
    bool? available,
  }) {
    return _startEffectFromState(
      _replaceTask(state, aggregate, features, task),
      operation: operation,
      group: group,
      product: product,
      barcode: barcode,
      available: available,
    );
  }

  WearReduction _startEffectFromState(
    WearRuntimeState state, {
    required WearAvailabilityOperation operation,
    WearAvailabilityGroup? group,
    WearAvailabilityProduct? product,
    String? barcode,
    bool? available,
  }) {
    final WearAggregatePayload aggregate =
        state.payloadAs<WearAggregatePayload>();
    final WearRuntimeFeaturePayload features =
        aggregate.features as WearRuntimeFeaturePayload;
    final WearAvailabilityTaskSlice task =
        features.availability as WearAvailabilityTaskSlice;
    if (task.isBusy) return WearReduction.reject(WearDispatchRejectReason.busy);
    final allocation = task.allocateOperation();
    final WearAvailabilityTaskSlice busy = allocation.task.copyWith(
      phase: WearAvailabilityTaskPhase.busy,
      clearError: true,
    );
    final WearRuntimeState next = _replaceTask(
      state,
      aggregate,
      features,
      busy,
    ).expectOperation(
      kind: operation.operationKind,
      operationId: allocation.operationId,
    );
    return WearReduction.accept(
      nextState: next,
      effects: <WearEffect>[
        WearAvailabilityOperationEffect(
          sessionEpoch: state.sessionEpoch,
          operationId: allocation.operationId,
          operation: operation,
          flow: busy.flow,
          group: group,
          product: product,
          barcode: barcode,
          available: available,
        ),
      ],
    );
  }

  WearReduction _startNavigation(
    WearRuntimeState state,
    WearAggregatePayload aggregate,
    WearRuntimeFeaturePayload features,
    WearAvailabilityTaskSlice task, {
    required WearScreenId target,
    Object? extra,
    bool replaceCurrent = false,
  }) {
    if (task.isBusy) return WearReduction.reject(WearDispatchRejectReason.busy);
    final allocation = task.allocateOperation();
    final WearAvailabilityTaskSlice busy = allocation.task.copyWith(
      phase: WearAvailabilityTaskPhase.busy,
      screen: target,
      clearError: true,
      clearBarcodeDedupe: target != task.screen,
    );
    final WearAggregatePayload nextAggregate = aggregate.copyWith(
      navigation: aggregate.navigation.request(
        target,
        kind: replaceCurrent
            ? WearPendingNavigationKind.replace
            : WearPendingNavigationKind.push,
      ),
    );
    final WearRuntimeState next = _replaceTask(
      state,
      nextAggregate,
      features,
      busy,
    ).withLegacy(
      WearLegacyRuntimeSnapshot(
        logicalScreen: target,
        sourceRevision: state.legacy.sourceRevision + 1,
      ),
    ).expectOperation(
      kind: WearAvailabilityOperation.navigate.operationKind,
      operationId: allocation.operationId,
    );
    return WearReduction.accept(
      nextState: next,
      effects: <WearEffect>[
        WearAvailabilityOperationEffect(
          sessionEpoch: state.sessionEpoch,
          operationId: allocation.operationId,
          operation: WearAvailabilityOperation.navigate,
          flow: busy.flow,
          targetScreen: target,
          navigationExtra: extra,
          replaceCurrent: replaceCurrent,
        ),
      ],
    );
  }

  WearReduction _success(
    WearRuntimeState state,
    WearAggregatePayload aggregate,
    WearRuntimeFeaturePayload features,
    WearAvailabilityTaskSlice task,
    WearAvailabilityOperationSucceeded intent,
  ) {
    final String kind = intent.operation.operationKind;
    if (intent.sessionEpoch != state.sessionEpoch) {
      return WearReduction.reject(WearDispatchRejectReason.staleEpoch);
    }
    if (state.expectedOperationId(kind) != intent.operationId ||
        !task.isBusy) {
      return WearReduction.reject(WearDispatchRejectReason.staleOperation);
    }
    WearRuntimeState cleared = state.clearExpectedOperation(kind);
    WearAvailabilityTaskSlice next = task.copyWith(
      phase: WearAvailabilityTaskPhase.ready,
      flow: intent.flow,
      message: intent.message,
      clearError: true,
    );

    if (intent.operation == WearAvailabilityOperation.fillAdd) {
      next = next.copyWith(
        savedCount: task.savedCount + intent.addedCount,
        message: intent.message ?? 'Добавлено позиций: ${intent.addedCount}',
      );
    } else if (intent.operation == WearAvailabilityOperation.fillReset) {
      next = next.copyWith(
        savedCount: 0,
        message: intent.message ?? 'База сканированной полки очищена',
        clearBarcodeDedupe: true,
      );
    }

    cleared = _replaceTask(cleared, aggregate, features, next);
    switch (intent.operation) {
      case WearAvailabilityOperation.selectGroup:
        return _startNavigationFromState(
          cleared,
          target: WearScreenId.availabilityProduct,
          extra: intent.flow.selectedGroup,
        );
      case WearAvailabilityOperation.selectProduct:
      case WearAvailabilityOperation.selectScannedProduct:
        return _startNavigationFromState(
          cleared,
          target: WearScreenId.availabilityCheck,
          extra: intent.flow,
        );
      case WearAvailabilityOperation.findBarcode:
        if (intent.flow.step == WearAvailabilityFlowStep.productQuestion &&
            intent.flow.selectedProduct != null) {
          return _startNavigationFromState(
            cleared,
            target: WearScreenId.availabilityCheck,
            extra: intent.flow,
          );
        }
        return WearReduction.accept(nextState: cleared);
      case WearAvailabilityOperation.complete:
        return _startNavigationFromState(
          cleared,
          target: WearScreenId.availabilityGroup,
          replaceCurrent: true,
        );
      default:
        return WearReduction.accept(nextState: cleared);
    }
  }

  WearReduction _startNavigationFromState(
    WearRuntimeState state, {
    required WearScreenId target,
    Object? extra,
    bool replaceCurrent = false,
  }) {
    final WearAggregatePayload aggregate =
        state.payloadAs<WearAggregatePayload>();
    final WearRuntimeFeaturePayload features =
        aggregate.features as WearRuntimeFeaturePayload;
    final WearAvailabilityTaskSlice task =
        features.availability as WearAvailabilityTaskSlice;
    return _startNavigation(
      state,
      aggregate,
      features,
      task,
      target: target,
      extra: extra,
      replaceCurrent: replaceCurrent,
    );
  }

  WearReduction _failure(
    WearRuntimeState state,
    WearAggregatePayload aggregate,
    WearRuntimeFeaturePayload features,
    WearAvailabilityTaskSlice task,
    WearAvailabilityOperationFailed intent,
  ) {
    final String kind = intent.operation.operationKind;
    if (intent.sessionEpoch != state.sessionEpoch) {
      return WearReduction.reject(WearDispatchRejectReason.staleEpoch);
    }
    if (state.expectedOperationId(kind) != intent.operationId ||
        !task.isBusy) {
      return WearReduction.reject(WearDispatchRejectReason.staleOperation);
    }
    final WearAvailabilityTaskSlice failed = task.copyWith(
      phase: WearAvailabilityTaskPhase.error,
      error: intent.message,
      message: intent.message,
      clearBarcodeDedupe:
          intent.operation == WearAvailabilityOperation.fillAdd ||
              intent.operation == WearAvailabilityOperation.findBarcode,
    );
    return WearReduction.accept(
      nextState: _replaceTask(
        state.clearExpectedOperation(kind),
        aggregate,
        features,
        failed,
      ),
    );
  }

  WearRuntimeState _replaceTask(
    WearRuntimeState state,
    WearAggregatePayload aggregate,
    WearRuntimeFeaturePayload features,
    WearAvailabilityTaskSlice task,
  ) {
    return state.withPayload(
      aggregate.copyWith(
        features: features.copyWith(availability: task),
      ),
    );
  }
}

extension WearRuntimeStateOperationPrefix on WearRuntimeState {
  WearRuntimeState clearExpectedOperationPrefix(String prefix) {
    WearRuntimeState next = this;
    for (final String kind in expectedOperationIds.keys.toList()) {
      if (kind.startsWith(prefix)) next = next.clearExpectedOperation(kind);
    }
    return next;
  }
}
