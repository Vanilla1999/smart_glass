import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';

enum WearVoiceDelayKind {
  preview,
  processing,
}

class WearVoiceDelayEvent {
  const WearVoiceDelayEvent({
    required this.visible,
    required this.captureEpoch,
    required this.segmentId,
    required this.sourceScreen,
    required this.routeRevision,
    required this.grammarRevision,
    required this.freeTextEpoch,
    this.commandUtteranceId = 0,
    this.listRevision = 0,
    this.kind = WearVoiceDelayKind.preview,
    this.previewText,
    this.statusText,
  });

  final bool visible;
  final int captureEpoch;
  final int segmentId;
  final WearScreenId sourceScreen;
  final int routeRevision;
  final int grammarRevision;
  final int freeTextEpoch;
  final int commandUtteranceId;
  final int listRevision;
  final WearVoiceDelayKind kind;
  final String? previewText;
  final String? statusText;
}
