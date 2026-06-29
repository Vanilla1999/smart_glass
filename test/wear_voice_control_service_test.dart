import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/voice_command_parser_service.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/wear_voice_command.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/wear_voice_control_service.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_typing/speech_recognition_service.dart';

void main() {
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

    test('partial command emits once', () async {
      final WearVoiceControlService service = createService();
      final List<WearVoiceCommand> emitted = <WearVoiceCommand>[];
      service.commandStream.listen(emitted.add);

      now = 1000;
      speech.emitPartial('назад');
      await Future<void>.delayed(Duration.zero);

      expect(emitted, <WearVoiceCommand>[WearVoiceCommand.back]);
    });

    test('duplicate partial within 1200ms is suppressed', () async {
      final WearVoiceControlService service = createService();
      final List<WearVoiceCommand> emitted = <WearVoiceCommand>[];
      service.commandStream.listen(emitted.add);

      now = 1000;
      speech.emitPartial('вверх');
      await Future<void>.delayed(Duration.zero);
      expect(emitted, <WearVoiceCommand>[WearVoiceCommand.up]);

      now = 1100;
      speech.emitPartial('вверх');
      await Future<void>.delayed(Duration.zero);

      expect(emitted, <WearVoiceCommand>[WearVoiceCommand.up]);
    });

    test('final same as last emitted partial is suppressed', () async {
      final WearVoiceControlService service = createService();
      final List<WearVoiceCommand> emitted = <WearVoiceCommand>[];
      service.commandStream.listen(emitted.add);

      now = 1000;
      speech.emitPartial('вниз');
      await Future<void>.delayed(Duration.zero);
      expect(emitted, <WearVoiceCommand>[WearVoiceCommand.down]);

      now = 1400;
      speech.emitResult('вниз');
      await Future<void>.delayed(Duration.zero);

      expect(emitted, <WearVoiceCommand>[WearVoiceCommand.down]);
    });

    test('final different from last emitted partial passes through', () async {
      final WearVoiceControlService service = createService();
      final List<WearVoiceCommand> emitted = <WearVoiceCommand>[];
      service.commandStream.listen(emitted.add);

      now = 1000;
      speech.emitPartial('вверх');
      await Future<void>.delayed(Duration.zero);

      now = 1050;
      speech.emitResult('вниз');
      await Future<void>.delayed(Duration.zero);

      expect(
        emitted,
        <WearVoiceCommand>[WearVoiceCommand.up, WearVoiceCommand.down],
      );
    });

    test('final same as recent emitted partial is suppressed', () async {
      final WearVoiceControlService service = createService();
      final List<WearVoiceCommand> emitted = <WearVoiceCommand>[];
      service.commandStream.listen(emitted.add);

      now = 1000;
      speech.emitPartial('вниз');
      await Future<void>.delayed(Duration.zero);
      expect(emitted, <WearVoiceCommand>[WearVoiceCommand.down]);

      now = 2400;
      speech.emitResult('вниз');
      await Future<void>.delayed(Duration.zero);

      expect(emitted, <WearVoiceCommand>[WearVoiceCommand.down]);
    });

    test('final same as stale emitted partial is emitted again', () async {
      final WearVoiceControlService service = createService();
      final List<WearVoiceCommand> emitted = <WearVoiceCommand>[];
      service.commandStream.listen(emitted.add);

      now = 1000;
      speech.emitPartial('вниз');
      await Future<void>.delayed(Duration.zero);
      expect(emitted, <WearVoiceCommand>[WearVoiceCommand.down]);

      now = 3000;
      speech.emitResult('вниз');
      await Future<void>.delayed(Duration.zero);

      expect(
        emitted,
        <WearVoiceCommand>[WearVoiceCommand.down, WearVoiceCommand.down],
      );
    });

    test('partial after 1200ms is emitted as new command', () async {
      final WearVoiceControlService service = createService();
      final List<WearVoiceCommand> emitted = <WearVoiceCommand>[];
      service.commandStream.listen(emitted.add);

      now = 1000;
      speech.emitPartial('вниз');
      await Future<void>.delayed(Duration.zero);
      expect(emitted, <WearVoiceCommand>[WearVoiceCommand.down]);

      now = 2500;
      speech.emitPartial('вниз');
      await Future<void>.delayed(Duration.zero);

      expect(
        emitted,
        <WearVoiceCommand>[WearVoiceCommand.down, WearVoiceCommand.down],
      );
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

class _FakeSpeechRecognitionService implements SpeechRecognitionService {
  final StreamController<String> _resultsController =
      StreamController<String>.broadcast();
  final StreamController<String> _partialController =
      StreamController<String>.broadcast();

  @override
  Stream<String> get resultsStream => _resultsController.stream;

  @override
  Stream<String> get partialResultsStream => _partialController.stream;

  @override
  bool get isPrepared => true;

  @override
  bool get isSessionActive => false;

  @override
  bool get isListening => false;

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
  Future<void> startSession() async {}

  @override
  Future<void> stopSession() async {}

  @override
  Future<void> startListening() async {}

  @override
  Future<void> stopListening() async {}

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
