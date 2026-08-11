import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smart_glasses/modules/wear/config/wear_dependencies.dart';
import 'package:smart_glasses/modules/wear/domain/availability/model/wear_availability_flow_state.dart';
import 'package:smart_glasses/modules/wear/domain/availability/model/wear_availability_product.dart';
import 'package:smart_glasses/modules/wear/domain/availability/use_case/wear_availability_flow_use_case.dart';
import 'package:smart_glasses/modules/wear/theme/wear_images.dart';

final AutoDisposeStateNotifierProvider<WearAvailabilityDirectScanNotifier,
        WearAvailabilityDirectScanState> wearAvailabilityDirectScanProvider =
    StateNotifierProvider.autoDispose<WearAvailabilityDirectScanNotifier,
        WearAvailabilityDirectScanState>(
  (Ref ref) => WearAvailabilityDirectScanNotifier(),
);

enum WearAvailabilityDirectScanPhase { idle, loading }

class WearAvailabilityDirectScanState {
  const WearAvailabilityDirectScanState({
    required this.phase,
    required this.message,
    required this.loadingText,
    required this.loadingIcon,
    this.navFlow,
    this.duplicateProducts = const <WearAvailabilityProduct>[],
  });

  factory WearAvailabilityDirectScanState.initial() {
    return const WearAvailabilityDirectScanState(
      phase: WearAvailabilityDirectScanPhase.idle,
      message: 'Наведите камеру на штрих-код',
      loadingText: 'ШК отсканирован, распознаю...',
      loadingIcon: WearImages.barcode,
    );
  }

  final WearAvailabilityDirectScanPhase phase;
  final String message;
  final String loadingText;
  final String loadingIcon;
  final WearAvailabilityFlowState? navFlow;
  final List<WearAvailabilityProduct> duplicateProducts;

  bool get isLoading => phase == WearAvailabilityDirectScanPhase.loading;

  WearAvailabilityDirectScanState copyWith({
    WearAvailabilityDirectScanPhase? phase,
    String? message,
    String? loadingText,
    String? loadingIcon,
    WearAvailabilityFlowState? navFlow,
    List<WearAvailabilityProduct>? duplicateProducts,
    bool clearNavigation = false,
    bool clearDuplicates = false,
  }) {
    return WearAvailabilityDirectScanState(
      phase: phase ?? this.phase,
      message: message ?? this.message,
      loadingText: loadingText ?? this.loadingText,
      loadingIcon: loadingIcon ?? this.loadingIcon,
      navFlow: clearNavigation ? null : navFlow ?? this.navFlow,
      duplicateProducts: clearDuplicates
          ? const <WearAvailabilityProduct>[]
          : duplicateProducts ?? this.duplicateProducts,
    );
  }
}

class WearAvailabilityDirectScanNotifier
    extends StateNotifier<WearAvailabilityDirectScanState> {
  WearAvailabilityDirectScanNotifier()
      : _flowUseCase = WearDependencies.I.availabilityFlowUseCase,
        super(WearAvailabilityDirectScanState.initial());

  final WearAvailabilityFlowUseCase _flowUseCase;
  String? _lastAcceptedBarcode;

  Future<void> handleBarcode(String barcode) async {
    if (state.isLoading) return;
    final String trimmed = barcode.trim();
    if (trimmed.isEmpty) return;
    if (_lastAcceptedBarcode == trimmed) return;

    _lastAcceptedBarcode = trimmed;
    state = state.copyWith(
      phase: WearAvailabilityDirectScanPhase.loading,
      loadingText: 'ШК отсканирован, распознаю...',
      loadingIcon: WearImages.barcode,
      clearNavigation: true,
      clearDuplicates: true,
    );

    try {
      final WearAvailabilityFlowState flow =
          await _flowUseCase.findProductByBarcode(
        const WearAvailabilityFlowState(
          step: WearAvailabilityFlowStep.productSelection,
        ),
        barcode: trimmed,
      );
      if (!mounted) return;

      final WearAvailabilityProduct? product = flow.selectedProduct;
      if (product != null) {
        state = state.copyWith(
          phase: WearAvailabilityDirectScanPhase.idle,
          message: 'Товар найден',
          navFlow: flow,
          clearDuplicates: true,
        );
        return;
      }

      if (flow.duplicateProducts.isNotEmpty) {
        state = state.copyWith(
          phase: WearAvailabilityDirectScanPhase.idle,
          message: 'Найдено несколько позиций',
          duplicateProducts: flow.duplicateProducts,
          clearNavigation: true,
        );
        return;
      }

      _lastAcceptedBarcode = null;
      state = state.copyWith(
        phase: WearAvailabilityDirectScanPhase.idle,
        message: flow.message ?? 'Позиция не найдена',
        clearNavigation: true,
        clearDuplicates: true,
      );
    } catch (error) {
      if (!mounted) return;
      _lastAcceptedBarcode = null;
      state = state.copyWith(
        phase: WearAvailabilityDirectScanPhase.idle,
        message: _asUiMessage(error),
        clearNavigation: true,
        clearDuplicates: true,
      );
    }
  }

  void consumeNavigation() {
    state = state.copyWith(clearNavigation: true);
  }

  void resetForNextScan() {
    _lastAcceptedBarcode = null;
    state = WearAvailabilityDirectScanState.initial();
  }

  void selectDuplicate(WearAvailabilityProduct product) {
    final String? barcode = _lastAcceptedBarcode;
    if (barcode == null) return;
    state = state.copyWith(
      navFlow: _flowUseCase.selectScannedProduct(
        state: const WearAvailabilityFlowState(
          step: WearAvailabilityFlowStep.productSelection,
        ),
        product: product,
        barcode: barcode,
      ),
    );
  }

  String _asUiMessage(Object error) {
    final String raw = error.toString();
    if (raw.startsWith('Exception: ')) {
      return raw.substring('Exception: '.length);
    }
    return raw;
  }
}
