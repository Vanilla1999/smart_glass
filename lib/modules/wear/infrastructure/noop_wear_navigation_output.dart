import 'package:smart_glasses/modules/wear/application/ports/wear_navigation_output.dart';
import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';

class NoopWearNavigationOutput implements WearNavigationOutput {
  @override
  Future<void> goTo(WearScreenId screen, {Object? extra}) async {
    print('[NoopWearNavigationOutput] goTo screen=$screen extra=$extra');
  }

  @override
  Future<void> back() async {
    print('[NoopWearNavigationOutput] back');
  }

  @override
  Future<void> home() async {
    print('[NoopWearNavigationOutput] home');
  }
}
