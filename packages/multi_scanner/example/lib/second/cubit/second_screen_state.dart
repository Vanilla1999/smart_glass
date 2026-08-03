import 'package:freezed_annotation/freezed_annotation.dart';

part 'second_screen_state.freezed.dart';
@freezed
class SecondScreenState with _$SecondScreenState{
  const factory SecondScreenState.loading() = _Loading;
  const factory SecondScreenState.suc() = _Suc;
  const factory SecondScreenState.onScan({required String barcode}) = _onScan;
}