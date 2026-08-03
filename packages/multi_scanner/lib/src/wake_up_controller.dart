import 'package:multi_scanner/src/platform/multi_scanner_platform_interface.dart';

import 'base_controller.dart';

class WakeUpController {
  ///Singleton MultiScannerController
  factory WakeUpController() {
    _singleton ??= WakeUpController._();
    return _singleton!;
  }

  WakeUpController._();

  static WakeUpController? _singleton;

  static MultiScannerPlatform get _platform {
    return MultiScannerPlatform.instance;
  }


  Future<void> wakeUpOnScanButton() => _platform.wakeUpOnScanButton();

}
