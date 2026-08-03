import 'package:bloc/bloc.dart';
import 'package:multi_scanner/multi_scanner.dart';
import 'package:multi_scanner_example/main.dart';
import 'package:multi_scanner_example/second/cubit/second_screen_state.dart';



class SecondScreenCubit extends Cubit<SecondScreenState> implements MultiScannerDelegate {
  SecondScreenCubit() : super(const SecondScreenState.loading());


  final MultiScanner getAccountUseCase = getIt<MultiScanner>();

  void initScanner(){
    getAccountUseCase.addDelegate(this);
  }

  @override
  bool? onScanEvent(String payload) {
    emit(SecondScreenState.onScan(barcode: payload));
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
