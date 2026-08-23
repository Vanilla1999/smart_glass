import 'package:smart_glasses/modules/wear/domain/price_tag_print/model/barcode_product_info.dart';

class WearProductSelectArgs {
  const WearProductSelectArgs({
    required this.barcode,
    required this.products,
  });

  final String barcode;
  final List<BarcodeProductInfo> products;
}
