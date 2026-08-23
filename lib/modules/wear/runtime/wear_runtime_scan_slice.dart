import 'dart:collection';

import 'package:smart_glasses/modules/wear/application/wear_product_select_args.dart';
import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/domain/price_tag_print/model/barcode_product_info.dart';
import 'package:smart_glasses/modules/wear/models/wear_printer_selection.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/status/wear_status_args.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_core_slices.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_printer_slice.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_store.dart';

enum WearScanTaskPhase {
  waiting,
  lookingUp,
  selecting,
  printing,
  status,
}

class WearScanTaskSlice implements WearScanFeaturePayload {
  WearScanTaskSlice({
    required this.phase,
    required this.screen,
    required this.barcode,
    required Iterable<BarcodeProductInfo> products,
    required this.focusedIndex,
    required this.productName,
    required this.status,
    required this.lastAcceptedBarcode,
    required this.nextOperationId,
  }) : products = UnmodifiableListView<BarcodeProductInfo>(
          List<BarcodeProductInfo>.of(products),
        );

  factory WearScanTaskSlice.initial() {
    return WearScanTaskSlice(
      phase: WearScanTaskPhase.waiting,
      screen: WearScreenId.scanIdle,
      barcode: null,
      products: const <BarcodeProductInfo>[],
      focusedIndex: 0,
      productName: null,
      status: null,
      lastAcceptedBarcode: null,
      nextOperationId: 0,
    );
  }

  final WearScanTaskPhase phase;
  final WearScreenId screen;
  final String? barcode;
  final UnmodifiableListView<BarcodeProductInfo> products;
  final int focusedIndex;
  final String? productName;
  final WearStatusScreenArgs? status;
  final String? lastAcceptedBarcode;
  final int nextOperationId;

  bool get isBusy =>
      phase == WearScanTaskPhase.lookingUp ||
      phase == WearScanTaskPhase.printing;

  WearScanTaskSlice copyWith({
    WearScanTaskPhase? phase,
    WearScreenId? screen,
    String? barcode,
    Iterable<BarcodeProductInfo>? products,
    int? focusedIndex,
    String? productName,
    WearStatusScreenArgs? status,
    String? lastAcceptedBarcode,
    int? nextOperationId,
    bool clearBarcode = false,
    bool clearProducts = false,
    bool clearProductName = false,
    bool clearStatus = false,
    bool clearLastAcceptedBarcode = false,
  }) {
    return WearScanTaskSlice(
      phase: phase ?? this.phase,
      screen: screen ?? this.screen,
      barcode: clearBarcode ? null : barcode ?? this.barcode,
      products: clearProducts
          ? const <BarcodeProductInfo>[]
          : products ?? this.products,
      focusedIndex: focusedIndex ?? this.focusedIndex,
      productName: clearProductName ? null : productName ?? this.productName,
      status: clearStatus ? null : status ?? this.status,
      lastAcceptedBarcode: clearLastAcceptedBarcode
          ? null
          : lastAcceptedBarcode ?? this.lastAcceptedBarcode,
      nextOperationId: nextOperationId ?? this.nextOperationId,
    );
  }

  WearScanTaskSlice reset() =>
      WearScanTaskSlice.initial().copyWith(nextOperationId: nextOperationId);

  ({WearScanTaskSlice task, int operationId}) allocateOperation() {
    final int operationId = nextOperationId + 1;
    return (
      task: copyWith(nextOperationId: operationId),
      operationId: operationId,
    );
  }
}

class WearScanEntered extends WearIntent {
  const WearScanEntered({required this.screen, this.extra});

  final WearScreenId screen;
  final Object? extra;
}

class WearScanBarcodeReceived extends WearIntent {
  const WearScanBarcodeReceived(this.barcode);

  final String barcode;
}

class WearScanFocusChanged extends WearIntent {
  const WearScanFocusChanged(this.index);

  final int index;
}

class WearScanFocusMoved extends WearIntent {
  const WearScanFocusMoved(this.delta);

  final int delta;
}

class WearScanPageMoved extends WearIntent {
  const WearScanPageMoved(this.delta);

  final int delta;
}

class WearScanProductSelected extends WearIntent {
  const WearScanProductSelected(this.productId);

  final int productId;
}

class WearBarcodeLookupSucceeded extends WearIntent {
  const WearBarcodeLookupSucceeded({
    required this.sessionEpoch,
    required this.operationId,
    required this.products,
  });

  final int sessionEpoch;
  final int operationId;
  final List<BarcodeProductInfo> products;
}

class WearBarcodeLookupFailed extends WearIntent {
  const WearBarcodeLookupFailed({
    required this.sessionEpoch,
    required this.operationId,
    required this.message,
  });

  final int sessionEpoch;
  final int operationId;
  final String message;
}

class WearPriceTagPrintSucceeded extends WearIntent {
  const WearPriceTagPrintSucceeded({
    required this.sessionEpoch,
    required this.operationId,
    required this.productName,
  });

  final int sessionEpoch;
  final int operationId;
  final String productName;
}

class WearPriceTagPrintFailed extends WearIntent {
  const WearPriceTagPrintFailed({
    required this.sessionEpoch,
    required this.operationId,
    required this.message,
  });

  final int sessionEpoch;
  final int operationId;
  final String message;
}

class WearScanStatusElapsed extends WearIntent {
  const WearScanStatusElapsed({
    required this.sessionEpoch,
    required this.operationId,
    required this.target,
  });

  final int sessionEpoch;
  final int operationId;
  final WearScreenId target;
}

class WearScanStatusPresentationFailed extends WearIntent {
  const WearScanStatusPresentationFailed({
    required this.sessionEpoch,
    required this.operationId,
    required this.message,
  });

  final int sessionEpoch;
  final int operationId;
  final String message;
}

class WearScanNavigationFailed extends WearIntent {
  const WearScanNavigationFailed({
    required this.sessionEpoch,
    required this.operationId,
    required this.message,
  });

  final int sessionEpoch;
  final int operationId;
  final String message;
}

class WearScanTaskReset extends WearIntent {
  const WearScanTaskReset();
}

class WearLookupBarcodeEffect extends WearEffect {
  const WearLookupBarcodeEffect({
    required super.sessionEpoch,
    required super.operationId,
    required this.barcode,
  }) : super(kind: operationKind);

  static const String operationKind = 'scan.lookup';
  final String barcode;
}

class WearPrintPriceTagEffect extends WearEffect {
  const WearPrintPriceTagEffect({
    required super.sessionEpoch,
    required super.operationId,
    required this.product,
    required this.selection,
  }) : super(kind: operationKind);

  static const String operationKind = 'scan.print';
  final BarcodeProductInfo product;
  final WearPrinterSelection selection;
}

class WearNavigateScanEffect extends WearEffect {
  const WearNavigateScanEffect({
    required super.sessionEpoch,
    required super.operationId,
    required this.screen,
    this.extra,
    this.replaceCurrent = false,
  }) : super(kind: operationKind);

  static const String operationKind = 'scan.navigate';
  final WearScreenId screen;
  final Object? extra;
  final bool replaceCurrent;
}

class WearPresentScanStatusEffect extends WearEffect {
  const WearPresentScanStatusEffect({
    required super.sessionEpoch,
    required super.operationId,
    required this.args,
  }) : super(kind: operationKind);

  static const String operationKind = 'scan.status.present';
  final WearStatusScreenArgs args;
}

class WearScanStatusDelayEffect extends WearEffect {
  const WearScanStatusDelayEffect({
    required super.sessionEpoch,
    required super.operationId,
    required this.duration,
    required this.target,
  }) : super(kind: operationKind);

  static const String operationKind = 'scan.status.delay';
  final Duration duration;
  final WearScreenId target;
}

class WearScanSliceReducer implements WearSliceReducer {
  const WearScanSliceReducer();

  static const int pageSize = 4;

  @override
  WearReduction? reduceSlice(WearRuntimeState state, WearIntent intent) {
    final WearAggregatePayload aggregate =
        state.payloadAs<WearAggregatePayload>();
    final WearFeaturePayload rawFeatures = aggregate.features;
    if (rawFeatures is! WearRuntimeFeaturePayload) return null;
    final WearScanFeaturePayload rawScan = rawFeatures.scan;
    if (rawScan is! WearScanTaskSlice) return null;
    final WearScanTaskSlice scan = rawScan;

    if (intent is WearScanEntered) {
      if (intent.screen != WearScreenId.scanIdle &&
          intent.screen != WearScreenId.productSelect) {
        return WearReduction.reject(WearDispatchRejectReason.unsupported);
      }
      WearRuntimeState cleared = _clearOperations(state);
      WearScanTaskSlice entered;
      if (intent.screen == WearScreenId.scanIdle) {
        entered = scan.copyWith(
          phase: WearScanTaskPhase.waiting,
          screen: WearScreenId.scanIdle,
          focusedIndex: 0,
          clearBarcode: true,
          clearProducts: true,
          clearProductName: true,
          clearStatus: true,
          clearLastAcceptedBarcode: true,
        );
      } else if (intent.extra is WearProductSelectArgs) {
        final WearProductSelectArgs args =
            intent.extra as WearProductSelectArgs;
        entered = scan.copyWith(
          phase: WearScanTaskPhase.selecting,
          screen: WearScreenId.productSelect,
          barcode: args.barcode,
          products: args.products,
          focusedIndex: 0,
          clearStatus: true,
        );
      } else if (scan.phase == WearScanTaskPhase.selecting &&
          scan.products.isNotEmpty) {
        entered = scan.copyWith(
          screen: WearScreenId.productSelect,
          focusedIndex: scan.focusedIndex.clamp(0, scan.products.length - 1),
        );
      } else {
        return WearReduction.reject(WearDispatchRejectReason.staleScreen);
      }
      return _commitScanWithLogicalScreen(
        cleared,
        aggregate,
        rawFeatures,
        entered,
        intent.screen,
      );
    }

    if (intent is WearScanBarcodeReceived) {
      if (aggregate.navigation.logicalScreen != WearScreenId.scanIdle ||
          scan.phase != WearScanTaskPhase.waiting) {
        return WearReduction.reject(WearDispatchRejectReason.staleScreen);
      }
      final String barcode = intent.barcode.trim();
      if (barcode.isEmpty) {
        return WearReduction.reject(WearDispatchRejectReason.unsupported);
      }
      if (scan.lastAcceptedBarcode == barcode) return WearReduction.accept();
      final WearPrinterSelection? selection = rawFeatures.printer.selection;
      if (selection == null) {
        return _enterStatus(
          state,
          aggregate,
          rawFeatures,
          scan.copyWith(lastAcceptedBarcode: barcode),
          args: const WearStatusScreenArgs(
            kind: WearStatusKind.error,
            title: 'Ошибка печати',
            message: 'Не выбраны принтеры',
            autoAfter: Duration(seconds: 3),
            autoAction: WearStatusAutoAction.none,
          ),
          target: WearScreenId.scanIdle,
        );
      }
      final ({WearScanTaskSlice task, int operationId}) allocation =
          scan.allocateOperation();
      final WearScanTaskSlice lookingUp = allocation.task.copyWith(
        phase: WearScanTaskPhase.lookingUp,
        screen: WearScreenId.scanIdle,
        barcode: barcode,
        lastAcceptedBarcode: barcode,
        focusedIndex: 0,
        clearProducts: true,
        clearProductName: true,
        clearStatus: true,
      );
      final WearRuntimeState nextState = state
          .withPayload(
            aggregate.copyWith(
              features: rawFeatures.copyWith(scan: lookingUp),
            ),
          )
          .expectOperation(
            kind: WearLookupBarcodeEffect.operationKind,
            operationId: allocation.operationId,
          );
      return WearReduction.accept(
        nextState: nextState,
        effects: <WearEffect>[
          WearLookupBarcodeEffect(
            sessionEpoch: state.sessionEpoch,
            operationId: allocation.operationId,
            barcode: barcode,
          ),
        ],
      );
    }

    if (intent is WearBarcodeLookupSucceeded) {
      final WearDispatchRejectReason? rejection = _resultRejection(
        state,
        aggregate,
        expectedKind: WearLookupBarcodeEffect.operationKind,
        sessionEpoch: intent.sessionEpoch,
        operationId: intent.operationId,
        requiredPhase: WearScanTaskPhase.lookingUp,
      );
      if (rejection != null) return WearReduction.reject(rejection);
      final WearRuntimeState cleared =
          state.clearExpectedOperation(WearLookupBarcodeEffect.operationKind);
      if (intent.products.isEmpty) {
        return _enterStatus(
          cleared,
          aggregate,
          rawFeatures,
          scan,
          args: const WearStatusScreenArgs(
            kind: WearStatusKind.error,
            title: 'Товар не найден',
            autoAfter: Duration(seconds: 3),
            autoAction: WearStatusAutoAction.none,
          ),
          target: WearScreenId.scanIdle,
        );
      }
      if (intent.products.length == 1) {
        return _startPrint(
          cleared,
          aggregate,
          rawFeatures,
          scan,
          intent.products.single,
        );
      }
      return _enterProductSelection(
        cleared,
        aggregate,
        rawFeatures,
        scan.copyWith(
          phase: WearScanTaskPhase.selecting,
          screen: WearScreenId.productSelect,
          products: intent.products,
          focusedIndex: 0,
        ),
      );
    }

    if (intent is WearBarcodeLookupFailed) {
      final WearDispatchRejectReason? rejection = _resultRejection(
        state,
        aggregate,
        expectedKind: WearLookupBarcodeEffect.operationKind,
        sessionEpoch: intent.sessionEpoch,
        operationId: intent.operationId,
        requiredPhase: WearScanTaskPhase.lookingUp,
      );
      if (rejection != null) return WearReduction.reject(rejection);
      return _enterStatus(
        state.clearExpectedOperation(WearLookupBarcodeEffect.operationKind),
        aggregate,
        rawFeatures,
        scan,
        args: WearStatusScreenArgs(
          kind: WearStatusKind.error,
          title: 'Ошибка сканирования',
          message: intent.message,
          autoAfter: const Duration(seconds: 3),
          autoAction: WearStatusAutoAction.none,
        ),
        target: WearScreenId.scanIdle,
      );
    }

    if (intent is WearScanFocusChanged) {
      if (aggregate.navigation.logicalScreen != WearScreenId.productSelect ||
          scan.phase != WearScanTaskPhase.selecting ||
          scan.products.isEmpty) {
        return WearReduction.reject(WearDispatchRejectReason.staleScreen);
      }
      final int next = intent.index.clamp(0, scan.products.length - 1);
      if (next == scan.focusedIndex) return WearReduction.accept();
      return _commitScan(
        state,
        aggregate,
        rawFeatures,
        scan.copyWith(focusedIndex: next),
      );
    }

    if (intent is WearScanFocusMoved) {
      return reduceSlice(
        state,
        WearScanFocusChanged(scan.focusedIndex + intent.delta),
      );
    }

    if (intent is WearScanPageMoved) {
      return reduceSlice(
        state,
        WearScanFocusChanged(scan.focusedIndex + intent.delta * pageSize),
      );
    }

    if (intent is WearScanProductSelected) {
      if (aggregate.navigation.logicalScreen != WearScreenId.productSelect ||
          scan.phase != WearScanTaskPhase.selecting) {
        return WearReduction.reject(WearDispatchRejectReason.staleScreen);
      }
      BarcodeProductInfo? product;
      for (final BarcodeProductInfo item in scan.products) {
        if (item.id == intent.productId) {
          product = item;
          break;
        }
      }
      if (product == null) {
        return WearReduction.reject(WearDispatchRejectReason.unsupported);
      }
      return _startPrint(state, aggregate, rawFeatures, scan, product);
    }

    if (intent is WearPriceTagPrintSucceeded) {
      final WearDispatchRejectReason? rejection = _resultRejection(
        state,
        aggregate,
        expectedKind: WearPrintPriceTagEffect.operationKind,
        sessionEpoch: intent.sessionEpoch,
        operationId: intent.operationId,
        requiredPhase: WearScanTaskPhase.printing,
      );
      if (rejection != null) return WearReduction.reject(rejection);
      return _enterStatus(
        state.clearExpectedOperation(WearPrintPriceTagEffect.operationKind),
        aggregate,
        rawFeatures,
        scan.copyWith(productName: intent.productName),
        args: WearStatusScreenArgs(
          kind: WearStatusKind.success,
          title: 'Ценник напечатан',
          message: intent.productName,
          autoAfter: const Duration(seconds: 2),
          autoAction: WearStatusAutoAction.none,
        ),
        target: WearScreenId.scanIdle,
      );
    }

    if (intent is WearPriceTagPrintFailed) {
      final WearDispatchRejectReason? rejection = _resultRejection(
        state,
        aggregate,
        expectedKind: WearPrintPriceTagEffect.operationKind,
        sessionEpoch: intent.sessionEpoch,
        operationId: intent.operationId,
        requiredPhase: WearScanTaskPhase.printing,
      );
      if (rejection != null) return WearReduction.reject(rejection);
      return _enterStatus(
        state.clearExpectedOperation(WearPrintPriceTagEffect.operationKind),
        aggregate,
        rawFeatures,
        scan,
        args: WearStatusScreenArgs(
          kind: WearStatusKind.error,
          title: 'Ошибка печати',
          message: intent.message,
          autoAfter: const Duration(seconds: 3),
          autoAction: WearStatusAutoAction.none,
        ),
        target: WearScreenId.scanIdle,
      );
    }

    if (intent is WearScanStatusElapsed) {
      final WearDispatchRejectReason? rejection = _resultRejection(
        state,
        aggregate,
        expectedKind: WearScanStatusDelayEffect.operationKind,
        sessionEpoch: intent.sessionEpoch,
        operationId: intent.operationId,
        requiredPhase: WearScanTaskPhase.status,
      );
      if (rejection != null) return WearReduction.reject(rejection);
      final WearRuntimeState cleared = state.clearExpectedOperation(
        WearScanStatusDelayEffect.operationKind,
      );
      final WearScanTaskSlice waiting = scan.copyWith(
        phase: WearScanTaskPhase.waiting,
        screen: intent.target,
        focusedIndex: 0,
        clearBarcode: true,
        clearProducts: true,
        clearProductName: true,
        clearStatus: true,
        clearLastAcceptedBarcode: true,
      );
      return _navigate(
        cleared,
        aggregate,
        rawFeatures,
        waiting,
        screen: intent.target,
        replaceCurrent: true,
      );
    }

    if (intent is WearScanStatusPresentationFailed) {
      if (intent.sessionEpoch != state.sessionEpoch) {
        return WearReduction.reject(WearDispatchRejectReason.staleEpoch);
      }
      if (state.expectedOperationId(
            WearPresentScanStatusEffect.operationKind,
          ) !=
          intent.operationId) {
        return WearReduction.reject(WearDispatchRejectReason.staleOperation);
      }
      return _commitScan(
        state.clearExpectedOperation(
          WearPresentScanStatusEffect.operationKind,
        ),
        aggregate,
        rawFeatures,
        scan.copyWith(
          status: WearStatusScreenArgs(
            kind: WearStatusKind.error,
            title: 'Ошибка отображения статуса',
            message: intent.message,
            autoAfter: scan.status?.autoAfter,
            autoAction: WearStatusAutoAction.none,
          ),
        ),
      );
    }

    if (intent is WearScanNavigationFailed) {
      if (intent.sessionEpoch != state.sessionEpoch) {
        return WearReduction.reject(WearDispatchRejectReason.staleEpoch);
      }
      if (state.expectedOperationId(WearNavigateScanEffect.operationKind) !=
          intent.operationId) {
        return WearReduction.reject(WearDispatchRejectReason.staleOperation);
      }
      return _commitScan(
        state.clearExpectedOperation(WearNavigateScanEffect.operationKind),
        aggregate,
        rawFeatures,
        scan.copyWith(
          phase: WearScanTaskPhase.status,
          screen: WearScreenId.status,
          status: WearStatusScreenArgs(
            kind: WearStatusKind.error,
            title: 'Ошибка навигации',
            message: intent.message,
            autoAction: WearStatusAutoAction.none,
          ),
        ),
      );
    }

    if (intent is WearScanTaskReset) {
      return _commitScan(
        _clearOperations(state),
        aggregate,
        rawFeatures,
        scan.reset(),
      );
    }

    return null;
  }

  WearReduction _startPrint(
    WearRuntimeState state,
    WearAggregatePayload aggregate,
    WearRuntimeFeaturePayload features,
    WearScanTaskSlice scan,
    BarcodeProductInfo product,
  ) {
    final WearPrinterSelection? selection = features.printer.selection;
    if (selection == null) {
      return _enterStatus(
        state,
        aggregate,
        features,
        scan,
        args: const WearStatusScreenArgs(
          kind: WearStatusKind.error,
          title: 'Ошибка печати',
          message: 'Не выбраны принтеры',
          autoAfter: Duration(seconds: 3),
          autoAction: WearStatusAutoAction.none,
        ),
        target: WearScreenId.scanIdle,
      );
    }
    final ({WearScanTaskSlice task, int operationId}) allocation =
        scan.allocateOperation();
    final WearScanTaskSlice printing = allocation.task.copyWith(
      phase: WearScanTaskPhase.printing,
      productName: product.name,
      clearStatus: true,
    );
    final WearRuntimeState nextState = state
        .withPayload(
          aggregate.copyWith(
            features: features.copyWith(scan: printing),
          ),
        )
        .expectOperation(
          kind: WearPrintPriceTagEffect.operationKind,
          operationId: allocation.operationId,
        );
    return WearReduction.accept(
      nextState: nextState,
      effects: <WearEffect>[
        WearPrintPriceTagEffect(
          sessionEpoch: state.sessionEpoch,
          operationId: allocation.operationId,
          product: product,
          selection: selection,
        ),
      ],
    );
  }

  WearReduction _enterProductSelection(
    WearRuntimeState state,
    WearAggregatePayload aggregate,
    WearRuntimeFeaturePayload features,
    WearScanTaskSlice scan,
  ) {
    final WearProductSelectArgs args = WearProductSelectArgs(
      barcode: scan.barcode ?? '',
      products: scan.products,
    );
    return _navigate(
      state,
      aggregate,
      features,
      scan,
      screen: WearScreenId.productSelect,
      extra: args,
    );
  }

  WearReduction _enterStatus(
    WearRuntimeState state,
    WearAggregatePayload aggregate,
    WearRuntimeFeaturePayload features,
    WearScanTaskSlice scan, {
    required WearStatusScreenArgs args,
    required WearScreenId target,
  }) {
    final ({WearScanTaskSlice task, int operationId}) presentAllocation =
        scan.allocateOperation();
    final ({WearScanTaskSlice task, int operationId}) delayAllocation =
        presentAllocation.task.allocateOperation();
    final WearScanTaskSlice statusTask = delayAllocation.task.copyWith(
      phase: WearScanTaskPhase.status,
      screen: WearScreenId.status,
      status: args,
    );
    final WearNavigationSlice navigation = aggregate.navigation.request(
      WearScreenId.status,
    );
    final WearAggregatePayload nextAggregate = aggregate.copyWith(
      navigation: navigation,
      features: features.copyWith(scan: statusTask),
    );
    final WearRuntimeState nextState = state
        .withLegacy(
          WearLegacyRuntimeSnapshot(
            logicalScreen: WearScreenId.status,
            sourceRevision: state.legacy.sourceRevision + 1,
          ),
        )
        .withPayload(nextAggregate)
        .expectOperation(
          kind: WearPresentScanStatusEffect.operationKind,
          operationId: presentAllocation.operationId,
        )
        .expectOperation(
          kind: WearScanStatusDelayEffect.operationKind,
          operationId: delayAllocation.operationId,
        );
    return WearReduction.accept(
      nextState: nextState,
      effects: <WearEffect>[
        WearPresentScanStatusEffect(
          sessionEpoch: state.sessionEpoch,
          operationId: presentAllocation.operationId,
          args: args,
        ),
        WearScanStatusDelayEffect(
          sessionEpoch: state.sessionEpoch,
          operationId: delayAllocation.operationId,
          duration: args.autoAfter ?? const Duration(seconds: 3),
          target: target,
        ),
      ],
    );
  }

  WearReduction _navigate(
    WearRuntimeState state,
    WearAggregatePayload aggregate,
    WearRuntimeFeaturePayload features,
    WearScanTaskSlice scan, {
    required WearScreenId screen,
    Object? extra,
    bool replaceCurrent = false,
  }) {
    final ({WearScanTaskSlice task, int operationId}) allocation =
        scan.allocateOperation();
    final WearNavigationSlice navigation = aggregate.navigation.request(
      screen,
      kind: replaceCurrent
          ? WearPendingNavigationKind.replace
          : WearPendingNavigationKind.push,
    );
    final WearAggregatePayload nextAggregate = aggregate.copyWith(
      navigation: navigation,
      features: features.copyWith(
        scan: allocation.task.copyWith(screen: screen),
      ),
    );
    final WearRuntimeState nextState = state
        .withLegacy(
          WearLegacyRuntimeSnapshot(
            logicalScreen: screen,
            sourceRevision: state.legacy.sourceRevision + 1,
          ),
        )
        .withPayload(nextAggregate)
        .expectOperation(
          kind: WearNavigateScanEffect.operationKind,
          operationId: allocation.operationId,
        );
    return WearReduction.accept(
      nextState: nextState,
      effects: <WearEffect>[
        WearNavigateScanEffect(
          sessionEpoch: state.sessionEpoch,
          operationId: allocation.operationId,
          screen: screen,
          extra: extra,
          replaceCurrent: replaceCurrent,
        ),
      ],
    );
  }

  WearReduction _commitScanWithLogicalScreen(
    WearRuntimeState state,
    WearAggregatePayload aggregate,
    WearRuntimeFeaturePayload features,
    WearScanTaskSlice scan,
    WearScreenId screen,
  ) {
    final WearNavigationSlice navigation =
        aggregate.navigation.logicalScreen == screen
            ? aggregate.navigation
            : aggregate.navigation.request(screen);
    return WearReduction.accept(
      nextState: state
          .withLegacy(
            WearLegacyRuntimeSnapshot(
              logicalScreen: screen,
              sourceRevision: state.legacy.sourceRevision + 1,
            ),
          )
          .withPayload(
            aggregate.copyWith(
              navigation: navigation,
              features: features.copyWith(scan: scan),
            ),
          ),
    );
  }

  WearReduction _commitScan(
    WearRuntimeState state,
    WearAggregatePayload aggregate,
    WearRuntimeFeaturePayload features,
    WearScanTaskSlice scan,
  ) {
    return WearReduction.accept(
      nextState: state.withPayload(
        aggregate.copyWith(features: features.copyWith(scan: scan)),
      ),
    );
  }

  WearDispatchRejectReason? _resultRejection(
    WearRuntimeState state,
    WearAggregatePayload aggregate, {
    required String expectedKind,
    required int sessionEpoch,
    required int operationId,
    required WearScanTaskPhase requiredPhase,
  }) {
    if (sessionEpoch != state.sessionEpoch) {
      return WearDispatchRejectReason.staleEpoch;
    }
    final WearFeaturePayload features = aggregate.features;
    if (features is! WearRuntimeFeaturePayload ||
        features.scan is! WearScanTaskSlice) {
      return WearDispatchRejectReason.unsupported;
    }
    final WearScanTaskSlice scan = features.scan as WearScanTaskSlice;
    if (scan.phase != requiredPhase ||
        state.expectedOperationId(expectedKind) != operationId) {
      return WearDispatchRejectReason.staleOperation;
    }
    return null;
  }

  WearRuntimeState _clearOperations(WearRuntimeState state) {
    return state
        .clearExpectedOperation(WearLookupBarcodeEffect.operationKind)
        .clearExpectedOperation(WearPrintPriceTagEffect.operationKind)
        .clearExpectedOperation(WearNavigateScanEffect.operationKind)
        .clearExpectedOperation(WearPresentScanStatusEffect.operationKind)
        .clearExpectedOperation(WearScanStatusDelayEffect.operationKind);
  }
}
