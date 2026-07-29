import 'package:smart_glasses/modules/wear/domain/service/voice_command/wear_voice_command.dart';

class WearVoiceCommandEvent {
  const WearVoiceCommandEvent({
    required this.command,
    required this.traceId,
    required this.recognizedAtMillis,
    required this.asrMillis,
  });

  final WearVoiceCommand command;
  final String traceId;
  final int recognizedAtMillis;
  final int asrMillis;
}
