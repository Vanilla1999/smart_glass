import 'package:freezed_annotation/freezed_annotation.dart';

part 'price_tag_type.freezed.dart';

@freezed
class PriceTagType with _$PriceTagType {
  factory PriceTagType({
    /// (`RID_REPORT`) Идентификатор отчета.
    required int reportId,

    /// (`RCAPTION`) Человекочитаемое наименование формата.
    required String caption,

    /// (`RSCHEME`) Код формата.
    required String scheme,

    /// (`RSORTER`) Поле сортировки.
    required int sortOrder,
  }) = _PriceTagType;
}
