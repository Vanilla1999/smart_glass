import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/voice_command_parser_service.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/wear_voice_command.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/wear_voice_control_service.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_typing/audio_stream_service.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_typing/speech_recognition_service.dart';
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
    expect(speech.startSessionCalls, 0);
    await service.dispose();
    await speech.dispose();
  });

  group('WearVoiceControlService dedup', () {
    late _FakeSpeechRecognitionService speech;
    late int now;

    WearVoiceControlService createService() {
      now = 0;
      return WearVoiceControlService(
        speechRecognitionService: speech,
        commandParserService: VoiceCommandParserService(),
        clock: () => now,
      );
    }

    setUp(() {
      speech = _FakeSpeechRecognitionService();
    });

    tearDown(() {});

    test('emits command that is not a duplicate', () async {
      final WearVoiceControlService service = createService();
      final List<WearVoiceCommand> emitted = <WearVoiceCommand>[];
      service.commandStream.listen(emitted.add);

      now = 1000;
      speech.emitResult('вверх');
      await Future<void>.delayed(Duration.zero);

      expect(emitted, <WearVoiceCommand>[WearVoiceCommand.up]);
    });

    test('unsafe partial command waits for final result', () async {
      final WearVoiceControlService service = createService();
      final List<WearVoiceCommand> emitted = <WearVoiceCommand>[];
      service.commandStream.listen(emitted.add);

      now = 1000;
      speech.emitPartial('назад');
      await Future<void>.delayed(Duration.zero);

      expect(emitted, isEmpty);

      now = 1100;
      speech.emitResult('назад страница');
      await Future<void>.delayed(Duration.zero);

      expect(emitted, <WearVoiceCommand>[WearVoiceCommand.previousPage]);
    });

    test('overlapping print partial does not run before final command',
        () async {
      final WearVoiceControlService service = createService();
      final List<WearVoiceCommand> emitted = <WearVoiceCommand>[];
      service.commandStream.listen(emitted.add);

      now = 1000;
      speech.emitPartial('печать');
      await Future<void>.delayed(Duration.zero);
      expect(emitted, isEmpty);

      now = 1100;
      speech.emitResult('печать ценника');
      await Future<void>.delayed(Duration.zero);

      expect(emitted, <WearVoiceCommand>[WearVoiceCommand.openPrintPriceTag]);
    });

    test('partial command never executes before final result', () async {
      final WearVoiceControlService service = createService();
      final List<WearVoiceCommand> emitted = <WearVoiceCommand>[];
      service.commandStream.listen(emitted.add);

      now = 1000;
      speech.emitPartial('вверх');
      await Future<void>.delayed(Duration.zero);
      expect(emitted, isEmpty);

      now = 1100;
      speech.emitResult('вверх');
      await Future<void>.delayed(Duration.zero);

      expect(emitted, <WearVoiceCommand>[WearVoiceCommand.up]);
    });

    test('corrected final is the only command that executes', () async {
      final WearVoiceControlService service = createService();
      final List<WearVoiceCommand> emitted = <WearVoiceCommand>[];
      service.commandStream.listen(emitted.add);

      now = 1000;
      speech.emitPartial('да');
      await Future<void>.delayed(Duration.zero);
      expect(emitted, isEmpty);

      now = 1400;
      speech.emitResult('далее');
      await Future<void>.delayed(Duration.zero);

      expect(emitted, <WearVoiceCommand>[WearVoiceCommand.nextPage]);
    });

    test('free-text phrase containing command token stays a phrase', () async {
      final WearVoiceControlService service = createService();
      final List<WearVoiceCommand> commands = <WearVoiceCommand>[];
      final List<String> phrases = <String>[];
      service.commandStream.listen(commands.add);
      service.phraseStream.listen(phrases.add);

      now = 1000;
      speech.emitResult('сбер продукт');
      await Future<void>.delayed(Duration.zero);

      expect(commands, isEmpty);
      expect(phrases, <String>['сбер продукт']);
    });

    test('final alone without prior partial emits', () async {
      final WearVoiceControlService service = createService();
      final List<WearVoiceCommand> emitted = <WearVoiceCommand>[];
      service.commandStream.listen(emitted.add);

      now = 1000;
      speech.emitResult('выбрать');
      await Future<void>.delayed(Duration.zero);

      expect(emitted, <WearVoiceCommand>[WearVoiceCommand.select]);
    });

    test('final unknown text emits free phrase', () async {
      final WearVoiceControlService service = createService();
      final List<String> emitted = <String>[];
      service.phraseStream.listen(emitted.add);

      now = 1000;
      speech.emitResult('чудо творожок');
      await Future<void>.delayed(Duration.zero);

      expect(emitted, <String>['чудо творожок']);
    });

    test('partial unknown text emits partial phrase only', () async {
      final WearVoiceControlService service = createService();
      final List<String> phrases = <String>[];
      final List<String> partialPhrases = <String>[];
      service.phraseStream.listen(phrases.add);
      service.partialPhraseStream.listen(partialPhrases.add);

      now = 1000;
      speech.emitPartial('безалкогольное');
      await Future<void>.delayed(Duration.zero);

      expect(phrases, isEmpty);
      expect(partialPhrases, <String>['безалкогольное']);
    });

    test('short partial unknown text does not emit partial phrase', () async {
      final WearVoiceControlService service = createService();
      final List<String> partialPhrases = <String>[];
      service.partialPhraseStream.listen(partialPhrases.add);

      now = 1000;
      speech.emitPartial('чудо');
      await Future<void>.delayed(Duration.zero);

      expect(partialPhrases, isEmpty);
    });

    test('duplicate partial phrase is throttled', () async {
      final WearVoiceControlService service = createService();
      final List<String> partialPhrases = <String>[];
      service.partialPhraseStream.listen(partialPhrases.add);

      now = 1000;
      speech.emitPartial('безалкогольное');
      await Future<void>.delayed(Duration.zero);

      now = 1100;
      speech.emitPartial('безалкогольное');
      await Future<void>.delayed(Duration.zero);

      now = 1400;
      speech.emitPartial('безалкогольное');
      await Future<void>.delayed(Duration.zero);

      expect(partialPhrases, <String>['безалкогольное', 'безалкогольное']);
    });
  });
}

class _FakeAudioStreamService implements AudioStreamService {
  @override
  double get audioLevel => 0;

  @override
  Stream<double> get audioLevelStream => const Stream<double>.empty();

  @override
  int get chunksReceived => 0;

  @override
  bool get isRunning => false;

  @override
  int? get lastChunkAtMillis => null;

  @override
  int? get lastNonSilentChunkAtMillis => null;

  @override
  void addDataCallback(void Function(Uint8List) callback) {}

  @override
  void removeDataCallback(void Function(Uint8List) callback) {}

  @override
  Future<String> diagnostics() async => 'fake';

  @override
  Future<void> dispose() async {}

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
  final StreamController<String> _resultsController =
      StreamController<String>.broadcast();
  final StreamController<String> _partialController =
      StreamController<String>.broadcast();
  bool listening = false;
  int startListeningCalls = 0;
  int stopListeningCalls = 0;
  int startSessionCalls = 0;

  @override
  Never get audioStreamService => throw UnsupportedError('Not used in test');

  @override
  Stream<String> get resultsStream => _resultsController.stream;

  @override
  Stream<String> get partialResultsStream => _partialController.stream;

  @override
  bool get isPrepared => true;

  @override
  bool get isSessionActive => false;

  @override
  bool get isListening => listening;

  @override
  bool get usesFreeTextRecognition => true;

  @override
  int? get lastAudioChunkAtMillis => null;

  @override
  int? get lastNonSilentAudioChunkAtMillis => null;

  void emitResult(String text) {
    _resultsController.add(text);
  }

  void emitPartial(String text) {
    _partialController.add(text);
  }

  @override
  Future<bool> requestMicrophonePermission() async => true;

  @override
  Future<void> prepare() async {}

  @override
  Future<void> startSession() async {
    startSessionCalls++;
  }

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
  Future<void> setRecognitionGrammar(List<String>? grammar) async {}

  @override
  Future<String> diagnostics() async => 'fake';

  @override
  Future<void> processAudioChunk(Uint8List bytes) async {}

  @override
  Future<void> dispose() async {
    await _resultsController.close();
    await _partialController.close();
  }
}
