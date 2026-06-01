import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:smart_glasses/modules/wear/data/bdto/model/enum/printer_selection_type.dart';

part 'printer_selection_result.freezed.dart';

@freezed
class PrinterSelectionResult with _$PrinterSelectionResult {
  factory PrinterSelectionResult({
    /// (`RES_CODE`) Тип выбора принтера для текущего объекта.
    required PrinterSelectionType selectionType,

    /// (`RES`) Человекочитаемое описание.
    required String message,
  }) = _PrinterSelectionResult;
}
