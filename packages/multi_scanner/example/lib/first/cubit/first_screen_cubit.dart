import 'package:bloc/bloc.dart';
import 'package:multi_scanner/multi_scanner.dart';

import 'package:multi_scanner_example/first/cubit/first_screen_state.dart';
import 'package:multi_scanner_example/main.dart';

class FirstScreenCubit extends Cubit<FirstScreenState>
    implements MultiScannerDelegate {
  FirstScreenCubit() : super(const FirstScreenState.loading());

  final MultiScanner getAccountUseCase = getIt<MultiScanner>();
  final MultiScannerController multiScannerController =
      MultiScannerController();
  final HoneywellController honeywellController = HoneywellController();
  final BaseController baseScanner = BaseController();
  final MertechController mertechController = MertechController();
  final WakeUpController wakeUpController = WakeUpController();
  final MultiScannerBluetooth multiScannerBluetooth = MultiScannerBluetooth();

  bool _delegateRegistered = false;
  Future<void>? _mainParityStart;

  void _registerDelegateOnce() {
    if (_delegateRegistered) return;
    getAccountUseCase.addDelegate(this);
    _delegateRegistered = true;
  }

  /// The production WearScannerRuntime path: init + prepare, without the
  /// example-only Bluetooth/settings side effects. The enclosing parity runtime
  /// intentionally starts this Future concurrently with UAC4 voice capture.
  Future<void> startMainAppParityScanner() {
    return _mainParityStart ??= _startMainAppParityScanner().catchError((
      Object error,
    ) {
      _mainParityStart = null;
      throw error;
    });
  }

  Future<void> _startMainAppParityScanner() async {
    _registerDelegateOnce();
    await baseScanner.init();
    await baseScanner.prepareForWear();
    emit(const FirstScreenState.suc());
  }

  /// Keeps the original broad example initialization available for manual
  /// comparison, but it is no longer run automatically at app startup.
  Future<void> initScanner() async {
    _registerDelegateOnce();
    await baseScanner.init();
    await MultiScannerBluetooth().init();
    await mertechController.goToCOMMode();
    await wakeUpController.wakeUpOnScanButton();

    print(await BaseController().isPCH());
    print(await BaseController().isDefaultHorizontal());
    print(await BaseController().isNotNeedCamera());
    print(await BaseController().isNeedBT());
    multiScannerBluetooth.battaryStream.listen((event) {
      print('battaryStream $event');
    });
    baseScanner.isServiceConnected.listen((event) {
      print('isServiceConnected $event');
    });
    baseScanner.scannerDisabled.listen((event) {
      print('scannerDisabled $event');
    });

    emit(const FirstScreenState.suc());
  }

  Future<void> disableScanner() async {
    await baseScanner.disableScanner();
    print('disableScanner');
  }

  Future<void> enableScanner() async {
    await baseScanner.enableScanner();
    print('enableScanner');
  }

  @override
  bool? onScanEvent(String payload) {
    emit(FirstScreenState.onScan(barcode: payload));
    return true;
  }

  @override
  bool? onErrorScan(Exception error) {
    print('scanner error: $error');
    return false;
  }

  Future<void> goToCOMMode(bool flag) async {
    await multiScannerBluetooth.showBluetoothDialog();
  }

  Future<void> goToHIDMode() async {
    await mertechController.goToHIDMode();
  }

  Future<void> scanBarcodeByCamera() async {
    final barcode = await baseScanner.scanBarcodeByCamera();
    print('barcode $barcode');
  }

  @override
  Future<void> close() {
    if (_delegateRegistered) {
      getAccountUseCase.removeDelegate(this);
      _delegateRegistered = false;
    }
    return super.close();
  }
}
