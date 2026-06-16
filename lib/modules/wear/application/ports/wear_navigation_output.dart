import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';

abstract class WearNavigationOutput {
  Future<void> goTo(WearScreenId screen, {Object? extra});

  Future<void> back();

  Future<void> home();
}
