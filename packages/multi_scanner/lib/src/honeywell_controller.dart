import 'package:multi_scanner/src/platform/multi_scanner_platform_interface.dart';

import 'base_controller.dart';

class HoneywellController extends BaseController {
  ///Singleton MultiScannerController
  factory HoneywellController() {
    _singleton ??= HoneywellController._();
    return _singleton!;
  }

  HoneywellController._();

  static HoneywellController? _singleton;

  static MultiScannerPlatform get _platform {
    return MultiScannerPlatform.instance;
  }

  /// Если flag = false выключается фонарик.
  Future<void> switchHoneywellLight(bool flag) =>
      _platform.switchHoneywellLight(flag);

  /// Возвращает true, когда фонарик включен.
  Future<bool> getHoneywellLight() => _platform.getHoneywellLight();

  /// смена флага rhk
  Future<void> changeRhkHoneywell(bool flag) =>
      _platform.changeRhkHoneywell(flag);
}
