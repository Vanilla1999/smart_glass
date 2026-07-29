import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_typing/segmented_recognition_result.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_typing/speech_recognition_service.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_typing/speech_segmenter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('setGrammar failure keeps active screen and revisions', () async {
    final _FakeRecognizer command = _FakeRecognizer();
    final SpeechRecognitionService service = _service(command: command);
    addTearDown(service.dispose);
    await service.prepare();

    await service.switchCommandGrammar(
      screen: WearScreenId.help,
      grammar: const <String>['назад', '[unk]'],
    );
    final int routeRevision = service.routeRevision;
    final int grammarRevision = service.grammarRevision;
    command.failNextGrammar = true;

    await expectLater(
      service.switchCommandGrammar(
        screen: WearScreenId.settings,
        grammar: const <String>['сохранить', '[unk]'],
      ),
      throwsStateError,
    );

    expect(service.routeRevision, routeRevision);
    expect(service.grammarRevision, grammarRevision);
  });

  test('setGrammar failure recovers before the next successful command',
      () async {
    final _FakeRecognizer failed = _FakeRecognizer();
    final _FakeRecognizer recovered = _FakeRecognizer()
      ..endpointSequence.add(true)
      ..resultSequence.add(_json(text: 'сохранить'));
    final List<_FakeRecognizer> recognizers = <_FakeRecognizer>[
      failed,
      recovered,
    ];
    final SpeechRecognitionService service = SpeechRecognitionService(
      commandGrammar: const <String>['вверх', '[unk]'],
      speechSegmenter: SpeechSegmenter(calibrationDuration: Duration.zero),
      recognizerFactory: (RecognitionLane lane, List<String> grammar) async =>
          recognizers.removeAt(0),
    );
    addTearDown(service.dispose);
    await service.prepare();
    failed.failNextGrammar = true;

    await expectLater(
      service.switchCommandGrammar(
        screen: WearScreenId.help,
        grammar: const <String>['назад', '[unk]'],
      ),
      throwsStateError,
    );
    await service.switchCommandGrammar(
      screen: WearScreenId.settings,
      grammar: const <String>['сохранить', '[unk]'],
    );
    await service.startSession();
    service.beginProcessingCapture();
    final Future<SegmentedRecognitionResult> result = service
        .segmentedResultsStream
        .firstWhere((event) => event.kind == RecognitionKind.endpointResult);
    await service.processAudioChunk(_pcmFrame(1000));

    expect((await result).text, 'сохранить');
    expect(recovered.grammars.last, const <String>['сохранить', '[unk]']);
    expect(service.routeRevision, 1);
    expect(service.grammarRevision, 1);
  });

  test('100 grammar switches call the active recognizer exactly 100 times',
      () async {
    final _FakeRecognizer command = _FakeRecognizer();
    final SpeechRecognitionService service = _service(command: command);
    addTearDown(service.dispose);
    await service.prepare();

    for (int index = 0; index < 100; index++) {
      await service.switchCommandGrammar(
        screen: index.isEven ? WearScreenId.help : WearScreenId.settings,
        grammar: <String>['команда $index', '[unk]'],
      );
    }

    expect(command.grammars, hasLength(101));
    expect(service.routeRevision, 100);
    expect(service.grammarRevision, 100);
  });

  test('identical screen grammar does not reset recognizer', () async {
    final _FakeRecognizer command = _FakeRecognizer();
    final SpeechRecognitionService service = _service(command: command);
    addTearDown(service.dispose);
    await service.prepare();
    await service.switchCommandGrammar(
      screen: WearScreenId.help,
      grammar: const <String>['назад', '[unk]'],
    );
    final int resetCalls = command.resetCalls;
    final int grammarCalls = command.grammars.length;

    await service.switchCommandGrammar(
      screen: WearScreenId.help,
      grammar: const <String>['назад', '[unk]'],
    );

    expect(command.resetCalls, resetCalls);
    expect(command.grammars, hasLength(grammarCalls));
  });

  test('grammar cutover never replays audio accepted by old grammar', () async {
    final _FakeRecognizer command = _FakeRecognizer();
    final SpeechRecognitionService service = _service(command: command);
    addTearDown(service.dispose);
    await service.prepare();
    await service.startSession();
    service.beginProcessingCapture();

    final Uint8List oldFrame = _pcmFrame(1000);
    final Uint8List newFrame = _pcmFrame(2000);
    await service.processAudioChunk(oldFrame);
    await service.switchCommandGrammar(
      screen: WearScreenId.help,
      grammar: const <String>['назад', '[unk]'],
    );
    await service.processAudioChunk(newFrame);

    expect(command.accepted, <Uint8List>[oldFrame, newFrame]);
  });

  test('free-text replay waits for recognizer creation', () async {
    final _FakeRecognizer command = _FakeRecognizer()
      ..endpointSequence.add(true)
      ..resultSequence.add(_json(text: 'товар молоко'));
    final _FakeRecognizer freeText = _FakeRecognizer()
      ..finalSequence.add(_json(text: 'товар молоко'));
    final Completer<VoiceRecognizer> freeTextReady =
        Completer<VoiceRecognizer>();
    final SpeechRecognitionService service = _service(
      command: command,
      freeTextFactory: () => freeTextReady.future,
    );
    addTearDown(service.dispose);
    await service.prepare();
    await service.startSession();
    service.beginProcessingCapture();
    final List<SegmentedRecognitionResult> results =
        <SegmentedRecognitionResult>[];
    service.segmentedResultsStream.listen(results.add);

    final Future<void> enabling = service.setFreeTextEnabled(true);
    await service.processAudioChunk(_pcmFrame(1000));
    freeTextReady.complete(freeText);
    await enabling;
    await service.waitForProcessing();

    expect(
      results
          .where((result) => result.lane == RecognitionLane.freeText)
          .map((result) => result.text),
      contains('товар молоко'),
    );
  });

  test('free-text replay aggregates two endpoints and stream tail', () async {
    final _FakeRecognizer command = _FakeRecognizer();
    for (int index = 0; index < 5; index++) {
      command.endpointSequence.add(false);
    }
    command.endpointSequence.add(true);
    command.resultSequence.add(_json(text: 'не команда'));
    final _FakeRecognizer freeText = _FakeRecognizer()
      ..endpointSequence.addAll(<bool>[true, true])
      ..resultSequence.addAll(<String>[
        _json(text: 'красное'),
        _json(text: 'яблоко'),
      ])
      ..finalSequence.add(_json(text: 'голден'));
    final SpeechRecognitionService service = _service(
      command: command,
      freeTextFactory: () async => freeText,
    );
    addTearDown(service.dispose);
    await service.prepare();
    await service.startSession();
    service.beginProcessingCapture();
    await service.setFreeTextEnabled(true);
    final Future<SegmentedRecognitionResult> result = service
        .segmentedResultsStream
        .firstWhere((event) => event.lane == RecognitionLane.freeText);

    for (int index = 0; index < 6; index++) {
      await service.processAudioChunk(_pcmFrame(1000 + index));
    }
    await service.waitForProcessing();

    expect((await result).text, 'красное яблоко голден');
  });

  test('route change cancels stale free-text replay between batches', () async {
    final _FakeRecognizer command = _FakeRecognizer()
      ..endpointSequence.add(true)
      ..resultSequence.add(_json(text: 'не команда'));
    final Completer<bool> firstBatch = Completer<bool>();
    final _FakeRecognizer freeText = _FakeRecognizer()
      ..acceptOverride = ((_) => firstBatch.future)
      ..finalSequence.add(_json(text: 'устаревший текст'));
    final SpeechRecognitionService service = _service(
      command: command,
      freeTextFactory: () async => freeText,
    );
    addTearDown(service.dispose);
    await service.prepare();
    await service.startSession();
    service.beginProcessingCapture();
    await service.setFreeTextEnabled(true);
    final List<SegmentedRecognitionResult> results =
        <SegmentedRecognitionResult>[];
    service.segmentedResultsStream.listen(results.add);

    await service.processAudioChunk(_pcmFrame(1000));
    await service.switchCommandGrammar(
      screen: WearScreenId.help,
      grammar: const <String>['назад', '[unk]'],
    );
    firstBatch.complete(false);
    await service.waitForProcessing();

    expect(
      results.where((event) => event.lane == RecognitionLane.freeText),
      isEmpty,
    );
    expect(freeText.finalCalls, 0);
  });

  test('free-text replay timeout releases the serial queue', () async {
    final _FakeRecognizer command = _FakeRecognizer()
      ..endpointSequence.add(true)
      ..resultSequence.add(_json(text: 'не команда'));
    final _FakeRecognizer freeText = _FakeRecognizer()
      ..acceptOverride = (_) => Completer<bool>().future;
    final SpeechRecognitionService service = _service(
      command: command,
      freeTextFactory: () async => freeText,
      recognizerOperationTimeout: const Duration(milliseconds: 20),
    );
    addTearDown(service.dispose);
    await service.prepare();
    await service.startSession();
    service.beginProcessingCapture();
    await service.setFreeTextEnabled(true);

    await service.processAudioChunk(_pcmFrame(1000));
    await service.waitForProcessing().timeout(const Duration(seconds: 1));

    expect(freeText.finalCalls, 0);
  });

  test('external max-duration VAD does not finalize command recognizer',
      () async {
    final _FakeRecognizer command = _FakeRecognizer();
    final SpeechRecognitionService service = _service(
      command: command,
      segmenter: SpeechSegmenter(
        calibrationDuration: Duration.zero,
        maxSegmentDuration: const Duration(milliseconds: 100),
      ),
    );
    addTearDown(service.dispose);
    await service.prepare();
    await service.startSession();
    service.beginProcessingCapture();

    for (int index = 0; index < 10; index++) {
      await service.processAudioChunk(_pcmFrame(1000));
    }

    expect(command.finalCalls, 0);
    expect(command.resetCalls, 1);
    expect(service.commandUtteranceId, 1);
    expect(service.bufferedUtteranceBytes, greaterThan(0));
  });

  test('command after acoustic max-duration remains executable', () async {
    final _FakeRecognizer command = _FakeRecognizer();
    command.endpointSequence.addAll(<bool>[
      ...List<bool>.filled(10, false),
      true,
    ]);
    command.resultSequence.add(_json(text: 'вверх'));
    final SpeechRecognitionService service = _service(
      command: command,
      segmenter: SpeechSegmenter(
        calibrationDuration: Duration.zero,
        maxSegmentDuration: const Duration(milliseconds: 100),
      ),
    );
    addTearDown(service.dispose);
    await service.prepare();
    await service.startSession();
    service.beginProcessingCapture();
    final Future<SegmentedRecognitionResult> result = service
        .segmentedResultsStream
        .firstWhere((event) => event.kind == RecognitionKind.endpointResult);

    for (int index = 0; index < 11; index++) {
      await service.processAudioChunk(_pcmFrame(1000));
    }

    expect((await result).text, 'вверх');
    expect(service.commandUtteranceId, 2);
  });

  test('natural Vosk endpoint clears PCM and increments utterance id',
      () async {
    final _FakeRecognizer command = _FakeRecognizer()
      ..endpointSequence.add(true)
      ..resultSequence.add(_json(text: 'вверх'));
    final SpeechRecognitionService service = _service(command: command);
    addTearDown(service.dispose);
    await service.prepare();
    await service.startSession();
    service.beginProcessingCapture();

    await service.processAudioChunk(_pcmFrame(1000));

    expect(service.bufferedUtteranceBytes, 0);
    expect(service.commandUtteranceId, 2);
  });

  test('ten seconds of activity accepts every frame and multiple endpoints',
      () async {
    final _FakeRecognizer command = _FakeRecognizer();
    for (int index = 1; index <= 500; index++) {
      final bool endpoint = index == 100 || index == 300 || index == 500;
      command.endpointSequence.add(endpoint);
      if (endpoint) command.resultSequence.add(_json(text: 'вверх'));
    }
    final SpeechRecognitionService service = _service(command: command);
    addTearDown(service.dispose);
    await service.prepare();
    await service.startSession();
    service.beginProcessingCapture();

    for (int index = 0; index < 500; index++) {
      await service.processAudioChunk(_pcmFrame(1000));
    }

    expect(command.accepted, hasLength(500));
    expect(command.resultCalls, 3);
    expect(service.commandUtteranceId, 4);
  });
}

SpeechRecognitionService _service({
  required _FakeRecognizer command,
  Future<VoiceRecognizer> Function()? freeTextFactory,
  SpeechSegmenter? segmenter,
  Duration recognizerOperationTimeout = const Duration(seconds: 2),
}) {
  return SpeechRecognitionService(
    commandGrammar: const <String>['вверх', '[unk]'],
    speechSegmenter: segmenter ??
        SpeechSegmenter(
          calibrationDuration: Duration.zero,
          maxSegmentDuration: const Duration(seconds: 30),
        ),
    recognizerFactory: (RecognitionLane lane, List<String> grammar) async {
      if (lane == RecognitionLane.command) return command;
      return freeTextFactory!();
    },
    recognizerOperationTimeout: recognizerOperationTimeout,
  );
}

class _FakeRecognizer implements VoiceRecognizer {
  final List<bool> endpointSequence = <bool>[];
  final List<String> resultSequence = <String>[];
  final List<String> finalSequence = <String>[];
  final List<Uint8List> accepted = <Uint8List>[];
  final List<List<String>> grammars = <List<String>>[];
  bool failNextGrammar = false;
  Future<bool> Function(Uint8List bytes)? acceptOverride;
  int resetCalls = 0;
  int resultCalls = 0;
  int finalCalls = 0;

  @override
  Future<bool> acceptWaveformBytes(Uint8List bytes) async {
    accepted.add(Uint8List.fromList(bytes));
    final Future<bool> Function(Uint8List bytes)? override = acceptOverride;
    if (override != null) return override(bytes);
    return endpointSequence.isEmpty ? false : endpointSequence.removeAt(0);
  }

  @override
  Future<void> dispose() async {}

  @override
  Future<String> getFinalResult() async {
    finalCalls++;
    return finalSequence.isEmpty ? _json() : finalSequence.removeAt(0);
  }

  @override
  Future<String> getPartialResult() async => _json(partial: '');

  @override
  Future<String> getResult() async {
    resultCalls++;
    return resultSequence.isEmpty ? _json() : resultSequence.removeAt(0);
  }

  @override
  Future<void> reset() async {
    resetCalls++;
  }

  @override
  Future<void> setGrammar(List<String> grammar) async {
    if (failNextGrammar) {
      failNextGrammar = false;
      throw StateError('setGrammar failed');
    }
    grammars.add(List<String>.of(grammar));
  }
}

Uint8List _pcmFrame(int amplitude) {
  final ByteData bytes = ByteData(640);
  for (int offset = 0; offset < 640; offset += 2) {
    bytes.setInt16(offset, amplitude, Endian.little);
  }
  return bytes.buffer.asUint8List();
}

String _json({String text = '', String partial = ''}) =>
    jsonEncode(<String, String>{'text': text, 'partial': partial});
