import 'dart:async';

import 'package:smart_glasses/modules/wear/domain/service/voice_typing/audio_stream_service.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_typing/number_parser_service.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_typing/speech_recognition_service.dart';

class VoiceTypingService {
  factory VoiceTypingService({
    AudioStreamService? audioStreamService,
    SpeechRecognitionService? speechRecognitionService,
    NumberParserService? numberParserService,
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
    );
  }

  VoiceTypingService._({
    required AudioStreamService audioStreamService,
    required SpeechRecognitionService speechRecognitionService,
    required NumberParserService numberParserService,
    required bool ownsSpeechRecognitionService,
  })  : _audioStreamService = audioStreamService,
        _speechRecognitionService = speechRecognitionService,
        _numberParserService = numberParserService,
        _ownsSpeechRecognitionService = ownsSpeechRecognitionService {
    _recognitionSubscription = _speechRecognitionService.resultsStream.listen(
      _onRecognitionResult,
      onError: _onRecognitionError,
    );
  }

  final AudioStreamService _audioStreamService;
  final SpeechRecognitionService _speechRecognitionService;
  final NumberParserService _numberParserService;
  final bool _ownsSpeechRecognitionService;
  final StreamController<String> _resultsController =
      StreamController<String>.broadcast();

  StreamSubscription<String>? _recognitionSubscription;

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

  void _onRecognitionResult(String resultText) {
    final output = _numberParserService.parseToNumber(resultText);
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
