import 'package:multi_scanner/src/platform/multi_scanner_platform_interface.dart';
@Deprecated('Используй HoneywellController, UrovoController')
class MultiScannerController{

  ///Singleton MultiScannerController
  factory MultiScannerController() {
    _singleton ??= MultiScannerController._();
    return _singleton!;
  }

  MultiScannerController._();

  static MultiScannerController? _singleton;

  static MultiScannerPlatform get _platform {
    return MultiScannerPlatform.instance;
  }

  /// Если flag = false выключается фонарик.
  Future<void> switchHoneywellLight(bool flag) => _platform.switchHoneywellLight(flag);

  /// Возвращает true, когда фонарик включен.
  Future<bool> getHoneywellLight() => _platform.getHoneywellLight();

  Future<void> setFlashlight(int state) => _platform.setFlashlight(state);

  Future<int> getFlashlightState() => _platform.getFlashlightState();

  /// смена флага rhk
  Future<void> changeRhkHoneywell(bool flag) => _platform.changeRhkHoneywell(flag);

  /// Возвращает true, если нужно развернуть клавиатуру по умолчанию.
  Future<bool> needDefaultExpandKeyboard() => _platform.needDefaultExpandKeyboard();
}
