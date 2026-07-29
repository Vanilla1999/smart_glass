import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/wear_voice_command.dart';

enum RecognitionEventKind { partial, endpointResult, streamFinal }

class CommandRecognitionEvent {
  const CommandRecognitionEvent({
    required this.captureEpoch,
    required this.acousticSegmentId,
    required this.commandUtteranceId,
    required this.routeRevision,
    required this.grammarRevision,
    required this.sourceScreen,
    required this.kind,
    required this.text,
    required this.command,
    required this.recognizedAtMillis,
  });

  final int captureEpoch;
  final int acousticSegmentId;
  final int commandUtteranceId;
  final int routeRevision;
  final int grammarRevision;
  final WearScreenId sourceScreen;
  final RecognitionEventKind kind;
  final String text;
  final WearVoiceCommand? command;
  final int recognizedAtMillis;
}
