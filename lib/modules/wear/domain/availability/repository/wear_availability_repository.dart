import 'package:smart_glasses/modules/wear/domain/availability/model/wear_availability_group.dart';
import 'package:smart_glasses/modules/wear/domain/availability/model/wear_availability_product.dart';

abstract interface class WearAvailabilityRepository {
  Future<List<WearAvailabilityGroup>> getGroups();

  Future<List<WearAvailabilityProduct>> getProductsByGroup(int groupId);

  Future<List<WearAvailabilityProduct>> findProductsByBarcode(String barcode);

  Future<WearAvailabilityProduct> upsertScannedProduct({
    required int articleId,
    required String name,
    required String barcode,
    double? rest,
  });

  Future<void> resetScannedProducts();

  Future<void> completeProduct(int productId);

  Future<void> resetCompletedProducts();
}
