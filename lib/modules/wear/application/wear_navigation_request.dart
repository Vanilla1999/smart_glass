import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';

class WearNavigationRequest {
  const WearNavigationRequest({
    required this.screen,
    this.extra,
  });

  final WearScreenId screen;
  final Object? extra;

  @override
  String toString() => 'WearNavigationRequest(screen: $screen, extra: $extra)';
}
