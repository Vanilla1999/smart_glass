import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:smart_glasses/modules/wear/data/bdto/model/enum/printer_kind.dart';
import 'package:smart_glasses/modules/wear/data/bdto/model/enum/printer_subkind.dart';

part 'printer_list_item.freezed.dart';

@freezed
class PrinterListItem with _$PrinterListItem {
  factory PrinterListItem({
    /// (`NAME`) Человекочитаемое имя принтера.
    required String name,

    /// (`ALIAS`) Алиас принтера.
    required String alias,

    /// (`KIND`) Тип принтера (A4 или мобильный/термо).
    required PrinterKind kind,

    /// (`SUBKIND`) Подтип принтера.
    required PrinterSubkind subkind,
  }) = _PrinterListItem;
}
