import 'package:freezed_annotation/freezed_annotation.dart';

part 'barcode_product_info.freezed.dart';

@freezed
class BarcodeProductInfo with _$BarcodeProductInfo {
  factory BarcodeProductInfo({
    /// Идентификатор товарной позиции.
    required int id,

    ///  Наименование товара.
    required String name,

    /// Вес из ШК, если применимо.
    double? weight,

    /// Учетный остаток, крч количество.
    double? articleRest,
  }) = _BarcodeProductInfo;
}
