import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/voice_action_catalog.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/voice_command_parser_service.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/wear_voice_command.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_typing/segmented_recognition_result.dart';

class RecognitionArbitration {
  const RecognitionArbitration._(
      {this.command, this.phrase, this.preview, this.clearPreview = false});

  const RecognitionArbitration.command(
    WearVoiceCommand command, {
    bool clearPreview = false,
  }) : this._(command: command, clearPreview: clearPreview);

  const RecognitionArbitration.phrase(String phrase) : this._(phrase: phrase);

  const RecognitionArbitration.preview(String preview)
      : this._(preview: preview);

  final WearVoiceCommand? command;
  final String? phrase;
  final String? preview;
  final bool clearPreview;
}

class VoiceSegmentContext {
  const VoiceSegmentContext({
    required this.captureEpoch,
    required this.segmentId,
    required this.actualScreen,
    required this.catalogRevision,
  });

  final int captureEpoch;
  final int segmentId;
  final WearScreenId actualScreen;
  final int catalogRevision;
}

/// Resolves one capture segment only after the command lane has completed.
class RecognitionArbiter {
  RecognitionArbiter({
    VoiceCommandParserService? commandParserService,
    VoiceActionCatalog? actionCatalog,
    WearScreenId Function()? screenProvider,
    this.maxClosedSegments = 128,
  })  : _parser = commandParserService ?? VoiceCommandParserService(),
        _catalog = actionCatalog ?? VoiceActionCatalog(),
        _screenProvider = screenProvider ?? (() => WearScreenId.menu);

  final VoiceCommandParserService _parser;
  final VoiceActionCatalog _catalog;
  final WearScreenId Function() _screenProvider;
  final int maxClosedSegments;
  final Map<String, _SegmentArbitrationState> _segments =
      <String, _SegmentArbitrationState>{};
  final Map<String, void> _closedSegments = <String, void>{};
  int _currentCaptureEpoch = 0;

  void startSegment(SpeechSegmentStarted started) {
    if (!_acceptCaptureEpoch(started.captureEpoch)) return;
    final String key = '${started.captureEpoch}:${started.segmentId}';
    if (_closedSegments.containsKey(key)) return;
    _segments.putIfAbsent(
      key,
      () => _SegmentArbitrationState(VoiceSegmentContext(
        captureEpoch: started.captureEpoch,
        segmentId: started.segmentId,
        actualScreen: _screenProvider(),
        catalogRevision: _catalog.revision,
      )),
    );
  }

  RecognitionArbitration? accept(SegmentedRecognitionResult result) {
    if (!_acceptCaptureEpoch(result.captureEpoch)) return null;

    final String key = '${result.captureEpoch}:${result.segmentId}';
    if (_closedSegments.containsKey(key)) return null;
    final _SegmentArbitrationState state = _segments.putIfAbsent(
      key,
      () => _SegmentArbitrationState(VoiceSegmentContext(
        captureEpoch: result.captureEpoch,
        segmentId: result.segmentId,
        actualScreen: _screenProvider(),
        catalogRevision: _catalog.revision,
      )),
    );
    if (result.lane == RecognitionLane.command) {
      final String text = result.text.trim();
      if (text.isEmpty) return null;
      if (result.kind == RecognitionKind.partial) {
        if (state.claimedCommand != null) return null;
        final WearVoiceCommand? command =
            _catalog.resolveFastAlias(state.context.actualScreen, text);
        if (command == null) return null;
        state.claimedCommand = command;
        print(
          '[VoiceArbiter] segment=$key screen=${state.context.actualScreen} '
          'earlyCommand=$command text="$text"',
        );
        return RecognitionArbitration.command(command, clearPreview: true);
      }
      final WearVoiceCommand? command =
          _resolveFinal(state.context.actualScreen, text);
      if (state.claimedCommand != null) {
        if (command != null && command != state.claimedCommand) {
          print(
            '[VoiceArbiter] segment=$key earlyCommand=${state.claimedCommand} '
            'finalCommand=$command decision=keep_early_command',
          );
        }
        return null;
      }
      if (command == null) return null;
      state.command = command;
      return null;
    }

    if (state.claimedCommand != null || state.command != null) {
      return null;
    }
    final String text = result.text.trim();
    if (text.isEmpty) return null;
    if (result.kind == RecognitionKind.partial) {
      return RecognitionArbitration.preview(text);
    }
    // Commit free text only after its sibling grammar lane has closed.
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
    if (state.claimedCommand != null) return null;
    if (command != null) {
      return RecognitionArbitration.command(command, clearPreview: true);
    }
    if (!ended.freeTextLaneCompleted) return null;
    final String? phrase = state.bufferedFreeText;
    if (phrase == null) return null;
    return RecognitionArbitration.phrase(phrase);
  }

  void dispose() => _clearClosedSegments();

  void _clearClosedSegments() {
    _closedSegments.clear();
  }

  bool _acceptCaptureEpoch(int captureEpoch) {
    if (captureEpoch < _currentCaptureEpoch) return false;
    if (captureEpoch > _currentCaptureEpoch) {
      _currentCaptureEpoch = captureEpoch;
      _segments.clear();
      _clearClosedSegments();
    }
    return true;
  }

  WearVoiceCommand? _resolveFinal(WearScreenId screen, String text) {
    final WearVoiceCommand? catalogCommand =
        _catalog.resolveFinal(screen, text);
    if (catalogCommand != null) return catalogCommand;
    if (_catalog.isKnownPhrase(text)) return null;
    return _parser.parseExact(text);
  }
}

class _SegmentArbitrationState {
  _SegmentArbitrationState(this.context);

  final VoiceSegmentContext context;
  WearVoiceCommand? claimedCommand;
  WearVoiceCommand? command;
  String? bufferedFreeText;
}
