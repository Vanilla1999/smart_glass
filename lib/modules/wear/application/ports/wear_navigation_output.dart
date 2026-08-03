import 'package:smart_glasses/modules/wear/application/wear_navigation_entry.dart';
import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';

abstract class WearNavigationOutput {
  Future<void> goTo(WearScreenId screen, {Object? extra});

  Future<void> replace(WearScreenId screen, {Object? extra});

  Future<void> back();

  Future<void> home();

  Future<void> synchronize(List<WearNavigationEntry> history);
}
