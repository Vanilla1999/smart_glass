import 'package:smart_glasses/modules/wear/data/bdto/data_source/bdto_datasource.dart';
import 'package:smart_glasses/modules/wear/data/bdto/model/barcode_info.dart';
import 'package:smart_glasses/modules/wear/data/bdto/model/enum/barcode_mode.dart';
import 'package:smart_glasses/modules/wear/data/bdto/model/price_tag_info.dart';
import 'package:smart_glasses/modules/wear/domain/price_tag_print/model/barcode_product_info.dart';

class GetBarcodeInfoUseCase {
  GetBarcodeInfoUseCase(this._bdtoDataSource);

  final BdtoDataSource _bdtoDataSource;

  /// Возвращает данные по ШК для отображения списка товаров.
  Future<List<BarcodeProductInfo>> call(String barcode) async {
    final List<BarcodeInfo> result = await _bdtoDataSource.getBarcodeInfo(
      barcode: barcode,
      isWeightless: true,
    );
    final List<BarcodeInfo> items = result
        // фильтруем на случай, если отсканировали ШК принтера (ну вдруг!)
        // у него нет ID как раз.
        // А то выведется принтер еще в результатах внезапно.
        .where((BarcodeInfo item) => item.entityId != null)
        .toList();

    final List<BarcodeProductInfo> products = <BarcodeProductInfo>[];
    for (final BarcodeInfo item in items) {
      String name = item.name ?? 'Название не указано';
      // Для ценников название не приходит сразу, нужно сходить в еще
      // одну процедуру, чтобы получить название самого товара.
      if (item.mode == BarcodeType.price) {
        final PriceTagInfo priceTagInfo = await _bdtoDataSource.getPriceTagInfo(
          artId: item.entityId!,
        );
        name = priceTagInfo.name;
      }
      products.add(
        BarcodeProductInfo(
          id: item.entityId!,
          name: name,
          weight: item.weight,
          articleRest: item.articleRest,
        ),
      );
    }
    await _bdtoDataSource.close();
    return products;
  }
}
