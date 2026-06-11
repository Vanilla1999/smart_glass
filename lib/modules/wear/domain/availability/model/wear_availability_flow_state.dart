import 'package:smart_glasses/modules/wear/domain/availability/model/wear_availability_group.dart';
import 'package:smart_glasses/modules/wear/domain/availability/model/wear_availability_product.dart';

enum WearAvailabilityFlowStep {
  groupSelection,
  productSelection,
  duplicateSelection,
  productQuestion,
  productScan,
  priceTagScan,
  priceTagOutdated,
  photoCapture,
  readyToComplete,
  manualInventoryRequired,
  completed,
}

class WearAvailabilityProductCheck {
  const WearAvailabilityProductCheck({
    required this.product,
    this.productScanned = false,
    this.priceTagScanned = false,
    this.priceTagOutdated = false,
    this.priceTagPrinted = false,
    this.photoCaptured = false,
    this.manualInventoryRequired = false,
  });

  final WearAvailabilityProduct product;
  final bool productScanned;
  final bool priceTagScanned;
  final bool priceTagOutdated;
  final bool priceTagPrinted;
  final bool photoCaptured;
  final bool manualInventoryRequired;

  bool get canCompletePositive {
    final bool productReady = product.unpackaged || productScanned;
    final bool priceReady = !product.checkPrice ||
        priceTagScanned && (!priceTagOutdated || priceTagPrinted);
    final bool photoReady = !product.photoControl || photoCaptured;
    return productReady && priceReady && photoReady;
  }

  WearAvailabilityProductCheck copyWith({
    bool? productScanned,
    bool? priceTagScanned,
    bool? priceTagOutdated,
    bool? priceTagPrinted,
    bool? photoCaptured,
    bool? manualInventoryRequired,
  }) {
    return WearAvailabilityProductCheck(
      product: product,
      productScanned: productScanned ?? this.productScanned,
      priceTagScanned: priceTagScanned ?? this.priceTagScanned,
      priceTagOutdated: priceTagOutdated ?? this.priceTagOutdated,
      priceTagPrinted: priceTagPrinted ?? this.priceTagPrinted,
      photoCaptured: photoCaptured ?? this.photoCaptured,
      manualInventoryRequired:
          manualInventoryRequired ?? this.manualInventoryRequired,
    );
  }
}

class WearAvailabilityFlowState {
  const WearAvailabilityFlowState({
    required this.step,
    this.groups = const <WearAvailabilityGroup>[],
    this.products = const <WearAvailabilityProduct>[],
    this.duplicateProducts = const <WearAvailabilityProduct>[],
    this.selectedGroup,
    this.check,
    this.message,
    this.lastBarcode,
    this.printedPrinter,
  });

  final WearAvailabilityFlowStep step;
  final List<WearAvailabilityGroup> groups;
  final List<WearAvailabilityProduct> products;
  final List<WearAvailabilityProduct> duplicateProducts;
  final WearAvailabilityGroup? selectedGroup;
  final WearAvailabilityProductCheck? check;
  final String? message;
  final String? lastBarcode;
  final String? printedPrinter;

  WearAvailabilityProduct? get selectedProduct => check?.product;

  WearAvailabilityFlowState copyWith({
    WearAvailabilityFlowStep? step,
    List<WearAvailabilityGroup>? groups,
    List<WearAvailabilityProduct>? products,
    List<WearAvailabilityProduct>? duplicateProducts,
    WearAvailabilityGroup? selectedGroup,
    WearAvailabilityProductCheck? check,
    String? message,
    String? lastBarcode,
    String? printedPrinter,
    bool clearSelectedGroup = false,
    bool clearCheck = false,
    bool clearMessage = false,
    bool clearLastBarcode = false,
    bool clearPrintedPrinter = false,
  }) {
    return WearAvailabilityFlowState(
      step: step ?? this.step,
      groups: groups ?? this.groups,
      products: products ?? this.products,
      duplicateProducts: duplicateProducts ?? this.duplicateProducts,
      selectedGroup:
          clearSelectedGroup ? null : selectedGroup ?? this.selectedGroup,
      check: clearCheck ? null : check ?? this.check,
      message: clearMessage ? null : message ?? this.message,
      lastBarcode: clearLastBarcode ? null : lastBarcode ?? this.lastBarcode,
      printedPrinter:
          clearPrintedPrinter ? null : printedPrinter ?? this.printedPrinter,
    );
  }
}
