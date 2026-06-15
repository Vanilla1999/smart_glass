import 'dart:async';
import 'dart:typed_data';

import 'package:smart_glasses/modules/wear/domain/service/voice_typing/audio_stream_service.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_typing/number_parser_service.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_typing/speech_recognition_service.dart';

class VoiceTypingService {
  VoiceTypingService({
    AudioStreamService? audioStreamService,
    SpeechRecognitionService? speechRecognitionService,
    NumberParserService? numberParserService,
  })  : _audioStreamService = audioStreamService ?? AudioStreamService(),
        _speechRecognitionService =
            speechRecognitionService ?? SpeechRecognitionService(),
        _numberParserService = numberParserService ?? NumberParserService() {
    _recognitionSubscription = _speechRecognitionService.resultsStream.listen(
      _onRecognitionResult,
      onError: _onRecognitionError,
    );
  }

  final AudioStreamService _audioStreamService;
  final SpeechRecognitionService _speechRecognitionService;
  final NumberParserService _numberParserService;
  final StreamController<String> _resultsController =
      StreamController<String>.broadcast();

  StreamSubscription<String>? _recognitionSubscription;
  Future<void> _audioProcessing = Future<void>.value();

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
    print('[STARTING SESSION]');
    await _speechRecognitionService.startSession();
    await _audioStreamService.start(
      onData: _onAudioChunk,
      onError: _onAudioError,
    );
  }

  Future<void> stopSession() async {
    await _audioStreamService.pauseCallbacks();
    await _audioProcessing;
    await _speechRecognitionService.stopSession();
  }

  Future<void> dispose() async {
    try {
      await stopSession();
    } finally {
      await _recognitionSubscription?.cancel();
      await _resultsController.close();
    }
  }

  void _onAudioChunk(Uint8List bytes) {
    // print('GOT CHUNK');
    _audioProcessing = _audioProcessing
        .then((_) => _speechRecognitionService.processAudioChunk(bytes))
        .catchError((Object error, StackTrace stackTrace) {
      _onProcessingError(error, stackTrace);
    });
  }

  void _onAudioError(Object error, StackTrace stackTrace) {
    _onProcessingError(error, stackTrace);
  }

  void _onProcessingError(Object error, StackTrace stackTrace) {
    if (!_resultsController.isClosed) {
      _resultsController.addError(error, stackTrace);
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
