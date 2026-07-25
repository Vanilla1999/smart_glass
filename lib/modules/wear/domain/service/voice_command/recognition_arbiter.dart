import 'dart:async';

import 'package:smart_glasses/modules/wear/domain/service/voice_command/voice_command_parser_service.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/wear_voice_command.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_typing/segmented_recognition_result.dart';

class RecognitionArbitration {
  const RecognitionArbitration._(
      {this.command, this.phrase, this.isPartial = false});

  const RecognitionArbitration.command(WearVoiceCommand command)
      : this._(command: command);

  const RecognitionArbitration.phrase(String phrase, {required bool isPartial})
      : this._(phrase: phrase, isPartial: isPartial);

  final WearVoiceCommand? command;
  final String? phrase;
  final bool isPartial;
}

/// Chooses at most one command for each capture segment, without timing rules.
class RecognitionArbiter {
  RecognitionArbiter({
    VoiceCommandParserService? commandParserService,
    this.closedSegmentCleanupTimeout = const Duration(seconds: 2),
  }) : _parser = commandParserService ?? VoiceCommandParserService();

  final VoiceCommandParserService _parser;
  final Duration closedSegmentCleanupTimeout;
  final Map<String, _SegmentArbitrationState> _segments =
      <String, _SegmentArbitrationState>{};
  final Map<String, Timer> _closedSegmentCleanup = <String, Timer>{};
  int _currentCaptureEpoch = 0;

  RecognitionArbitration? accept(SegmentedRecognitionResult result) {
    if (result.captureEpoch < _currentCaptureEpoch) return null;
    if (result.captureEpoch > _currentCaptureEpoch) {
      _currentCaptureEpoch = result.captureEpoch;
      _segments.clear();
      _clearClosedSegments();
    }

    final String key = '${result.captureEpoch}:${result.segmentId}';
    if (_closedSegmentCleanup.containsKey(key)) return null;
    final _SegmentArbitrationState state =
        _segments.putIfAbsent(key, _SegmentArbitrationState.new);
    if (result.lane == RecognitionLane.command) {
      final WearVoiceCommand? command = result.parsedCommand;
      if (command == null || state.claimedByCommand) return null;
      state.claimedByCommand = true;
      state.bufferedFreeText = null;
      return RecognitionArbitration.command(command);
    }

    if (state.claimedByCommand || _parser.parseExact(result.text) != null) {
      return null;
    }
    final String text = result.text.trim();
    if (text.isEmpty) return null;
    if (result.kind == RecognitionKind.finalResult) {
      state.bufferedFreeText = text;
      return null;
    }
    return RecognitionArbitration.phrase(
      text,
      isPartial: true,
    );
  }

  RecognitionArbitration? endSegment(SpeechSegmentEnded ended) {
    if (ended.captureEpoch != _currentCaptureEpoch) return null;
    final String key = '${ended.captureEpoch}:${ended.segmentId}';
    final _SegmentArbitrationState? state = _segments.remove(key);
    _closedSegmentCleanup[key] = Timer(closedSegmentCleanupTimeout, () {
      _closedSegmentCleanup.remove(key);
    });
    if (state == null || state.claimedByCommand) return null;
    final String? phrase = state.bufferedFreeText;
    if (phrase == null) return null;
    return RecognitionArbitration.phrase(phrase, isPartial: false);
  }

  void dispose() => _clearClosedSegments();

  void _clearClosedSegments() {
    for (final Timer timer in _closedSegmentCleanup.values) {
      timer.cancel();
    }
    _closedSegmentCleanup.clear();
  }
}

class _SegmentArbitrationState {
  bool claimedByCommand = false;
  String? bufferedFreeText;
}
