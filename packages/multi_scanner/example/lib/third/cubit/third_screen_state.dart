import 'package:freezed_annotation/freezed_annotation.dart';

part 'third_screen_state.freezed.dart';
@freezed
class ThirdScreenState with _$ThirdScreenState{
  const factory ThirdScreenState.loading() = _Loading;
  const factory ThirdScreenState.suc() = _Suc;
  const factory ThirdScreenState.onScan({required String barcode}) = _onScan;
}