
import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:multi_scanner/multi_scanner.dart';
import 'package:multi_scanner_example/main.dart';
import 'package:multi_scanner_example/third/cubit/third_screen_state.dart';




class ThirdScreenCubit extends Cubit<ThirdScreenState> implements MultiScannerDelegate {
  ThirdScreenCubit() : super(const ThirdScreenState.loading());

  bool isDialogScanOpen = false;

  final StreamController<String> _barcodeStreamController = StreamController.broadcast();
  Stream<String> get barcodeStream => _barcodeStreamController.stream.asBroadcastStream();

  final MultiScanner getAccountUseCase = getIt<MultiScanner>();

  void initScanner(){
    getAccountUseCase.addDelegate(this);
  }

  void openDialogForScan(){
    isDialogScanOpen = true;
  }
  void closeDialogForScan(){
    isDialogScanOpen = false;
  }

  @override
  bool? onScanEvent(String payload) {
    if(isDialogScanOpen){
      _barcodeStreamController.add(payload);
    }else{
      emit(ThirdScreenState.onScan(barcode: payload));
    }
  }

  @override
  bool? onErrorScan(Exception error) {
    // TODO: implement onErrorScan
    throw UnimplementedError();
  }

  @override
  Future<void> close() {
    getAccountUseCase.removeDelegate(this);
    return super.close();
  }

}
