import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';

class WearVoicePhraseEvent {
  const WearVoicePhraseEvent({
    required this.phrase,
    required this.traceId,
    required this.captureEpoch,
    this.recognitionContextId = 1,
    required this.speechTurnId,
    required this.decoderGeneration,
    required this.commandUtteranceId,
    required this.sourceScreen,
    required this.routeRevision,
    required this.grammarRevision,
    required this.freeTextEpoch,
    required this.listRevision,
  });

  final String phrase;
  final String traceId;
  final int captureEpoch;
  final int recognitionContextId;
  final int speechTurnId;
  final int decoderGeneration;
  final int commandUtteranceId;
  final WearScreenId sourceScreen;
  final int routeRevision;
  final int grammarRevision;
  final int freeTextEpoch;
  final int listRevision;
}
