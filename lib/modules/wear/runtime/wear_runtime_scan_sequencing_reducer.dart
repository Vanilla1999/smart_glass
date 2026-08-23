import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/domain/price_tag_print/model/barcode_product_info.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/status/wear_status_args.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_core_slices.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_printer_slice.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_scan_slice.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_store.dart';

class WearScanStatusPresented extends WearIntent {
  const WearScanStatusPresented({
    required this.sessionEpoch,
    required this.operationId,
  });

  final int sessionEpoch;
  final int operationId;
}

class WearScanStatusDelayFailed extends WearIntent {
  const WearScanStatusDelayFailed({
    required this.sessionEpoch,
    required this.operationId,
    required this.message,
  });

  final int sessionEpoch;
  final int operationId;
  final String message;
}

/// Fixes status sequencing without making the phone presenter a state owner.
///
/// Normative order:
///
///   commit status -> present -> typed result -> schedule delay -> return
///
/// The reducer is installed before the legacy-compatible raw scan reducer and
/// intercepts every transition that creates or completes a scan status.
class WearScanStatusSequencingReducer implements WearSliceReducer {
  const WearScanStatusSequencingReducer();

  @override
  WearReduction? reduceSlice(WearRuntimeState state, WearIntent intent) {
    final WearAggregatePayload aggregate =
        state.payloadAs<WearAggregatePayload>();
    final WearFeaturePayload rawFeatures = aggregate.features;
    if (rawFeatures is! WearRuntimeFeaturePayload ||
        rawFeatures.scan is! WearScanTaskSlice) {
      return null;
    }
    final WearRuntimeFeaturePayload features = rawFeatures;
    final WearScanTaskSlice scan = features.scan as WearScanTaskSlice;

    if (intent is WearScanEntered &&
        aggregate.navigation.logicalScreen == intent.screen &&
        scan.screen == intent.screen) {
      // A Flutter widget attaching after a logical transition is observation,
      // not a second business entry. In particular it must not clear an active
      // lookup/print/status operation.
      return WearReduction.accept();
    }

    if (intent is WearScanBarcodeReceived &&
        aggregate.navigation.logicalScreen == WearScreenId.scanIdle &&
        scan.screen == WearScreenId.scanIdle &&
        scan.phase == WearScanTaskPhase.waiting &&
        features.printer.selection == null) {
      final String barcode = intent.barcode.trim();
      if (barcode.isEmpty) {
        return WearReduction.reject(WearDispatchRejectReason.unsupported);
      }
      if (scan.lastAcceptedBarcode == barcode) return WearReduction.accept();
      return _enterStatus(
        state,
        aggregate,
        features,
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

    if (intent is WearBarcodeLookupSucceeded && intent.products.isEmpty) {
      final WearDispatchRejectReason? rejection = _resultRejection(
        state,
        aggregate,
        scan,
        expectedKind: WearLookupBarcodeEffect.operationKind,
        sessionEpoch: intent.sessionEpoch,
        operationId: intent.operationId,
        requiredPhase: WearScanTaskPhase.lookingUp,
        requiredScreen: WearScreenId.scanIdle,
      );
      if (rejection != null) return WearReduction.reject(rejection);
      return _enterStatus(
        state.clearExpectedOperation(WearLookupBarcodeEffect.operationKind),
        aggregate,
        features,
        scan,
        args: const WearStatusScreenArgs(
          kind: WearStatusKind.error,
          title: 'Товар не найден',
          message: 'Товар не найден',
          autoAfter: Duration(seconds: 3),
          autoAction: WearStatusAutoAction.none,
        ),
        target: WearScreenId.scanIdle,
      );
    }

    if (intent is WearBarcodeLookupFailed) {
      final WearDispatchRejectReason? rejection = _resultRejection(
        state,
        aggregate,
        scan,
        expectedKind: WearLookupBarcodeEffect.operationKind,
        sessionEpoch: intent.sessionEpoch,
        operationId: intent.operationId,
        requiredPhase: WearScanTaskPhase.lookingUp,
        requiredScreen: WearScreenId.scanIdle,
      );
      if (rejection != null) return WearReduction.reject(rejection);
      return _enterStatus(
        state.clearExpectedOperation(WearLookupBarcodeEffect.operationKind),
        aggregate,
        features,
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

    if (intent is WearPriceTagPrintSucceeded) {
      final WearDispatchRejectReason? rejection = _resultRejection(
        state,
        aggregate,
        scan,
        expectedKind: WearPrintPriceTagEffect.operationKind,
        sessionEpoch: intent.sessionEpoch,
        operationId: intent.operationId,
        requiredPhase: WearScanTaskPhase.printing,
        requiredScreen: scan.screen,
      );
      if (rejection != null) return WearReduction.reject(rejection);
      final String productName = scan.productName ?? '';
      return _enterStatus(
        state.clearExpectedOperation(WearPrintPriceTagEffect.operationKind),
        aggregate,
        features,
        scan,
        args: WearStatusScreenArgs(
          kind: WearStatusKind.success,
          title: 'Ценник напечатан',
          message: productName,
          details: intent.printerName,
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
        scan,
        expectedKind: WearPrintPriceTagEffect.operationKind,
        sessionEpoch: intent.sessionEpoch,
        operationId: intent.operationId,
        requiredPhase: WearScanTaskPhase.printing,
        requiredScreen: scan.screen,
      );
      if (rejection != null) return WearReduction.reject(rejection);
      return _enterStatus(
        state.clearExpectedOperation(WearPrintPriceTagEffect.operationKind),
        aggregate,
        features,
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

    if (intent is WearScanStatusPresented) {
      final WearDispatchRejectReason? rejection = _statusResultRejection(
        state,
        aggregate,
        scan,
        sessionEpoch: intent.sessionEpoch,
        operationId: intent.operationId,
        expectedKind: WearPresentScanStatusEffect.operationKind,
      );
      if (rejection != null) return WearReduction.reject(rejection);
      return _afterPresentation(
        state.clearExpectedOperation(
          WearPresentScanStatusEffect.operationKind,
        ),
        aggregate,
        features,
        scan,
      );
    }

    if (intent is WearScanStatusPresentationFailed) {
      final WearDispatchRejectReason? rejection = _statusResultRejection(
        state,
        aggregate,
        scan,
        sessionEpoch: intent.sessionEpoch,
        operationId: intent.operationId,
        expectedKind: WearPresentScanStatusEffect.operationKind,
      );
      if (rejection != null) return WearReduction.reject(rejection);
      final WearScreenId target = _statusTarget(scan);
      final WearStatusScreenArgs failed = WearStatusScreenArgs(
        kind: WearStatusKind.error,
        title: 'Ошибка отображения статуса',
        message: intent.message,
        autoAfter: scan.status?.autoAfter,
        autoExtra: target,
        autoAction: WearStatusAutoAction.none,
      );
      return _afterPresentation(
        state.clearExpectedOperation(
          WearPresentScanStatusEffect.operationKind,
        ),
        aggregate,
        features,
        scan.copyWith(status: failed),
      );
    }

    if (intent is WearScanStatusElapsed) {
      final WearDispatchRejectReason? rejection = _statusResultRejection(
        state,
        aggregate,
        scan,
        sessionEpoch: intent.sessionEpoch,
        operationId: intent.operationId,
        expectedKind: WearScanStatusDelayEffect.operationKind,
      );
      if (rejection != null) return WearReduction.reject(rejection);
      final WearScreenId target = _statusTarget(scan);
      if (intent.target != target) {
        return WearReduction.reject(WearDispatchRejectReason.staleOperation);
      }
      return _returnFromStatus(
        state.clearExpectedOperation(WearScanStatusDelayEffect.operationKind),
        aggregate,
        features,
        scan,
        target: target,
      );
    }

    if (intent is WearScanStatusDelayFailed) {
      final WearDispatchRejectReason? rejection = _statusResultRejection(
        state,
        aggregate,
        scan,
        sessionEpoch: intent.sessionEpoch,
        operationId: intent.operationId,
        expectedKind: WearScanStatusDelayEffect.operationKind,
      );
      if (rejection != null) return WearReduction.reject(rejection);
      return _returnFromStatus(
        state.clearExpectedOperation(WearScanStatusDelayEffect.operationKind),
        aggregate,
        features,
        scan,
        target: _statusTarget(scan),
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
      if (aggregate.navigation.logicalScreen != scan.screen) {
        return WearReduction.reject(WearDispatchRejectReason.staleScreen);
      }
      return _enterStatus(
        state.clearExpectedOperation(WearNavigateScanEffect.operationKind),
        aggregate,
        features,
        scan,
        args: WearStatusScreenArgs(
          kind: WearStatusKind.error,
          title: 'Ошибка навигации',
          message: intent.message,
          autoAction: WearStatusAutoAction.none,
        ),
        target: WearScreenId.scanIdle,
      );
    }

    return null;
  }

  WearReduction _enterStatus(
    WearRuntimeState state,
    WearAggregatePayload aggregate,
    WearRuntimeFeaturePayload features,
    WearScanTaskSlice scan, {
    required WearStatusScreenArgs args,
    required WearScreenId target,
  }) {
    final ({WearScanTaskSlice task, int operationId}) allocation =
        scan.allocateOperation();
    final WearStatusScreenArgs storedArgs = WearStatusScreenArgs(
      kind: args.kind,
      title: args.title,
      message: args.message,
      details: args.details,
      autoAfter: args.autoAfter,
      autoRoute: args.autoRoute,
      autoExtra: target,
      autoAction: WearStatusAutoAction.none,
      showHome: args.showHome,
      glassesStatusText: args.glassesStatusText,
      glassesStatusIcon: args.glassesStatusIcon,
      autoStartedAtMillis: args.autoStartedAtMillis,
    );
    final WearScanTaskSlice statusTask = allocation.task.copyWith(
      phase: WearScanTaskPhase.status,
      screen: WearScreenId.status,
      status: storedArgs,
    );
    final WearNavigationSlice navigation =
        aggregate.navigation.logicalScreen == WearScreenId.status
            ? aggregate.navigation
            : aggregate.navigation.request(WearScreenId.status);
    final WearAggregatePayload nextAggregate = aggregate.copyWith(
      navigation: navigation,
      features: features.copyWith(scan: statusTask),
    );
    final WearRuntimeState prepared = state
        .clearExpectedOperation(WearPresentScanStatusEffect.operationKind)
        .clearExpectedOperation(WearScanStatusDelayEffect.operationKind)
        .withLegacy(
          WearLegacyRuntimeSnapshot(
            logicalScreen: WearScreenId.status,
            sourceRevision: state.legacy.sourceRevision + 1,
          ),
        )
        .withPayload(nextAggregate)
        .expectOperation(
          kind: WearPresentScanStatusEffect.operationKind,
          operationId: allocation.operationId,
        );
    return WearReduction.accept(
      nextState: prepared,
      effects: <WearEffect>[
        WearPresentScanStatusEffect(
          sessionEpoch: state.sessionEpoch,
          operationId: allocation.operationId,
          args: storedArgs,
        ),
      ],
    );
  }

  WearReduction _afterPresentation(
    WearRuntimeState state,
    WearAggregatePayload aggregate,
    WearRuntimeFeaturePayload features,
    WearScanTaskSlice scan,
  ) {
    final Duration? duration = scan.status?.autoAfter;
    if (duration == null) {
      return WearReduction.accept(
        nextState: state.withPayload(
          aggregate.copyWith(features: features.copyWith(scan: scan)),
        ),
      );
    }
    final ({WearScanTaskSlice task, int operationId}) allocation =
        scan.allocateOperation();
    final WearRuntimeState next = state
        .withPayload(
          aggregate.copyWith(
            features: features.copyWith(scan: allocation.task),
          ),
        )
        .expectOperation(
          kind: WearScanStatusDelayEffect.operationKind,
          operationId: allocation.operationId,
        );
    return WearReduction.accept(
      nextState: next,
      effects: <WearEffect>[
        WearScanStatusDelayEffect(
          sessionEpoch: state.sessionEpoch,
          operationId: allocation.operationId,
          duration: duration,
          target: _statusTarget(scan),
        ),
      ],
    );
  }

  WearReduction _returnFromStatus(
    WearRuntimeState state,
    WearAggregatePayload aggregate,
    WearRuntimeFeaturePayload features,
    WearScanTaskSlice scan, {
    required WearScreenId target,
  }) {
    final WearScanTaskSlice waiting = scan.copyWith(
      phase: WearScanTaskPhase.waiting,
      screen: target,
      focusedIndex: 0,
      clearBarcode: true,
      clearProducts: true,
      clearProductName: true,
      clearStatus: true,
      clearLastAcceptedBarcode: true,
    );
    final ({WearScanTaskSlice task, int operationId}) allocation =
        waiting.allocateOperation();
    final WearNavigationSlice navigation = aggregate.navigation.request(
      target,
      kind: WearPendingNavigationKind.replace,
    );
    final WearRuntimeState next = state
        .withLegacy(
          WearLegacyRuntimeSnapshot(
            logicalScreen: target,
            sourceRevision: state.legacy.sourceRevision + 1,
          ),
        )
        .withPayload(
          aggregate.copyWith(
            navigation: navigation,
            features: features.copyWith(scan: allocation.task),
          ),
        )
        .expectOperation(
          kind: WearNavigateScanEffect.operationKind,
          operationId: allocation.operationId,
        );
    return WearReduction.accept(
      nextState: next,
      effects: <WearEffect>[
        WearNavigateScanEffect(
          sessionEpoch: state.sessionEpoch,
          operationId: allocation.operationId,
          screen: target,
          replaceCurrent: true,
        ),
      ],
    );
  }

  WearScreenId _statusTarget(WearScanTaskSlice scan) {
    final Object? target = scan.status?.autoExtra;
    return target is WearScreenId ? target : WearScreenId.scanIdle;
  }

  WearDispatchRejectReason? _resultRejection(
    WearRuntimeState state,
    WearAggregatePayload aggregate,
    WearScanTaskSlice scan, {
    required String expectedKind,
    required int sessionEpoch,
    required int operationId,
    required WearScanTaskPhase requiredPhase,
    required WearScreenId requiredScreen,
  }) {
    if (sessionEpoch != state.sessionEpoch) {
      return WearDispatchRejectReason.staleEpoch;
    }
    if (aggregate.navigation.logicalScreen != requiredScreen ||
        scan.screen != requiredScreen) {
      return WearDispatchRejectReason.staleScreen;
    }
    if (scan.phase != requiredPhase ||
        state.expectedOperationId(expectedKind) != operationId) {
      return WearDispatchRejectReason.staleOperation;
    }
    return null;
  }

  WearDispatchRejectReason? _statusResultRejection(
    WearRuntimeState state,
    WearAggregatePayload aggregate,
    WearScanTaskSlice scan, {
    required int sessionEpoch,
    required int operationId,
    required String expectedKind,
  }) {
    return _resultRejection(
      state,
      aggregate,
      scan,
      expectedKind: expectedKind,
      sessionEpoch: sessionEpoch,
      operationId: operationId,
      requiredPhase: WearScanTaskPhase.status,
      requiredScreen: WearScreenId.status,
    );
  }
}
