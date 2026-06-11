import 'package:smart_glasses/modules/wear/domain/availability/model/wear_availability_flow_state.dart';
import 'package:smart_glasses/modules/wear/domain/availability/model/wear_availability_group.dart';
import 'package:smart_glasses/modules/wear/domain/availability/model/wear_availability_product.dart';
import 'package:smart_glasses/modules/wear/domain/availability/repository/wear_availability_repository.dart';

class WearAvailabilityFlowUseCase {
  const WearAvailabilityFlowUseCase(this._repository);

  final WearAvailabilityRepository _repository;

  static const String manualInventoryMessage =
      'Скорректируйте остатки заведением инвентаризации';

  Future<WearAvailabilityFlowState> start() async {
    final List<WearAvailabilityGroup> groups = await _repository.getGroups();
    return WearAvailabilityFlowState(
      step: WearAvailabilityFlowStep.groupSelection,
      groups: groups,
    );
  }

  Future<WearAvailabilityFlowState> selectGroup({
    required WearAvailabilityFlowState state,
    required WearAvailabilityGroup group,
  }) async {
    final List<WearAvailabilityProduct> products =
        await _repository.getProductsByGroup(group.id);
    return state.copyWith(
      step: WearAvailabilityFlowStep.productSelection,
      selectedGroup: group,
      products: products,
      duplicateProducts: const <WearAvailabilityProduct>[],
      clearCheck: true,
      clearMessage: true,
      clearLastBarcode: true,
      clearPrintedPrinter: true,
    );
  }

  WearAvailabilityFlowState selectProduct({
    required WearAvailabilityFlowState state,
    required WearAvailabilityProduct product,
  }) {
    return state.copyWith(
      step: WearAvailabilityFlowStep.productQuestion,
      check: WearAvailabilityProductCheck(product: product),
      message: 'Товар есть на полке?',
      duplicateProducts: const <WearAvailabilityProduct>[],
      clearLastBarcode: true,
      clearPrintedPrinter: true,
    );
  }

  Future<WearAvailabilityFlowState> findProductByBarcode(
    WearAvailabilityFlowState state, {
    required String barcode,
  }) async {
    final List<WearAvailabilityProduct> foundProducts =
        await _repository.findProductsByBarcode(barcode);
    if (foundProducts.isEmpty) {
      return state.copyWith(
        step: WearAvailabilityFlowStep.productSelection,
        lastBarcode: barcode,
        message: 'Позиция не найдена',
        duplicateProducts: const <WearAvailabilityProduct>[],
      );
    }
    if (foundProducts.length > 1) {
      return state.copyWith(
        step: WearAvailabilityFlowStep.duplicateSelection,
        duplicateProducts: foundProducts,
        lastBarcode: barcode,
        message: 'Найдено несколько позиций',
      );
    }
    return selectProduct(
      state: state,
      product: foundProducts.single,
    ).copyWith(lastBarcode: barcode);
  }

  WearAvailabilityFlowState answerProductAvailable(
    WearAvailabilityFlowState state, {
    required bool available,
  }) {
    final WearAvailabilityProductCheck check = _requireCheck(state);
    if (!available) {
      return state.copyWith(
        step: WearAvailabilityFlowStep.manualInventoryRequired,
        check: check.copyWith(manualInventoryRequired: true),
        message: manualInventoryMessage,
      );
    }

    if (check.product.unpackaged) {
      return _nextRequiredStep(
        state,
        check.copyWith(productScanned: true),
      );
    }

    return state.copyWith(
      step: WearAvailabilityFlowStep.productScan,
      check: check,
      message: 'Отсканируйте ШК товара',
    );
  }

  WearAvailabilityFlowState scanProductBarcode({
    required WearAvailabilityFlowState state,
    required String barcode,
  }) {
    final WearAvailabilityProductCheck check = _requireCheck(state);
    if (!check.product.matchesProductBarcode(barcode)) {
      return state.copyWith(
        step: WearAvailabilityFlowStep.productScan,
        check: check,
        lastBarcode: barcode,
        message: 'ШК не относится к выбранному товару',
      );
    }
    return _nextRequiredStep(
      state,
      check.copyWith(productScanned: true),
      barcode: barcode,
      message: 'Товар отсканирован',
    );
  }

  WearAvailabilityFlowState scanPriceTagBarcode({
    required WearAvailabilityFlowState state,
    required String barcode,
  }) {
    final WearAvailabilityProductCheck check = _requireCheck(state);
    if (!check.product.matchesPriceTagBarcode(barcode)) {
      return state.copyWith(
        step: WearAvailabilityFlowStep.priceTagScan,
        check: check,
        lastBarcode: barcode,
        message: 'Ценник не относится к выбранному товару',
      );
    }

    final WearAvailabilityProductCheck nextCheck = check.copyWith(
      priceTagScanned: true,
      priceTagOutdated: !check.product.priceTagActual,
    );
    return _nextRequiredStep(
      state,
      nextCheck,
      barcode: barcode,
      message: check.product.priceTagActual
          ? 'Ценник актуален'
          : 'Ценник неактуален',
    );
  }

  WearAvailabilityFlowState markPriceTagPrinted({
    required WearAvailabilityFlowState state,
    required String printerName,
  }) {
    final WearAvailabilityProductCheck check = _requireCheck(state);
    return _nextRequiredStep(
      state,
      check.copyWith(priceTagPrinted: true),
      printedPrinter: printerName,
      message: 'Ценник отправлен на печать',
    );
  }

  WearAvailabilityFlowState capturePhoto(WearAvailabilityFlowState state) {
    final WearAvailabilityProductCheck check = _requireCheck(state);
    return _nextRequiredStep(
      state,
      check.copyWith(photoCaptured: true),
      message: 'Фото сохранено',
    );
  }

  Future<WearAvailabilityFlowState> complete(
    WearAvailabilityFlowState state,
  ) async {
    final WearAvailabilityProductCheck check = _requireCheck(state);
    if (check.manualInventoryRequired) {
      await _repository.completeProduct(check.product.id);
      return state.copyWith(
        step: WearAvailabilityFlowStep.completed,
        check: check,
        message: manualInventoryMessage,
      );
    }
    if (!check.canCompletePositive) {
      return state.copyWith(
        step: WearAvailabilityFlowStep.readyToComplete,
        check: check,
        message: 'Не все обязательные проверки выполнены',
      );
    }
    await _repository.completeProduct(check.product.id);
    return state.copyWith(
      step: WearAvailabilityFlowStep.completed,
      check: check,
      message: 'Проверка товара завершена',
    );
  }

  WearAvailabilityFlowState _nextRequiredStep(
    WearAvailabilityFlowState state,
    WearAvailabilityProductCheck check, {
    String? barcode,
    String? message,
    String? printedPrinter,
  }) {
    final WearAvailabilityProduct product = check.product;
    if (!check.productScanned && !product.unpackaged) {
      return state.copyWith(
        step: WearAvailabilityFlowStep.productScan,
        check: check,
        lastBarcode: barcode,
        printedPrinter: printedPrinter,
        message: message ?? 'Отсканируйте ШК товара',
      );
    }
    if (product.checkPrice && !check.priceTagScanned) {
      return state.copyWith(
        step: WearAvailabilityFlowStep.priceTagScan,
        check: check,
        lastBarcode: barcode,
        printedPrinter: printedPrinter,
        message: message ?? 'Отсканируйте ценник',
      );
    }
    if (check.priceTagOutdated && !check.priceTagPrinted) {
      return state.copyWith(
        step: WearAvailabilityFlowStep.priceTagOutdated,
        check: check,
        lastBarcode: barcode,
        printedPrinter: printedPrinter,
        message: message ?? 'Ценник неактуален',
      );
    }
    if (product.photoControl && !check.photoCaptured) {
      return state.copyWith(
        step: WearAvailabilityFlowStep.photoCapture,
        check: check,
        lastBarcode: barcode,
        printedPrinter: printedPrinter,
        message: message ?? 'Сделайте фото',
      );
    }
    return state.copyWith(
      step: WearAvailabilityFlowStep.readyToComplete,
      check: check,
      lastBarcode: barcode,
      printedPrinter: printedPrinter,
      message: message ?? 'Можно завершить проверку',
    );
  }

  WearAvailabilityProductCheck _requireCheck(WearAvailabilityFlowState state) {
    final WearAvailabilityProductCheck? check = state.check;
    if (check == null) {
      throw StateError('Не выбрана ТП для проверки');
    }
    return check;
  }
}
