import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/voice_command_parser_service.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/wear_voice_command.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/wear_voice_control_service.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_typing/audio_stream_service.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_typing/segmented_recognition_result.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_typing/speech_recognition_service.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_typing/voice_device_profile.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_typing/voice_typing_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('voice typing reuses global listening without stopping it', () async {
    final _FakeSpeechRecognitionService speech = _FakeSpeechRecognitionService()
      ..listening = true;
    final VoiceTypingService service = VoiceTypingService(
      speechRecognitionService: speech,
      audioStreamService: _FakeAudioStreamService(),
    );

    await service.startSession();
    await service.stopSession();

    expect(speech.startListeningCalls, 0);
    expect(speech.stopListeningCalls, 0);
    await service.dispose();
    await speech.dispose();
  });

  group('segmented voice pipeline', () {
    late _FakeSpeechRecognitionService speech;
    late WearVoiceControlService service;
    late List<WearVoiceCommand> commands;
    late List<String> phrases;

    setUp(() {
      speech = _FakeSpeechRecognitionService();
      service = WearVoiceControlService(
        speechRecognitionService: speech,
        commandParserService: VoiceCommandParserService(),
      );
      commands = <WearVoiceCommand>[];
      phrases = <String>[];
      service.commandStream.listen(commands.add);
      service.phraseStream.listen(phrases.add);
    });

    tearDown(() async {
      await service.dispose();
      await speech.dispose();
    });

    test('command and free text from one segment execute once', () async {
      speech.emit(lane: RecognitionLane.freeText, text: 'вверх', segmentId: 1);
      speech.emit(lane: RecognitionLane.command, text: 'вверх', segmentId: 1);
      speech.end(segmentId: 1);
      await _settle();

      expect(commands, <WearVoiceCommand>[WearVoiceCommand.up]);
      expect(phrases, isEmpty);
    });

    test('previous-page grammar partial suppresses free-text "прошлое"',
        () async {
      speech.emit(
        lane: RecognitionLane.command,
        kind: RecognitionKind.partial,
        text: 'прошлая страница',
        segmentId: 3,
      );
      speech.emit(
          lane: RecognitionLane.freeText, text: 'прошлое', segmentId: 3);
      speech.end(segmentId: 3);
      await _settle();

      expect(commands, <WearVoiceCommand>[WearVoiceCommand.previousPage]);
      expect(phrases, isEmpty);
    });

    test('same command in the next segment executes again', () async {
      speech.emit(lane: RecognitionLane.command, text: 'вверх', segmentId: 1);
      speech.emit(lane: RecognitionLane.command, text: 'вверх', segmentId: 2);
      speech.end(segmentId: 1);
      speech.end(segmentId: 2);
      await _settle();

      expect(commands,
          <WearVoiceCommand>[WearVoiceCommand.up, WearVoiceCommand.up]);
    });

    test('free text first remains a phrase when it is not a command', () async {
      speech.emit(
          lane: RecognitionLane.freeText, text: 'чудо творожок', segmentId: 1);
      speech.emit(
          lane: RecognitionLane.command, text: 'неизвестно', segmentId: 1);
      speech.end(segmentId: 1);
      await _settle();

      expect(commands, isEmpty);
      expect(phrases, <String>['чудо творожок']);
    });

    test('no command leaves a free-text final available', () async {
      speech.emit(
          lane: RecognitionLane.freeText, text: 'без сахара', segmentId: 4);
      speech.end(segmentId: 4);
      await _settle();

      expect(commands, isEmpty);
      expect(phrases, <String>['без сахара']);
    });

    test('exact grammar partial executes and its final does not repeat',
        () async {
      speech.emit(
        lane: RecognitionLane.command,
        kind: RecognitionKind.partial,
        text: 'печать',
        segmentId: 7,
      );
      speech.emit(lane: RecognitionLane.command, text: 'печать', segmentId: 7);
      await _settle();

      expect(commands, <WearVoiceCommand>[WearVoiceCommand.print]);
    });

    test('stale capture epoch is discarded after a newer epoch', () async {
      speech.emit(
          lane: RecognitionLane.command, text: 'вверх', captureEpoch: 2);
      speech.emit(lane: RecognitionLane.command, text: 'вниз', captureEpoch: 1);
      await _settle();

      expect(commands, <WearVoiceCommand>[WearVoiceCommand.up]);
    });

    test('restart epoch cancels a late partial from the old capture', () async {
      speech.emit(lane: RecognitionLane.command, text: 'вниз', captureEpoch: 2);
      speech.emit(
        lane: RecognitionLane.command,
        kind: RecognitionKind.partial,
        text: 'вверх',
        captureEpoch: 1,
      );
      await _settle();

      expect(commands, <WearVoiceCommand>[WearVoiceCommand.down]);
    });
  });
}

Future<void> _settle() => Future<void>.delayed(Duration.zero);

class _FakeAudioStreamService implements AudioStreamService {
  @override
  double get audioLevel => 0;
  @override
  Stream<double> get audioLevelStream => const Stream<double>.empty();
  @override
  int get chunksReceived => 0;
  @override
  int get captureId => 0;
  @override
  int? get captureStartedAtMillis => null;
  @override
  VoiceDeviceProfile get deviceProfile => VoiceDeviceProfile.defaultProfile;
  @override
  bool get isRunning => false;
  @override
  int? get lastChunkAtMillis => null;
  @override
  int? get lastNonSilentChunkAtMillis => null;
  @override
  int? get continuousZeroAudioStartedAtMillis => null;
  @override
  void addDataCallback(void Function(Uint8List) callback) {}
  @override
  void removeDataCallback(void Function(Uint8List) callback) {}
  @override
  Future<String> diagnostics() async => 'fake';
  @override
  Future<void> dispose() async {}
  @override
  Future<void> recreateRecorder() async {}
  @override
  Future<void> pauseCallbacks() async {}
  @override
  Future<bool> requestPermission() async => true;
  @override
  Future<void> start({
    void Function(Uint8List bytes)? onData,
    void Function(Object error, StackTrace stackTrace)? onError,
  }) async {}
  @override
  Future<void> stop() async {}
}

class _FakeSpeechRecognitionService implements SpeechRecognitionService {
  final StreamController<SegmentedRecognitionResult> _results =
      StreamController<SegmentedRecognitionResult>.broadcast(sync: true);
  final StreamController<SpeechSegmentEnded> _ended =
      StreamController<SpeechSegmentEnded>.broadcast(sync: true);
  bool listening = false;
  int startListeningCalls = 0;
  int stopListeningCalls = 0;

  @override
  Stream<SegmentedRecognitionResult> get segmentedResultsStream =>
      _results.stream;
  @override
  Stream<SpeechSegmentEnded> get segmentEndedStream => _ended.stream;
  @override
  Never get audioStreamService => throw UnsupportedError('Not used in test');
  @override
  bool get isPrepared => true;
  @override
  bool get isSessionActive => false;
  @override
  bool get isListening => listening;
  @override
  bool get isCaptureRunning => false;
  @override
  bool get usesFreeTextRecognition => true;
  @override
  int? get lastAudioChunkAtMillis => null;
  @override
  int? get lastNonSilentAudioChunkAtMillis => null;
  @override
  int? get continuousZeroAudioStartedAtMillis => null;
  @override
  int get audioChunksReceived => 0;
  @override
  int get audioCaptureId => 0;
  @override
  int? get captureStartedAtMillis => null;
  @override
  VoiceDeviceProfile get deviceProfile => VoiceDeviceProfile.defaultProfile;

  void emit({
    required RecognitionLane lane,
    required String text,
    int captureEpoch = 1,
    int segmentId = 1,
    RecognitionKind kind = RecognitionKind.finalResult,
  }) {
    _results.add(SegmentedRecognitionResult(
      captureEpoch: captureEpoch,
      segmentId: segmentId,
      lane: lane,
      kind: kind,
      text: text,
      lastChunkId: segmentId,
      parsedCommand: lane == RecognitionLane.command
          ? VoiceCommandParserService().parseExact(text)
          : null,
    ));
  }

  void end({int captureEpoch = 1, required int segmentId}) {
    _ended.add(SpeechSegmentEnded(
      captureEpoch: captureEpoch,
      segmentId: segmentId,
      endChunkId: segmentId,
    ));
  }

  @override
  Future<bool> requestMicrophonePermission() async => true;
  @override
  Future<void> prepare() async {}
  @override
  Future<void> startSession() async {}
  @override
  Future<void> stopSession() async {}
  @override
  Future<void> startListening() async {
    startListeningCalls++;
    listening = true;
  }

  @override
  Future<void> stopListening() async {
    stopListeningCalls++;
    listening = false;
  }

  @override
  Future<void> restartListening({required String reason}) async {}
  @override
  Future<void> setFreeTextEnabled(bool enabled) async {}
  @override
  Future<String> diagnostics() async => 'fake';
  @override
  Future<void> processAudioChunk(Uint8List bytes) async {}
  @override
  Future<void> dispose() async {
    await _results.close();
    await _ended.close();
  }
}
