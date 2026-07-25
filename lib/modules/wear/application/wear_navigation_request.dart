import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';

class WearNavigationRequest {
  const WearNavigationRequest({
    required this.requestId,
    required this.screen,
    this.extra,
    this.replaceCurrent = false,
    this.popCurrent = false,
  });

  final int requestId;
  final WearScreenId screen;
  final Object? extra;
  final bool replaceCurrent;
  final bool popCurrent;

  @override
  String toString() => 'WearNavigationRequest(requestId: $requestId, '
      'screen: $screen, extra: $extra, '
      'replaceCurrent: $replaceCurrent, popCurrent: $popCurrent)';
}
