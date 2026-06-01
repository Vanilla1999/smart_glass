import 'package:freezed_annotation/freezed_annotation.dart';

part 'print_price_tags_result.freezed.dart';

@freezed
class PrintPriceTagsResult with _$PrintPriceTagsResult {
  factory PrintPriceTagsResult({
    /// (`RES_CODE`) Код результата.
    required int resultCode,

    /// (`RES_TEXT`) Текст ошибки, если `RES_CODE = -1`.
    required String message,
  }) = _PrintPriceTagsResult;
}
