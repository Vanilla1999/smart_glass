import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';

class WearNavigationEntry {
  const WearNavigationEntry({required this.screen, this.extra});

  final WearScreenId screen;
  final Object? extra;

  @override
  String toString() => 'WearNavigationEntry(screen: $screen, extra: $extra)';
}
