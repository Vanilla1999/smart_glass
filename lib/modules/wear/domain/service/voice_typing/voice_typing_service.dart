import 'dart:async';

import 'package:smart_glasses/modules/wear/domain/service/voice_typing/audio_stream_service.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_typing/number_parser_service.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_typing/segmented_recognition_result.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_typing/speech_recognition_service.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/wear_voice_phrase_event.dart';

class VoiceTypingService {
  factory VoiceTypingService({
    AudioStreamService? audioStreamService,
    SpeechRecognitionService? speechRecognitionService,
    NumberParserService? numberParserService,
    Stream<WearVoicePhraseEvent>? resolvedPhrases,
  }) {
    final AudioStreamService sharedAudio = audioStreamService ??
        speechRecognitionService?.audioStreamService ??
        AudioStreamService();
    return VoiceTypingService._(
      audioStreamService: sharedAudio,
      speechRecognitionService: speechRecognitionService ??
          SpeechRecognitionService(audioStreamService: sharedAudio),
      numberParserService: numberParserService ?? NumberParserService(),
      ownsSpeechRecognitionService: speechRecognitionService == null,
      resolvedPhrases: resolvedPhrases,
    );
  }

  VoiceTypingService._({
    required AudioStreamService audioStreamService,
    required SpeechRecognitionService speechRecognitionService,
    required NumberParserService numberParserService,
    required bool ownsSpeechRecognitionService,
    Stream<WearVoicePhraseEvent>? resolvedPhrases,
  })  : _audioStreamService = audioStreamService,
        _speechRecognitionService = speechRecognitionService,
        _numberParserService = numberParserService,
        _ownsSpeechRecognitionService = ownsSpeechRecognitionService {
    if (resolvedPhrases == null) {
      _recognitionSubscription =
          _speechRecognitionService.segmentedResultsStream.listen(
        _onRecognitionResult,
        onError: _onRecognitionError,
      );
    } else {
      _recognitionSubscription = resolvedPhrases.listen(
        _onResolvedPhraseEvent,
        onError: _onRecognitionError,
      );
    }
  }

  final AudioStreamService _audioStreamService;
  final SpeechRecognitionService _speechRecognitionService;
  final NumberParserService _numberParserService;
  final bool _ownsSpeechRecognitionService;
  final StreamController<String> _resultsController =
      StreamController<String>.broadcast();

  StreamSubscription<dynamic>? _recognitionSubscription;

  Stream<String> get resultsStream => _resultsController.stream;
  Stream<double> get audioLevelStream => _audioStreamService.audioLevelStream;
  bool get isPrepared => _speechRecognitionService.isPrepared;
  bool get isSessionActive => _speechRecognitionService.isSessionActive;

  Future<bool> requestPermission() {
    return _audioStreamService.requestPermission();
  }

  Future<void> prepare() {
    return _speechRecognitionService.prepare();
  }

  Future<void> startSession() async {
    if (!isPrepared) {
      throw StateError(
        'Сначала подготовьте модель вызовом prepare() перед стартом сессии.',
      );
    }
    if (!_speechRecognitionService.isListening) {
      await _speechRecognitionService.startListening();
    }
  }

  Future<void> stopSession() async {
    // WearVoiceSession owns the shared recorder; the cubit stops consuming results.
  }

  Future<void> dispose() async {
    await _recognitionSubscription?.cancel();
    await _resultsController.close();
    if (_ownsSpeechRecognitionService) {
      await _speechRecognitionService.dispose();
    }
  }

  void _onRecognitionResult(SegmentedRecognitionResult result) {
    if (result.lane != RecognitionLane.freeText ||
        result.kind != RecognitionKind.endpointResult &&
            result.kind != RecognitionKind.streamFinal) {
      return;
    }
    if (result.sourceScreen != _speechRecognitionService.sourceScreen ||
        _speechRecognitionService.captureEpoch > 0 &&
            result.captureEpoch != _speechRecognitionService.captureEpoch ||
        result.routeRevision != _speechRecognitionService.routeRevision ||
        result.grammarRevision != _speechRecognitionService.grammarRevision ||
        result.freeTextEpoch != _speechRecognitionService.freeTextEpoch ||
        result.listRevision !=
            _speechRecognitionService.currentDynamicItemsRevision) {
      return;
    }
    _onResolvedPhrase(result.text);
  }

  void _onResolvedPhraseEvent(WearVoicePhraseEvent event) {
    if (event.sourceScreen != _speechRecognitionService.sourceScreen ||
        _speechRecognitionService.captureEpoch > 0 &&
            event.captureEpoch != _speechRecognitionService.captureEpoch ||
        event.routeRevision != _speechRecognitionService.routeRevision ||
        event.grammarRevision != _speechRecognitionService.grammarRevision ||
        event.freeTextEpoch > 0 &&
            event.freeTextEpoch != _speechRecognitionService.freeTextEpoch ||
        event.listRevision > 0 &&
            event.listRevision !=
                _speechRecognitionService.currentDynamicItemsRevision) {
      return;
    }
    _onResolvedPhrase(event.phrase);
  }

  void _onResolvedPhrase(String phrase) {
    final output = _numberParserService.parseToNumber(phrase);
    if (!_resultsController.isClosed) {
      _resultsController.add(output);
    }
  }

  void _onRecognitionError(Object error, StackTrace stackTrace) {
    if (!_resultsController.isClosed) {
      _resultsController.addError(error, stackTrace);
    }
  }
}
