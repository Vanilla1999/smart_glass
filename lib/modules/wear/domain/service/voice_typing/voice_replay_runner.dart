import 'dart:typed_data';

import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/recognition_arbiter.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/voice_action_catalog.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/wear_voice_command.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_typing/segmented_recognition_result.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_typing/speech_recognition_service.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_typing/speech_segmenter.dart';

class ReplayRecognition {
  const ReplayRecognition({required this.kind, required this.text});

  final RecognitionKind kind;
  final String text;
}

abstract interface class VoiceReplayRecognizer {
  Iterable<ReplayRecognition> accept(
    Uint8List pcmFrame, {
    required List<String> grammar,
  });
}

class VoiceReplayResult {
  const VoiceReplayResult({
    required this.commands,
    required this.freeTextReplayCount,
    required this.lastUtteranceId,
  });

  final List<WearVoiceCommand> commands;
  final int freeTextReplayCount;
  final int lastUtteranceId;
}

/// Host-side regression harness. PCM follows the production fixed-frame VAD
/// and utterance arbiter path; only the native Vosk call is injected.
class VoiceReplayRunner {
  VoiceReplayRunner({
    required VoiceReplayRecognizer recognizer,
    VoiceActionCatalog? catalog,
    SpeechSegmenter? segmenter,
  })  : _recognizer = recognizer,
        _catalog = catalog ?? VoiceActionCatalog(),
        _segmenter = segmenter ??
            SpeechSegmenter(
              calibrationDuration: Duration.zero,
              maxSegmentDuration: const Duration(seconds: 4),
            );

  final VoiceReplayRecognizer _recognizer;
  final VoiceActionCatalog _catalog;
  final SpeechSegmenter _segmenter;

  VoiceReplayResult run({
    required Iterable<Uint8List> packets,
    required WearScreenId screen,
    int captureEpoch = 1,
  }) {
    int utteranceId = 1;
    int freeTextReplayCount = 0;
    final List<WearVoiceCommand> commands = <WearVoiceCommand>[];
    final PcmFrameAccumulator frames = PcmFrameAccumulator(frameBytes: 640);
    final RecognitionArbiter arbiter = RecognitionArbiter(
      actionCatalog: _catalog,
      screenProvider: () => screen,
    );
    _segmenter.begin(captureEpoch);

    for (final Uint8List packet in packets) {
      for (final PcmFramePair frame in frames.add(packet, packet)) {
        final SpeechSegment? segment = _segmenter.add(frame.raw, captureEpoch);
        if (segment == null) continue;
        if (segment.started) {
          arbiter.startSegment(SpeechSegmentStarted(
            captureEpoch: captureEpoch,
            segmentId: segment.segmentId,
            startChunkId: segment.lastChunkId,
          ));
        }
        for (final ReplayRecognition recognition in _recognizer.accept(
          frame.boosted,
          grammar: _catalog.grammarFor(screen),
        )) {
          final SegmentedRecognitionResult event = SegmentedRecognitionResult(
            captureEpoch: captureEpoch,
            segmentId: segment.segmentId,
            lane: RecognitionLane.command,
            kind: recognition.kind,
            text: recognition.text,
            lastChunkId: segment.lastChunkId,
            parsedCommand: null,
            commandUtteranceId: utteranceId,
            sourceScreen: screen,
          );
          RecognitionArbitration? decision = arbiter.accept(event);
          if (decision?.stableCandidate != null) {
            decision = arbiter.claimStable(event);
          }
          if (decision?.command case final WearVoiceCommand command) {
            commands.add(command);
          }
          if (recognition.kind == RecognitionKind.endpointResult) {
            if (decision?.command == null &&
                _catalog.resolve(screen, recognition.text) == null) {
              freeTextReplayCount++;
            }
            utteranceId++;
          }
        }
      }
    }

    return VoiceReplayResult(
      commands: List<WearVoiceCommand>.unmodifiable(commands),
      freeTextReplayCount: freeTextReplayCount,
      lastUtteranceId: utteranceId,
    );
  }
}
