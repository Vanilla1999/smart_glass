import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';

class WearActualScreenStore {
  WearActualScreenStore(
      {WearScreenId initialScreen = WearScreenId.scannerConnect})
      : _screen = initialScreen;

  WearScreenId _screen;
  int _revision = 0;

  WearScreenId get screen => _screen;
  int get revision => _revision;

  bool confirm(WearScreenId screen) {
    if (_screen == screen) return false;
    _screen = screen;
    _revision++;
    return true;
  }
}
