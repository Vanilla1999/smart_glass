import 'package:bloc/bloc.dart';
import 'package:multi_scanner/barcode_settings_config.dart';
import 'package:multi_scanner/multi_scanner.dart';

import 'package:multi_scanner_example/first/cubit/first_screen_state.dart';
import 'package:multi_scanner_example/main.dart';

class FirstScreenCubit extends Cubit<FirstScreenState> implements MultiScannerDelegate {
  FirstScreenCubit() : super(const FirstScreenState.loading());

  final MultiScanner getAccountUseCase = getIt<MultiScanner>();
  final MultiScannerController multiScannerController = MultiScannerController();
  final HoneywellController honeywellController = HoneywellController();
  final BaseController baseScanner = BaseController();
  final MertechController mertechController = MertechController();
  final WakeUpController wakeUpController = WakeUpController();
  final MultiScannerBluetooth multiScannerBluetooth = MultiScannerBluetooth();


  Future<void> initScanner() async{
    getAccountUseCase.addDelegate(this);
    await baseScanner.init();
    MultiScannerBluetooth().init();
    mertechController.goToCOMMode();
    baseScanner.setRecomendedSettings();
    wakeUpController.wakeUpOnScanButton();

   print(await BaseController().isPCH());
    print(await BaseController().isDefaultHorizontal());
    print(await BaseController().isNotNeedCamera());
    print(await BaseController().isNeedBT());
    multiScannerBluetooth.battaryStream.listen((event) {
      print("battaryStream "+event.toString());
    });
    baseScanner.isServiceConnected.listen((event) {
      print("isServiceConnected "+event.toString());
    });
    baseScanner.scannerDisabled.listen((event) {
      print("scannerDisabled $event");
    });

    emit(const FirstScreenState.suc());
  }

  Future<void> disableScanner() async {
    await baseScanner.disableScanner();
    print("disableScanner");
  }

  Future<void> enableScanner() async {
    await baseScanner.enableScanner();
    print("enableScanner");
  }

  @override
  bool? onScanEvent(String payload) {
    emit(FirstScreenState.onScan(barcode: payload));
  }

  @override
  bool? onErrorScan(Exception error) {
    // TODO: implement onErrorScan
    throw UnimplementedError();
  }

  Future<void> goToCOMMode(bool flag) async {
    multiScannerBluetooth.showBluetoothDialog();  }

  Future<void> goToHIDMode() async {
    mertechController.goToHIDMode();
  }
  Future<void> scanBarcodeByCamera() async {
   final barcode = await baseScanner.scanBarcodeByCamera();
   print("barcode $barcode");
  }

  @override
  Future<void> close() {
    getAccountUseCase.removeDelegate(this);
    return super.close();
  }
}
