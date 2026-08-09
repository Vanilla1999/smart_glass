import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/wear_voice_command_event.dart';

bool isCurrentWearVoiceCommandEvent(
  WearVoiceCommandEvent event, {
  required WearScreenId screen,
  required int captureEpoch,
  required int routeRevision,
  required int grammarRevision,
}) {
  return event.sourceScreen == screen &&
      event.captureEpoch == captureEpoch &&
      event.routeRevision == routeRevision &&
      event.grammarRevision == grammarRevision;
}
