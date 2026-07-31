import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';

class WearVoicePreviewEvent {
  const WearVoicePreviewEvent({
    required this.text,
    required this.captureEpoch,
    required this.commandUtteranceId,
    required this.routeRevision,
    required this.grammarRevision,
    required this.freeTextEpoch,
    required this.sourceScreen,
    required this.partialRevision,
    required this.recognizedAtMillis,
    required this.listRevision,
    required this.segmentId,
    required this.itemId,
    required this.isCommandLane,
  });

  final String text;
  final int captureEpoch;
  final int commandUtteranceId;
  final int routeRevision;
  final int grammarRevision;
  final int freeTextEpoch;
  final WearScreenId sourceScreen;
  final int partialRevision;
  final int recognizedAtMillis;
  final int listRevision;
  final int segmentId;
  final String itemId;
  final bool isCommandLane;
}
