import 'package:freezed_annotation/freezed_annotation.dart';

part 'print_task_get_result.freezed.dart';

@freezed
class PrintGetTaskResult with _$PrintGetTaskResult {
  factory PrintGetTaskResult({
    /// (`ID_SHTASK`) Идентификатор задания печати.
    required int taskId,
  }) = _PrintGetTaskResult;
}
