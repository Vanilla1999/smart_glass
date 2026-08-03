import 'package:multi_scanner/src/base_controller.dart';
import 'package:multi_scanner/src/platform/multi_scanner_platform_interface.dart';

class MovfastGlassController extends BaseController {
  factory MovfastGlassController() {
    return _instance;
  }

  MovfastGlassController._();

  static final MovfastGlassController _instance = MovfastGlassController._();

  static MultiScannerPlatform get _platform => MultiScannerPlatform.instance;

  Future<void> setFlashlight(int state) => _platform.setFlashlight(state);

  Future<int> getFlashlightState() => _platform.getFlashlightState();

  Future<String> takePhoto() => _platform.takePhoto();

  Future<void> deletePhoto(String uri) => _platform.deletePhoto(uri);
}
