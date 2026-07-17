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
      speech.emitCommandResult('вверх');
      await Future<void>.delayed(Duration.zero);

      expect(emitted, <WearVoiceCommand>[WearVoiceCommand.up]);
    });

    test('fixed command emits immediately from grammar partial', () async {
      final WearVoiceControlService service = createService();
      final List<WearVoiceCommand> emitted = <WearVoiceCommand>[];
      service.commandStream.listen(emitted.add);

      now = 1000;
      speech.emitCommandPartial('да');
      await Future<void>.delayed(Duration.zero);

      expect(emitted, <WearVoiceCommand>[WearVoiceCommand.yes]);

      now = 1100;
      speech.emitCommandResult('да');
      await Future<void>.delayed(Duration.zero);

      expect(emitted, <WearVoiceCommand>[WearVoiceCommand.yes]);
    });

    test('print command emits from partial and matching final is suppressed',
        () async {
      final WearVoiceControlService service = createService();
      final List<WearVoiceCommand> emitted = <WearVoiceCommand>[];
      service.commandStream.listen(emitted.add);

      now = 1000;
      speech.emitCommandPartial('печать');
      await Future<void>.delayed(Duration.zero);
      expect(emitted, <WearVoiceCommand>[WearVoiceCommand.print]);

      now = 1100;
      speech.emitCommandResult('печать');
      await Future<void>.delayed(Duration.zero);

      expect(emitted, <WearVoiceCommand>[WearVoiceCommand.print]);
    });

    test('free-text command never executes', () async {
      final WearVoiceControlService service = createService();
      final List<WearVoiceCommand> emitted = <WearVoiceCommand>[];
      service.commandStream.listen(emitted.add);

      now = 1000;
      speech.emitFreeTextPartial('вверх');
      await Future<void>.delayed(Duration.zero);
      expect(emitted, isEmpty);

      now = 1100;
      speech.emitFreeTextResult('вверх');
      await Future<void>.delayed(Duration.zero);

      expect(emitted, isEmpty);
    });

    test(
        'grammar partial command emits immediately and matching final is suppressed',
        () async {
      final WearVoiceControlService service = createService();
      final List<WearVoiceCommand> emitted = <WearVoiceCommand>[];
      service.commandStream.listen(emitted.add);

      now = 1000;
      speech.emitCommandPartial('вверх');
      await Future<void>.delayed(Duration.zero);

      expect(emitted, <WearVoiceCommand>[WearVoiceCommand.up]);

      now = 1600;
      speech.emitCommandResult('вверх');
      await Future<void>.delayed(Duration.zero);

      expect(emitted, <WearVoiceCommand>[WearVoiceCommand.up]);
    });

    test('grammar corrected final is suppressed after emitted partial',
        () async {
      final WearVoiceControlService service = createService();
      final List<WearVoiceCommand> emitted = <WearVoiceCommand>[];
      service.commandStream.listen(emitted.add);

      now = 1000;
      speech.emitCommandPartial('да');
      await Future<void>.delayed(Duration.zero);

      now = 1400;
      speech.emitCommandResult('далее');
      await Future<void>.delayed(Duration.zero);

      expect(
        emitted,
        <WearVoiceCommand>[WearVoiceCommand.yes],
      );
    });

    test('corrected final does not execute a second command', () async {
      final WearVoiceControlService service = createService();
      final List<WearVoiceCommand> emitted = <WearVoiceCommand>[];
      service.commandStream.listen(emitted.add);

      now = 1000;
      speech.emitCommandPartial('да');
      await Future<void>.delayed(Duration.zero);
      expect(emitted, <WearVoiceCommand>[WearVoiceCommand.yes]);

      now = 1400;
      speech.emitCommandResult('далее');
      await Future<void>.delayed(Duration.zero);

      expect(
        emitted,
        <WearVoiceCommand>[WearVoiceCommand.yes],
      );
    });

    test('free-text phrase containing command token stays a phrase', () async {
      final WearVoiceControlService service = createService();
      final List<WearVoiceCommand> commands = <WearVoiceCommand>[];
      final List<String> phrases = <String>[];
      service.commandStream.listen(commands.add);
      service.phraseStream.listen(phrases.add);

      now = 1000;
      speech.emitFreeTextResult('сбер продукт');
      await Future<void>.delayed(Duration.zero);

      expect(commands, isEmpty);
      expect(phrases, <String>['сбер продукт']);
    });

    test('final alone without prior partial emits', () async {
      final WearVoiceControlService service = createService();
      final List<WearVoiceCommand> emitted = <WearVoiceCommand>[];
      service.commandStream.listen(emitted.add);

      now = 1000;
      speech.emitCommandResult('выбрать');
      await Future<void>.delayed(Duration.zero);

      expect(emitted, <WearVoiceCommand>[WearVoiceCommand.select]);
    });

    test('final unknown text emits free phrase', () async {
      final WearVoiceControlService service = createService();
      final List<String> emitted = <String>[];
      service.phraseStream.listen(emitted.add);

      now = 1000;
      speech.emitFreeTextResult('чудо творожок');
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
      speech.emitFreeTextPartial('безалкогольное');
      await Future<void>.delayed(Duration.zero);

      expect(phrases, isEmpty);
      expect(partialPhrases, <String>['безалкогольное']);
    });

    test('short partial unknown text does not emit partial phrase', () async {
      final WearVoiceControlService service = createService();
      final List<String> partialPhrases = <String>[];
      service.partialPhraseStream.listen(partialPhrases.add);

      now = 1000;
      speech.emitFreeTextPartial('чудо');
      await Future<void>.delayed(Duration.zero);

      expect(partialPhrases, isEmpty);
    });

    test('duplicate partial phrase is throttled', () async {
      final WearVoiceControlService service = createService();
      final List<String> partialPhrases = <String>[];
      service.partialPhraseStream.listen(partialPhrases.add);

      now = 1000;
      speech.emitFreeTextPartial('безалкогольное');
      await Future<void>.delayed(Duration.zero);

      now = 1100;
      speech.emitFreeTextPartial('безалкогольное');
      await Future<void>.delayed(Duration.zero);

      now = 1400;
      speech.emitFreeTextPartial('безалкогольное');
      await Future<void>.delayed(Duration.zero);

      expect(partialPhrases, <String>['безалкогольное', 'безалкогольное']);
    });

    test('dual recognition emits a command only once', () async {
      final WearVoiceControlService service = createService();
      final List<WearVoiceCommand> commands = <WearVoiceCommand>[];
      service.commandStream.listen(commands.add);

      now = 1000;
      speech.emitCommandPartial('вниз');
      speech.emitFreeTextPartial('вниз');
      await Future<void>.delayed(Duration.zero);

      now = 1500;
      speech.emitCommandResult('вниз');
      speech.emitFreeTextResult('вниз');
      await Future<void>.delayed(Duration.zero);

      expect(commands, <WearVoiceCommand>[WearVoiceCommand.down]);
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
  final StreamController<String> _commandResultsController =
      StreamController<String>.broadcast();
  final StreamController<String> _commandPartialController =
      StreamController<String>.broadcast();
  final StreamController<String> _freeTextResultsController =
      StreamController<String>.broadcast();
  final StreamController<String> _freeTextPartialController =
      StreamController<String>.broadcast();
  bool listening = false;
  bool freeTextEnabled = true;
  int startListeningCalls = 0;
  int stopListeningCalls = 0;
  int startSessionCalls = 0;

  @override
  Never get audioStreamService => throw UnsupportedError('Not used in test');

  @override
  Stream<String> get commandResultsStream => _commandResultsController.stream;

  @override
  Stream<String> get commandPartialResultsStream =>
      _commandPartialController.stream;

  @override
  Stream<String> get freeTextResultsStream => _freeTextResultsController.stream;

  @override
  Stream<String> get freeTextPartialResultsStream =>
      _freeTextPartialController.stream;

  @override
  bool get isPrepared => true;

  @override
  bool get isSessionActive => false;

  @override
  bool get isListening => listening;

  @override
  bool get usesFreeTextRecognition => freeTextEnabled;

  @override
  int? get lastAudioChunkAtMillis => null;

  @override
  int? get lastNonSilentAudioChunkAtMillis => null;

  @override
  int? get continuousZeroAudioStartedAtMillis => null;

  void emitCommandResult(String text) {
    _commandResultsController.add(text);
  }

  void emitCommandPartial(String text) {
    _commandPartialController.add(text);
  }

  void emitFreeTextResult(String text) {
    _freeTextResultsController.add(text);
  }

  void emitFreeTextPartial(String text) {
    _freeTextPartialController.add(text);
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
  Future<void> setFreeTextEnabled(bool enabled) async {
    freeTextEnabled = enabled;
  }

  @override
  Future<String> diagnostics() async => 'fake';

  @override
  Future<void> processAudioChunk(Uint8List bytes) async {}

  @override
  Future<void> dispose() async {
    await _commandResultsController.close();
    await _commandPartialController.close();
    await _freeTextResultsController.close();
    await _freeTextPartialController.close();
  }
}
