import 'package:freezed_annotation/freezed_annotation.dart';

part 'first_screen_state.freezed.dart';
@freezed
class FirstScreenState with _$FirstScreenState {
  const factory FirstScreenState.loading() = _Loading;
  const factory FirstScreenState.suc() = _Suc;
  const factory FirstScreenState.onScan({required String barcode}) = _onScan;
}