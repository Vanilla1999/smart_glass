import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/voice_action_catalog.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/wear_voice_command.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_typing/segmented_recognition_result.dart';

class RecognitionArbitration {
  const RecognitionArbitration._({
    this.command,
    this.phrase,
    this.preview,
    this.stableCandidate,
    this.clearPreview = false,
    this.ignoredEndpointOnly = false,
  });

  const RecognitionArbitration.command(WearVoiceCommand command)
      : this._(command: command, clearPreview: true);
  const RecognitionArbitration.stable(SegmentedRecognitionResult result)
      : this._(stableCandidate: result);
  const RecognitionArbitration.phrase(SegmentedRecognitionResult phrase)
      : this._(phrase: phrase);
  const RecognitionArbitration.preview(SegmentedRecognitionResult preview)
      : this._(preview: preview);
  const RecognitionArbitration.ignoredEndpointOnly()
      : this._(ignoredEndpointOnly: true);

  final WearVoiceCommand? command;
  final SegmentedRecognitionResult? phrase;
  final SegmentedRecognitionResult? preview;
  final SegmentedRecognitionResult? stableCandidate;
  final bool clearPreview;
  final bool ignoredEndpointOnly;
}

/// Arbitrates logical Vosk utterances. Acoustic VAD segments are diagnostics
/// only and may contain any number of independent command utterances.
class RecognitionArbiter {
  RecognitionArbiter({
    VoiceActionCatalog? actionCatalog,
    WearScreenId Function()? screenProvider,
    int Function()? routeRevisionProvider,
    int Function()? grammarRevisionProvider,
    int Function()? freeTextEpochProvider,
  })  : _catalog = actionCatalog ?? VoiceActionCatalog(),
        _screenProvider = screenProvider ?? (() => WearScreenId.menu),
        _routeRevisionProvider = routeRevisionProvider ?? (() => 1),
        _grammarRevisionProvider = grammarRevisionProvider ?? (() => 1),
        _freeTextEpochProvider = freeTextEpochProvider ?? (() => 0);

  final VoiceActionCatalog _catalog;
  final WearScreenId Function() _screenProvider;
  final int Function() _routeRevisionProvider;
  final int Function() _grammarRevisionProvider;
  final int Function() _freeTextEpochProvider;
  final Set<String> _claimedUtterances = <String>{};
  final Map<String, String> _latestPartial = <String, String>{};
  final Set<String> _loggedEndpointOnlyPartials = <String>{};
  int _currentCaptureEpoch = 0;

  int get debugRetainedPartialCount => _latestPartial.length;

  void startSegment(SpeechSegmentStarted started) {
    _acceptCaptureEpoch(started.captureEpoch);
  }

  RecognitionArbitration? accept(SegmentedRecognitionResult result) {
    if (!_isCurrent(result)) return null;
    final String key = _key(result);
    if (_claimedUtterances.contains(key)) return null;
    final WearScreenId screen = result.sourceScreen;

    if (result.kind == RecognitionKind.partial &&
        result.dynamicItemId != null) {
      return RecognitionArbitration.preview(result);
    }

    if (result.lane == RecognitionLane.freeText) {
      if (result.kind == RecognitionKind.partial) {
        return null;
      }
      final VoiceActionEntry? action = _catalog.resolve(screen, result.text);
      _claim(key);
      if (action != null) {
        return RecognitionArbitration.command(action.command);
      }
      return RecognitionArbitration.phrase(result);
    }

    if (result.kind == RecognitionKind.partial) {
      final String normalized = VoiceActionCatalog.normalize(result.text);
      final VoiceActionEntry? exactAction =
          _catalog.resolve(screen, normalized);
      if (exactAction?.activationPolicy == VoiceActivationPolicy.endpointOnly) {
        final String logKey = '$key:$normalized:${exactAction!.command.name}';
        if (_loggedEndpointOnlyPartials.add(logKey)) {
          while (_loggedEndpointOnlyPartials.length > 128) {
            _loggedEndpointOnlyPartials.remove(
              _loggedEndpointOnlyPartials.first,
            );
          }
          // ignore: avoid_print
          print(
            '[VOICE_POLICY] screen=${result.sourceScreen.name} '
            'utteranceId=${result.commandUtteranceId} kind=partial '
            'text="$normalized" command=${exactAction.command.name} '
            'policy=endpointOnly decision=ignored_until_endpoint',
          );
        }
        return const RecognitionArbitration.ignoredEndpointOnly();
      }

      final VoiceActionEntry? action =
          _catalog.resolvePartial(screen, normalized);
      _latestPartial[key] = VoiceActionCatalog.normalize(result.text);
      while (_latestPartial.length > 128) {
        _latestPartial.remove(_latestPartial.keys.first);
      }
      if (action == null) return null;
      switch (action.activationPolicy) {
        case VoiceActivationPolicy.immediateExactPartial:
          _claim(key);
          return RecognitionArbitration.command(action.command);
        case VoiceActivationPolicy.stableExactPartial:
          return RecognitionArbitration.stable(result);
        case VoiceActivationPolicy.endpointOnly:
          throw StateError('Endpoint-only partial must be handled first');
      }
    }

    final VoiceActionEntry? action = _catalog.resolve(screen, result.text);
    _latestPartial.remove(key);
    _loggedEndpointOnlyPartials.removeWhere(
      (String logKey) => logKey.startsWith('$key:'),
    );
    if (action == null) return null;
    _claim(key);
    return RecognitionArbitration.command(action.command);
  }

  RecognitionArbitration? claimStable(SegmentedRecognitionResult candidate) {
    if (!_isCurrent(candidate)) return null;
    final String key = _key(candidate);
    if (_claimedUtterances.contains(key) ||
        _latestPartial[key] != VoiceActionCatalog.normalize(candidate.text)) {
      return null;
    }
    final VoiceActionEntry? action = _catalog.resolvePartial(
      candidate.sourceScreen,
      candidate.text,
    );
    if (action?.activationPolicy != VoiceActivationPolicy.stableExactPartial) {
      return null;
    }
    _claim(key);
    return RecognitionArbitration.command(action!.command);
  }

  bool canPreview(SegmentedRecognitionResult candidate) {
    return _isCurrent(candidate) &&
        candidate.dynamicItemId != null &&
        !_claimedUtterances.contains(_key(candidate));
  }

  RecognitionArbitration? endSegment(SpeechSegmentEnded ended) => null;

  void resetRoute() {
    _claimedUtterances.clear();
    _latestPartial.clear();
    _loggedEndpointOnlyPartials.clear();
  }

  void dispose() => resetRoute();

  bool _isCurrent(SegmentedRecognitionResult result) {
    if (!_acceptCaptureEpoch(result.captureEpoch)) return false;
    if (result.routeRevision <= 0 || result.grammarRevision <= 0) return false;
    return result.routeRevision == _routeRevisionProvider() &&
        result.grammarRevision == _grammarRevisionProvider() &&
        (result.lane == RecognitionLane.command ||
            result.freeTextEpoch == _freeTextEpochProvider()) &&
        result.sourceScreen == _screenProvider();
  }

  bool _acceptCaptureEpoch(int captureEpoch) {
    if (captureEpoch < _currentCaptureEpoch) return false;
    if (captureEpoch > _currentCaptureEpoch) {
      _currentCaptureEpoch = captureEpoch;
      resetRoute();
    }
    return true;
  }

  void _claim(String key) {
    _latestPartial.remove(key);
    _loggedEndpointOnlyPartials.removeWhere(
      (String logKey) => logKey.startsWith('$key:'),
    );
    _claimedUtterances.add(key);
    if (_claimedUtterances.length > 128) {
      _claimedUtterances.remove(_claimedUtterances.first);
    }
  }

  String _key(SegmentedRecognitionResult result) =>
      '${result.captureEpoch}:${result.commandUtteranceId}:'
      '${result.routeRevision}:${result.grammarRevision}:'
      '${result.freeTextEpoch}:${result.sourceScreen.name}';
}
