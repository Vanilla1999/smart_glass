import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/voice_command_parser_service.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/voice_action_catalog.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/wear_voice_command.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/wear_voice_control_service.dart';
import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
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
    late List<String?> previews;

    setUp(() {
      speech = _FakeSpeechRecognitionService();
      service = WearVoiceControlService(
        speechRecognitionService: speech,
        commandParserService: VoiceCommandParserService(),
      );
      commands = <WearVoiceCommand>[];
      phrases = <String>[];
      previews = <String?>[];
      service.commandStream.listen(commands.add);
      service.phraseStream.listen(phrases.add);
      service.freeTextPreviewStream.listen(previews.add);
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

    test('free-text partial cannot change UI before grammar resolves',
        () async {
      speech.emit(
        lane: RecognitionLane.command,
        kind: RecognitionKind.partial,
        text: 'прошлая страница',
        segmentId: 3,
      );
      speech.emit(
          lane: RecognitionLane.freeText, text: 'прошлое', segmentId: 3);
      expect(previews, isEmpty);
      speech.emit(
        lane: RecognitionLane.command,
        text: 'прошлая страница',
        segmentId: 3,
      );
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

    test('grammar final commits after a non-executing partial', () async {
      WearScreenId screen = WearScreenId.printerSelect;
      await service.dispose();
      service = WearVoiceControlService(
        speechRecognitionService: speech,
        screenProvider: () => screen,
      );
      commands = <WearVoiceCommand>[];
      service.commandStream.listen(commands.add);
      speech.emit(
        lane: RecognitionLane.command,
        kind: RecognitionKind.partial,
        text: 'печать',
        segmentId: 7,
      );
      speech.emit(lane: RecognitionLane.command, text: 'печать', segmentId: 7);
      speech.end(segmentId: 7);
      await _settle();

      expect(commands, <WearVoiceCommand>[WearVoiceCommand.print]);
    });

    test('exact fast alias executes immediately and final does not repeat',
        () async {
      WearScreenId screen = WearScreenId.availabilityInteraction;
      await service.dispose();
      service = WearVoiceControlService(
        speechRecognitionService: speech,
        screenProvider: () => screen,
      );
      commands = <WearVoiceCommand>[];
      service.commandStream.listen(commands.add);

      speech.emit(
        lane: RecognitionLane.command,
        kind: RecognitionKind.partial,
        text: 'прямое',
        segmentId: 8,
      );
      await _settle();
      expect(commands, <WearVoiceCommand>[WearVoiceCommand.openDirectScan]);

      speech.emit(
        lane: RecognitionLane.command,
        text: 'прямое сканирование',
        segmentId: 8,
      );
      speech.emit(
        lane: RecognitionLane.freeText,
        text: 'прямое сканирование',
        segmentId: 8,
      );
      speech.end(segmentId: 8);
      await _settle();

      expect(commands, <WearVoiceCommand>[WearVoiceCommand.openDirectScan]);
      expect(phrases, isEmpty);
    });

    test('segment context uses the screen at VAD start', () async {
      WearScreenId screen = WearScreenId.availabilityInteraction;
      await service.dispose();
      service = WearVoiceControlService(
        speechRecognitionService: speech,
        screenProvider: () => screen,
      );
      commands = <WearVoiceCommand>[];
      service.commandStream.listen(commands.add);

      speech.start(segmentId: 12);
      screen = WearScreenId.productSelect;
      speech.emit(
        lane: RecognitionLane.command,
        kind: RecognitionKind.partial,
        text: 'прямое',
        segmentId: 12,
      );
      await _settle();

      expect(commands, <WearVoiceCommand>[WearVoiceCommand.openDirectScan]);
    });

    test('free-text partial is preview-only and a command clears it', () async {
      WearScreenId screen = WearScreenId.availabilityInteraction;
      await service.dispose();
      service = WearVoiceControlService(
        speechRecognitionService: speech,
        screenProvider: () => screen,
      );
      previews = <String?>[];
      phrases = <String>[];
      service.freeTextPreviewStream.listen(previews.add);
      service.phraseStream.listen(phrases.add);

      speech.start(segmentId: 13);
      speech.emit(
        lane: RecognitionLane.freeText,
        kind: RecognitionKind.partial,
        text: 'прямое молоко',
        segmentId: 13,
      );
      speech.emit(
        lane: RecognitionLane.command,
        kind: RecognitionKind.partial,
        text: 'прямое',
        segmentId: 13,
      );
      await _settle();

      expect(previews, <String?>['прямое молоко', null]);
      expect(phrases, isEmpty);
    });

    test('different final after a fast alias does not execute twice', () async {
      WearScreenId screen = WearScreenId.menu;
      await service.dispose();
      service = WearVoiceControlService(
        speechRecognitionService: speech,
        screenProvider: () => screen,
      );
      commands = <WearVoiceCommand>[];
      service.commandStream.listen(commands.add);

      speech.emit(
        lane: RecognitionLane.command,
        kind: RecognitionKind.partial,
        text: 'вверх',
        segmentId: 10,
      );
      speech.emit(
        lane: RecognitionLane.command,
        text: 'вниз',
        segmentId: 10,
      );
      speech.end(segmentId: 10);
      await _settle();

      expect(commands, <WearVoiceCommand>[WearVoiceCommand.up]);
    });

    test('menu print final resolves to opening the print section', () async {
      speech.emit(
        lane: RecognitionLane.command,
        text: 'печать',
        segmentId: 11,
      );
      speech.end(segmentId: 11);
      await _settle();

      expect(commands, <WearVoiceCommand>[WearVoiceCommand.openPrintPriceTag]);
    });

    test('alias from another screen remains available to free text', () async {
      WearScreenId screen = WearScreenId.productSelect;
      await service.dispose();
      service = WearVoiceControlService(
        speechRecognitionService: speech,
        screenProvider: () => screen,
      );
      commands = <WearVoiceCommand>[];
      phrases = <String>[];
      service.commandStream.listen(commands.add);
      service.phraseStream.listen(phrases.add);

      speech.emit(
        lane: RecognitionLane.command,
        kind: RecognitionKind.partial,
        text: 'прямое',
        segmentId: 9,
      );
      speech.emit(
        lane: RecognitionLane.freeText,
        text: 'прямое молоко',
        segmentId: 9,
      );
      speech.end(segmentId: 9);
      await _settle();

      expect(commands, isEmpty);
      expect(phrases, <String>['прямое молоко']);
    });

    test('catalog rejects duplicate immediate aliases on one screen', () {
      expect(
        () => VoiceActionCatalog(actions: <VoiceActionEntry>[
          VoiceActionEntry(
            command: WearVoiceCommand.openList,
            screens: <WearScreenId>{WearScreenId.menu},
            fullPhrases: <String>{'список'},
            fastAliases: <String>{'список'},
            activationPolicy: VoiceActivationPolicy.immediateExactPartial,
          ),
          VoiceActionEntry(
            command: WearVoiceCommand.openHelp,
            screens: <WearScreenId>{WearScreenId.menu},
            fullPhrases: <String>{'список помощи'},
            fastAliases: <String>{'список'},
            activationPolicy: VoiceActivationPolicy.immediateExactPartial,
          ),
        ]),
        throwsArgumentError,
      );
    });

    test('catalog resolves every agreed fast action alias', () {
      final VoiceActionCatalog catalog = VoiceActionCatalog();

      expect(
        catalog.resolveFastAlias(WearScreenId.menu, 'печать'),
        WearVoiceCommand.openPrintPriceTag,
      );
      expect(
        catalog.resolveFastAlias(WearScreenId.menu, 'ценник'),
        WearVoiceCommand.openPrintPriceTag,
      );
      expect(
        catalog.resolveFastAlias(
          WearScreenId.availabilityInteraction,
          'список',
        ),
        WearVoiceCommand.openList,
      );
      expect(
        catalog.resolveFastAlias(
          WearScreenId.availabilityInteraction,
          'товары',
        ),
        WearVoiceCommand.openList,
      );
      expect(
        catalog.resolveFastAlias(
          WearScreenId.availabilityInteraction,
          'прямое',
        ),
        WearVoiceCommand.openDirectScan,
      );
      expect(
        catalog.resolveFastAlias(
          WearScreenId.availabilityInteraction,
          'сканирование',
        ),
        WearVoiceCommand.openDirectScan,
      );
      expect(
        catalog.resolveFastAlias(WearScreenId.productSelect, 'фото'),
        WearVoiceCommand.takePhoto,
      );
    });

    test('stale capture epoch is discarded after a newer epoch', () async {
      speech.emit(
          lane: RecognitionLane.command, text: 'вверх', captureEpoch: 2);
      speech.emit(lane: RecognitionLane.command, text: 'вниз', captureEpoch: 1);
      speech.end(segmentId: 1, captureEpoch: 2);
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
      speech.end(segmentId: 1, captureEpoch: 2);
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
  void addPcmCallback(
      void Function(Uint8List raw, Uint8List boosted) callback) {}
  @override
  void removePcmCallback(
    void Function(Uint8List raw, Uint8List boosted) callback,
  ) {}
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
  @override
  void useDeviceProfile(VoiceDeviceProfile profile) {}
}

class _FakeSpeechRecognitionService implements SpeechRecognitionService {
  final StreamController<SegmentedRecognitionResult> _results =
      StreamController<SegmentedRecognitionResult>.broadcast(sync: true);
  final StreamController<SpeechSegmentEnded> _ended =
      StreamController<SpeechSegmentEnded>.broadcast(sync: true);
  final StreamController<SpeechSegmentStarted> _started =
      StreamController<SpeechSegmentStarted>.broadcast(sync: true);
  final Set<String> _startedSegments = <String>{};
  bool listening = false;
  int startListeningCalls = 0;
  int stopListeningCalls = 0;

  @override
  Stream<SegmentedRecognitionResult> get segmentedResultsStream =>
      _results.stream;
  @override
  Stream<SpeechSegmentEnded> get segmentEndedStream => _ended.stream;
  @override
  Stream<SpeechSegmentStarted> get segmentStartedStream => _started.stream;
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
  @override
  void useDeviceProfile(VoiceDeviceProfile profile) {}

  void emit({
    required RecognitionLane lane,
    required String text,
    int captureEpoch = 1,
    int segmentId = 1,
    RecognitionKind kind = RecognitionKind.finalResult,
  }) {
    start(captureEpoch: captureEpoch, segmentId: segmentId);
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

  void start({int captureEpoch = 1, required int segmentId}) {
    final String key = '$captureEpoch:$segmentId';
    if (!_startedSegments.add(key)) return;
    _started.add(SpeechSegmentStarted(
      captureEpoch: captureEpoch,
      segmentId: segmentId,
      startChunkId: segmentId,
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
    await _started.close();
    await _ended.close();
  }
}
