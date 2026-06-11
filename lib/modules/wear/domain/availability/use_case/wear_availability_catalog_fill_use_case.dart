import 'package:smart_glasses/modules/wear/domain/availability/model/wear_availability_product.dart';
import 'package:smart_glasses/modules/wear/domain/availability/repository/wear_availability_repository.dart';
import 'package:smart_glasses/modules/wear/domain/price_tag_print/model/barcode_product_info.dart';
import 'package:smart_glasses/modules/wear/domain/price_tag_print/use_case/get_barcode_info_use_case.dart';

class WearAvailabilityCatalogFillUseCase {
  const WearAvailabilityCatalogFillUseCase({
    required GetBarcodeInfoUseCase getBarcodeInfoUseCase,
    required WearAvailabilityRepository repository,
  })  : _getBarcodeInfoUseCase = getBarcodeInfoUseCase,
        _repository = repository;

  final GetBarcodeInfoUseCase _getBarcodeInfoUseCase;
  final WearAvailabilityRepository _repository;

  Future<List<WearAvailabilityProduct>> addByBarcode(String barcode) async {
    final String normalizedBarcode = barcode.trim();
    if (normalizedBarcode.isEmpty) {
      throw Exception('Пустой ШК');
    }

    final List<BarcodeProductInfo> products =
        await _getBarcodeInfoUseCase.call(normalizedBarcode);
    if (products.isEmpty) {
      throw Exception('Товар не найден');
    }

    final List<WearAvailabilityProduct> savedProducts =
        <WearAvailabilityProduct>[];
    for (final BarcodeProductInfo product in products) {
      savedProducts.add(
        await _repository.upsertScannedProduct(
          articleId: product.id,
          name: product.name,
          barcode: normalizedBarcode,
          rest: product.articleRest,
        ),
      );
    }
    return savedProducts;
  }

  Future<void> reset() {
    return _repository.resetScannedProducts();
  }
}
