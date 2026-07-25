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

/// Resolves one capture segment only after the command lane has completed.
class RecognitionArbiter {
  RecognitionArbiter({
    VoiceCommandParserService? commandParserService,
    this.maxClosedSegments = 128,
  }) : _parser = commandParserService ?? VoiceCommandParserService();

  final VoiceCommandParserService _parser;
  final int maxClosedSegments;
  final Map<String, _SegmentArbitrationState> _segments =
      <String, _SegmentArbitrationState>{};
  final Map<String, void> _closedSegments = <String, void>{};
  int _currentCaptureEpoch = 0;

  RecognitionArbitration? accept(SegmentedRecognitionResult result) {
    if (result.captureEpoch < _currentCaptureEpoch) return null;
    if (result.captureEpoch > _currentCaptureEpoch) {
      _currentCaptureEpoch = result.captureEpoch;
      _segments.clear();
      _clearClosedSegments();
    }

    final String key = '${result.captureEpoch}:${result.segmentId}';
    if (_closedSegments.containsKey(key)) return null;
    final _SegmentArbitrationState state =
        _segments.putIfAbsent(key, _SegmentArbitrationState.new);
    if (result.lane == RecognitionLane.command) {
      final WearVoiceCommand? command = result.parsedCommand;
      if (command == null || result.kind != RecognitionKind.finalResult) {
        return null;
      }
      state.command = command;
      return null;
    }

    if (state.command != null || _parser.parseExact(result.text) != null) {
      return null;
    }
    final String text = result.text.trim();
    if (text.isEmpty) return null;
    // A live free-text result can alter focus/search before its sibling
    // grammar result arrives. Keep only the newest candidate until closure.
    state.bufferedFreeText = text;
    return null;
  }

  RecognitionArbitration? endSegment(SpeechSegmentEnded ended) {
    if (ended.captureEpoch != _currentCaptureEpoch) return null;
    final String key = '${ended.captureEpoch}:${ended.segmentId}';
    final _SegmentArbitrationState? state = _segments.remove(key);
    _closedSegments[key] = null;
    if (_closedSegments.length > maxClosedSegments) {
      _closedSegments.remove(_closedSegments.keys.first);
    }
    if (state == null || !ended.commandLaneCompleted) return null;
    final WearVoiceCommand? command = state.command;
    if (command != null) return RecognitionArbitration.command(command);
    if (!ended.freeTextLaneCompleted) return null;
    final String? phrase = state.bufferedFreeText;
    if (phrase == null) return null;
    return RecognitionArbitration.phrase(phrase, isPartial: false);
  }

  void dispose() => _clearClosedSegments();

  void _clearClosedSegments() {
    _closedSegments.clear();
  }
}

class _SegmentArbitrationState {
  WearVoiceCommand? command;
  String? bufferedFreeText;
}
