import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:smart_glasses/modules/wear/data/bdto/model/enum/price_tag_action_flag.dart';

part 'print_add_art_result.freezed.dart';

@freezed
class PrintAddArtResult with _$PrintAddArtResult {
  factory PrintAddArtResult({
    /// (`MES`) Сообщение для отображения в интерфейсе.
    required String message,

    /// (`RESCODE`) Код результата.
    required int resultCode,

    /// (`PRINTQUANT`) Количество печатаемых ценников.
    required int printQuantity,

    /// (`ISACTION`) Признак акционности.
    required PriceTagActionFlag actionFlag,

    /// (`R_IDSHTASK`) Идентификатор задания печати.
    required int taskId,
  }) = _PrintAddArtResult;
}
