import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:multi_scanner/multi_scanner.dart';
import 'package:smart_glasses/modules/wear/config/wear_dependencies.dart';
import 'package:smart_glasses/modules/wear/config/wear_mock_config.dart';
import 'package:smart_glasses/modules/wear/config/wear_session.dart';
import 'package:smart_glasses/modules/wear/domain/availability/model/wear_availability_flow_state.dart';
import 'package:smart_glasses/modules/wear/domain/availability/model/wear_availability_product.dart';
import 'package:smart_glasses/modules/wear/domain/availability/use_case/wear_availability_flow_use_case.dart';
import 'package:smart_glasses/modules/wear/domain/auth/model/authenticated_user.dart';
import 'package:smart_glasses/modules/wear/domain/price_tag_print/use_case/print_price_tag_use_case.dart';
import 'package:smart_glasses/modules/wear/models/wear_printer_selection.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/status/wear_status_args.dart';
import 'package:smart_glasses/modules/wear/presentation/utils/wear_feedback.dart';
import 'package:smart_glasses/modules/wear/theme/wear_images.dart';

final AutoDisposeStateNotifierProviderFamily<
        WearAvailabilityCheckNotifier,
        WearAvailabilityCheckState,
        WearAvailabilityProduct> wearAvailabilityCheckNotifierProvider =
    StateNotifierProvider.autoDispose.family<WearAvailabilityCheckNotifier,
        WearAvailabilityCheckState, WearAvailabilityProduct>(
  (
    Ref ref,
    WearAvailabilityProduct product,
  ) =>
      WearAvailabilityCheckNotifier(product),
);

enum WearAvailabilityCheckPhase { idle, loading }

enum WearAvailabilityPhotoPhase { ready, taking, saving }

class WearAvailabilityCheckState {
  const WearAvailabilityCheckState({
    required this.phase,
    required this.flow,
    required this.navStatus,
    required this.loadingText,
    required this.loadingIcon,
    required this.photoPhase,
  });

  factory WearAvailabilityCheckState.initial(
    WearAvailabilityProduct product,
  ) {
    final WearAvailabilityFlowUseCase flowUseCase =
        WearDependencies.I.availabilityFlowUseCase;
    return WearAvailabilityCheckState(
      phase: WearAvailabilityCheckPhase.idle,
      flow: flowUseCase.selectProduct(
        state: const WearAvailabilityFlowState(
          step: WearAvailabilityFlowStep.productSelection,
        ),
        product: product,
      ),
      navStatus: null,
      loadingText: 'Обрабатываем...',
      loadingIcon: WearImages.barcode,
      photoPhase: WearAvailabilityPhotoPhase.ready,
    );
  }

  final WearAvailabilityCheckPhase phase;
  final WearAvailabilityFlowState flow;
  final WearStatusScreenArgs? navStatus;
  final String loadingText;
  final String loadingIcon;
  final WearAvailabilityPhotoPhase photoPhase;

  bool get isLoading => phase == WearAvailabilityCheckPhase.loading;

  WearAvailabilityCheckState copyWith({
    WearAvailabilityCheckPhase? phase,
    WearAvailabilityFlowState? flow,
    WearStatusScreenArgs? navStatus,
    String? loadingText,
    String? loadingIcon,
    WearAvailabilityPhotoPhase? photoPhase,
    bool clearNav = false,
  }) {
    return WearAvailabilityCheckState(
      phase: phase ?? this.phase,
      flow: flow ?? this.flow,
      navStatus: clearNav ? null : navStatus ?? this.navStatus,
      loadingText: loadingText ?? this.loadingText,
      loadingIcon: loadingIcon ?? this.loadingIcon,
      photoPhase: photoPhase ?? this.photoPhase,
    );
  }
}

class WearAvailabilityCheckNotifier
    extends StateNotifier<WearAvailabilityCheckState>
    implements MultiScannerDelegate {
  WearAvailabilityCheckNotifier(WearAvailabilityProduct product)
      : _flowUseCase = WearDependencies.I.availabilityFlowUseCase,
        super(WearAvailabilityCheckState.initial(product)) {
    _scanner.addDelegate(this);
  }

  final WearAvailabilityFlowUseCase _flowUseCase;
  final MultiScanner _scanner = MultiScanner.last();
  String? _lastAcceptedBarcode;
  WearAvailabilityFlowStep? _lastAcceptedStep;

  @override
  void dispose() {
    _scanner.removeDelegate(this);
    super.dispose();
  }

  @override
  bool? onScanEvent(String payload) {
    handleBarcode(payload);
    return true;
  }

  @override
  bool? onErrorScan(Exception error) {
    return false;
  }

  void consumeNavigation() {
    state = state.copyWith(clearNav: true);
  }

  void answerProductAvailable(bool available) {
    if (state.isLoading) return;
    final WearAvailabilityFlowState flow = state.flow;
    if (flow.step != WearAvailabilityFlowStep.productQuestion) return;
    final WearAvailabilityFlowState next =
        _flowUseCase.answerProductAvailable(flow, available: available);
    state = state.copyWith(flow: next, clearNav: true);
  }

  void handleBarcode(String barcode) {
    if (state.isLoading) return;
    final String trimmed = barcode.trim();
    if (trimmed.isEmpty) return;

    final WearAvailabilityFlowState flow = state.flow;
    if (_lastAcceptedBarcode == trimmed && _lastAcceptedStep == flow.step) {
      return;
    }
    _lastAcceptedBarcode = trimmed;
    _lastAcceptedStep = flow.step;

    if (flow.step == WearAvailabilityFlowStep.productScan) {
      state = state.copyWith(
        flow: _flowUseCase.scanProductBarcode(
          state: flow,
          barcode: trimmed,
        ),
        clearNav: true,
      );
      return;
    }
    if (flow.step == WearAvailabilityFlowStep.priceTagScan) {
      state = state.copyWith(
        flow: _flowUseCase.scanPriceTagBarcode(
          state: flow,
          barcode: trimmed,
        ),
        clearNav: true,
      );
    }
  }

  Future<void> printPriceTag() async {
    if (state.isLoading) return;
    final WearAvailabilityFlowState flow = state.flow;
    if (flow.step != WearAvailabilityFlowStep.priceTagOutdated) return;

    final WearPrinterSelection? selection = WearSession.printerSelectionOrNull;
    if (selection == null) {
      _emitStatus(
        const WearStatusScreenArgs(
          kind: WearStatusKind.error,
          title: 'Ошибка',
          message: 'Не выбраны принтеры',
          autoAfter: Duration(seconds: 4),
          autoAction: WearStatusAutoAction.none,
        ),
      );
      return;
    }

    final AuthenticatedUser? user = WearSession.userOrNull;
    if (user == null) {
      _emitStatus(
        const WearStatusScreenArgs(
          kind: WearStatusKind.error,
          title: 'Ошибка',
          message: 'Пользователь не авторизован',
          autoAfter: Duration(seconds: 4),
          autoAction: WearStatusAutoAction.none,
        ),
      );
      return;
    }

    state = state.copyWith(
      phase: WearAvailabilityCheckPhase.loading,
      loadingText: 'Отправляем на печать...',
      loadingIcon: WearImages.printer,
      clearNav: true,
    );
    try {
      final String printerName = await _sendPriceTagToPrint(
        flow: flow,
        user: user,
        selection: selection,
      );
      if (!mounted) return;
      await WearFeedback.play(WearStatusKind.success);
      state = state.copyWith(
        phase: WearAvailabilityCheckPhase.idle,
        flow: _flowUseCase.markPriceTagPrinted(
          state: flow,
          printerName: printerName,
        ),
        clearNav: true,
      );
    } catch (error) {
      if (!mounted) return;
      await WearFeedback.play(WearStatusKind.error);
      state = state.copyWith(phase: WearAvailabilityCheckPhase.idle);
      _emitStatus(
        WearStatusScreenArgs(
          kind: WearStatusKind.error,
          title: 'Ошибка печати',
          message: _asUiMessage(error),
          autoAfter: const Duration(seconds: 5),
          autoAction: WearStatusAutoAction.none,
        ),
      );
    }
  }

  Future<String> _sendPriceTagToPrint({
    required WearAvailabilityFlowState flow,
    required AuthenticatedUser user,
    required WearPrinterSelection selection,
  }) async {
    if (WearMockConfig.isEnabled) {
      await Future<void>.delayed(const Duration(milliseconds: 350));
      return selection.whitePrinter.name;
    }

    final WearAvailabilityProduct product = flow.selectedProduct ??
        (throw StateError('Не выбрана ТП для печати ценника'));
    final PrintPriceTagUseCase printUseCase =
        WearDependencies.I.printPriceTagUseCase;
    return printUseCase.call(
      userId: user.idUser,
      employeeId: user.idEmployee,
      articleId: product.id,
      whiteTagsPrinterName: selection.whitePrinter.name,
      yellowTagsPrinterName: selection.yellowPrinter.name,
    );
  }

  Future<void> capturePhoto() async {
    if (state.isLoading) return;
    final WearAvailabilityFlowState flow = state.flow;
    if (flow.step != WearAvailabilityFlowStep.photoCapture) return;
    state = state.copyWith(
      photoPhase: WearAvailabilityPhotoPhase.taking,
      clearNav: true,
    );
    await Future<void>.delayed(const Duration(milliseconds: 450));
    if (!mounted) return;
    state = state.copyWith(photoPhase: WearAvailabilityPhotoPhase.saving);
    await Future<void>.delayed(const Duration(milliseconds: 450));
    if (!mounted) return;
    state = state.copyWith(
      flow: _flowUseCase.capturePhoto(flow),
      photoPhase: WearAvailabilityPhotoPhase.ready,
      clearNav: true,
    );
  }

  Future<void> complete() async {
    if (state.isLoading) return;
    final WearAvailabilityFlowState flow = state.flow;
    if (flow.step != WearAvailabilityFlowStep.readyToComplete &&
        flow.step != WearAvailabilityFlowStep.manualInventoryRequired) {
      return;
    }

    state = state.copyWith(
      phase: WearAvailabilityCheckPhase.loading,
      loadingText: 'Завершаем проверку...',
      loadingIcon: WearImages.good,
      clearNav: true,
    );
    try {
      final WearAvailabilityFlowState next = await _flowUseCase.complete(flow);
      if (!mounted) return;
      await WearFeedback.play(WearStatusKind.success);
      state = state.copyWith(
        phase: WearAvailabilityCheckPhase.idle,
        flow: next,
        clearNav: true,
      );
      _emitStatus(
        WearStatusScreenArgs(
          kind: WearStatusKind.success,
          title: 'Готово',
          message: next.message ?? 'Проверка товара завершена',
          autoAfter: const Duration(seconds: 4),
          autoAction: WearStatusAutoAction.pop,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      await WearFeedback.play(WearStatusKind.error);
      state = state.copyWith(phase: WearAvailabilityCheckPhase.idle);
      _emitStatus(
        WearStatusScreenArgs(
          kind: WearStatusKind.error,
          title: 'Ошибка',
          message: _asUiMessage(error),
          autoAfter: const Duration(seconds: 5),
          autoAction: WearStatusAutoAction.none,
        ),
      );
    }
  }

  void _emitStatus(WearStatusScreenArgs args) {
    state = state.copyWith(navStatus: args);
  }

  String _asUiMessage(Object error) {
    final String raw = error.toString();
    if (raw.startsWith('Exception: ')) {
      return raw.substring('Exception: '.length);
    }
    return raw;
  }
}
