import 'package:freezed_annotation/freezed_annotation.dart';

part 'available_printer.freezed.dart';

@freezed
class AvailablePrinter with _$AvailablePrinter {
  factory AvailablePrinter({
    /// Название принтера, например "p630022mobile_1"
    required String name,

    /// Номер принтера, например "1"
    required String number,
  }) = _AvailablePrinter;
}
