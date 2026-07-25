import 'package:smart_glasses/modules/wear/domain/service/voice_command/wear_voice_command.dart';

enum RecognitionLane { command, freeText }

enum RecognitionKind { partial, finalResult }

class SpeechSegmentEnded {
  const SpeechSegmentEnded({
    required this.captureEpoch,
    required this.segmentId,
    required this.endChunkId,
    this.commandLaneCompleted = true,
    this.freeTextLaneCompleted = true,
    this.commandLaneError,
    this.freeTextLaneError,
  });

  final int captureEpoch;
  final int segmentId;
  final int endChunkId;
  final bool commandLaneCompleted;
  final bool freeTextLaneCompleted;
  final Object? commandLaneError;
  final Object? freeTextLaneError;
}

class SegmentedRecognitionResult {
  const SegmentedRecognitionResult({
    required this.captureEpoch,
    required this.segmentId,
    required this.lane,
    required this.kind,
    required this.text,
    required this.lastChunkId,
    required this.parsedCommand,
  });

  final int captureEpoch;
  final int segmentId;
  final RecognitionLane lane;
  final RecognitionKind kind;
  final String text;
  final int lastChunkId;
  final WearVoiceCommand? parsedCommand;
}
