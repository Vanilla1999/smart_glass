import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';

class WearVoicePhraseEvent {
  const WearVoicePhraseEvent({
    required this.phrase,
    required this.captureEpoch,
    required this.commandUtteranceId,
    required this.sourceScreen,
    required this.routeRevision,
    required this.grammarRevision,
  });

  final String phrase;
  final int captureEpoch;
  final int commandUtteranceId;
  final WearScreenId sourceScreen;
  final int routeRevision;
  final int grammarRevision;
}
