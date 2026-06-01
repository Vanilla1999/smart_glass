import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:smart_glasses/modules/wear/data/bdto/model/enum/barcode_mode.dart';

part 'barcode_info.freezed.dart';

@freezed
class BarcodeInfo with _$BarcodeInfo {
  factory BarcodeInfo({
    /// (`MODE`) Тип ШК.
    required BarcodeType mode,

    /// (`ID`) Идентификатор товарной позиции при сканировании ШК товара
    /// или ценника. Для принтера всегда `null`.
    int? entityId,

    /// (`MES`) Служебное сообщение. Не содержит значимых данных.
    String? message,

    /// (`NAME`) Имя принтера или наименование товара.
    String? name,

    /// (`WEIGHT`) Для ШК товара - вес из ШК. Если вес не найден (в режиме G) - `null`.
    double? weight,

    /// (`ID_PLARTPRICE`) Для ШК ценника - ID прайслиста. Для остальных - `null`.
    int? priceListId,

    /// (`ID_NOTART`) Для ШК ценника - ID ценника. Для остальных - `null`.
    int? priceTagId,

    /// (`ARTREST`) Учетный остаток для ШК ценника или товара.
    double? articleRest,

    /// (`ARTRESTLOT`) Партионный остаток для ШК ценника или товара.
    double? articleRestLot,
  }) = _BarcodeInfo;
}
