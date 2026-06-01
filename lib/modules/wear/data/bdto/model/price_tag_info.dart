import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:smart_glasses/modules/wear/data/bdto/model/enum/price_tag_color.dart';

part 'price_tag_info.freezed.dart';

@freezed
class PriceTagInfo with _$PriceTagInfo {
  factory PriceTagInfo({
    /// (`R_COLOR`) Цвет ценника.
    required PriceTagColor color,

    /// (`R_ARTNAME`) Укороченное наименование товара.
    required String name,
  }) = _PriceTagInfo;
}
