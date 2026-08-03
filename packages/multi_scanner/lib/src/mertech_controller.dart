import 'package:multi_scanner/src/platform/multi_scanner_platform_interface.dart';

import 'base_controller.dart';

class MertechController extends BaseController {
  ///Singleton MultiScannerController
  factory MertechController() {
    _singleton ??= MertechController._();
    return _singleton!;
  }

  MertechController._();

  static MertechController? _singleton;

  static MultiScannerPlatform get _platform {
    return MultiScannerPlatform.instance;
  }


  Future<void> goToCOMMode() => _platform.goToCOMMode();

  Future<void> goToHIDMode() => _platform.goToHIDMode();
}
