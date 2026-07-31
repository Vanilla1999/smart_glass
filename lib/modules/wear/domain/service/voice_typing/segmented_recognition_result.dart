import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/wear_voice_command.dart';

enum RecognitionLane { command, freeText }

enum RecognitionKind { partial, endpointResult, streamFinal }

class SpeechSegmentStarted {
  const SpeechSegmentStarted({
    required this.captureEpoch,
    required this.segmentId,
    required this.startChunkId,
  });

  final int captureEpoch;
  final int segmentId;
  final int startChunkId;
}

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
    this.commandUtteranceId = 0,
    this.routeRevision = 0,
    this.grammarRevision = 0,
    this.sourceScreen = WearScreenId.menu,
    this.partialRevision = 0,
    this.commandUtteranceStartedAtMillis,
    this.freeTextEpoch = 0,
    this.isLiveFreeText = false,
    this.recognizedAtMillis = 0,
    this.listRevision = 0,
    this.dynamicItemId,
  });

  final int captureEpoch;
  final int segmentId;
  final RecognitionLane lane;
  final RecognitionKind kind;
  final String text;
  final int lastChunkId;
  final WearVoiceCommand? parsedCommand;
  final int commandUtteranceId;
  final int routeRevision;
  final int grammarRevision;
  final WearScreenId sourceScreen;
  final int partialRevision;
  final int? commandUtteranceStartedAtMillis;
  final int freeTextEpoch;
  final bool isLiveFreeText;
  final int recognizedAtMillis;
  final int listRevision;
  final String? dynamicItemId;
}
