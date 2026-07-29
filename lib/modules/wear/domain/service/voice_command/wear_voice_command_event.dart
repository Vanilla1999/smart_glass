import 'package:smart_glasses/modules/wear/domain/service/voice_command/wear_voice_command.dart';
import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';

class WearVoiceCommandEvent {
  const WearVoiceCommandEvent({
    required this.command,
    required this.traceId,
    required this.recognizedAtMillis,
    required this.asrMillis,
    required this.captureEpoch,
    required this.commandUtteranceId,
    required this.sourceScreen,
    required this.routeRevision,
    required this.grammarRevision,
  });

  final WearVoiceCommand command;
  final String traceId;
  final int recognizedAtMillis;
  final int asrMillis;
  final int captureEpoch;
  final int commandUtteranceId;
  final WearScreenId sourceScreen;
  final int routeRevision;
  final int grammarRevision;
}
