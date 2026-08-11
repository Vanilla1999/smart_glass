import 'package:multi_scanner/src/base_controller.dart';
import 'package:multi_scanner/src/platform/multi_scanner_platform_interface.dart';

class MovfastGlassController extends BaseController {
  factory MovfastGlassController() {
    return _instance;
  }

  MovfastGlassController._();

  static final MovfastGlassController _instance = MovfastGlassController._();

  static const int soundDefault = 0;
  static const int soundPortal = 1;
  static const int soundSciFiChirp = 2;
  static const int soundDigitalClick = 3;
  static const int soundSuccessPop = 4;
  static const int soundCyberScanner = 5;
  static const int soundRetroBarcode = 6;

  static MultiScannerPlatform get _platform => MultiScannerPlatform.instance;

  Future<void> setFlashlight(int state) => _platform.setFlashlight(state);

  Future<int> getFlashlightState() => _platform.getFlashlightState();

  Future<void> changeScanSound(int sound) {
    if (sound < soundDefault || sound > soundRetroBarcode) {
      throw RangeError.range(sound, soundDefault, soundRetroBarcode, 'sound');
    }
    return _platform.changeScanSound(sound);
  }

  Future<String> takePhoto() => _platform.takePhoto();

  Future<void> deletePhoto(String uri) => _platform.deletePhoto(uri);
}
