import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';

class WearVoiceDelayEvent {
  const WearVoiceDelayEvent({
    required this.visible,
    required this.captureEpoch,
    required this.segmentId,
    required this.sourceScreen,
    required this.routeRevision,
    required this.grammarRevision,
    required this.freeTextEpoch,
  });

  final bool visible;
  final int captureEpoch;
  final int segmentId;
  final WearScreenId sourceScreen;
  final int routeRevision;
  final int grammarRevision;
  final int freeTextEpoch;
}
