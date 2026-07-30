import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_typing/free_text_pipeline_mode.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/voice_utterance_coordinator.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_typing/segmented_recognition_result.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_typing/speech_recognition_service.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_typing/speech_segmenter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('T01 live mode fans the same PCM out to both lanes', () async {
    final _FakeRecognizer command = _FakeRecognizer();
    final _FakeRecognizer freeText = _FakeRecognizer();
    final SpeechRecognitionService service = _service(
      command: command,
      freeText: freeText,
    );
    addTearDown(service.dispose);
    await _start(service);

    final Uint8List frame = _pcmFrame(1000);
    await service.processAudioChunk(frame);
    await service.waitForProcessing();

    expect(command.accepted, hasLength(1));
    expect(freeText.accepted, hasLength(2));
    expect(freeText.accepted.last, command.accepted.single);
  });

  test('T02 grammar-only mode does not feed free-text live lane', () async {
    final _FakeRecognizer command = _FakeRecognizer();
    final SpeechRecognitionService service = SpeechRecognitionService(
      commandGrammar: const <String>['вверх', '[unk]'],
      freeTextPipelineMode: FreeTextPipelineMode.liveWithReplayFallback,
      speechSegmenter: SpeechSegmenter(calibrationDuration: Duration.zero),
      recognizerFactory: (RecognitionLane lane, List<String> grammar) async {
        expect(lane, RecognitionLane.command);
        return command;
      },
    );
    addTearDown(service.dispose);
    await service.prepare();
    await service.startSession();
    service.beginProcessingCapture();

    await service.processAudioChunk(_pcmFrame(1000));
    await service.waitForProcessing();

    expect(command.accepted, hasLength(1));
  });

  test('T03 live yellow publishes once without replay', () async {
    final _FakeRecognizer command = _FakeRecognizer()
      ..endpoints.add(true)
      ..results.add(_json(text: 'не команда'));
    final _FakeRecognizer freeText = _FakeRecognizer()
      ..finals.addAll(<String>[_json(), _json(text: 'жёлтый')]);
    final SpeechRecognitionService service = _service(
      command: command,
      freeText: freeText,
    );
    addTearDown(service.dispose);
    await _start(service);
    final List<SegmentedRecognitionResult> phrases =
        <SegmentedRecognitionResult>[];
    service.segmentedResultsStream.listen((SegmentedRecognitionResult event) {
      if (event.lane == RecognitionLane.freeText) phrases.add(event);
    });

    await _processUtterance(service);
    await service.waitForProcessing();

    expect(phrases.map((event) => event.text), <String>['жёлтый']);
    expect(phrases.single.isLiveFreeText, isTrue);
    expect(freeText.accepted.length, command.accepted.length + 1);
    expect(service.replayFallbackCount, 0);
  });

  test('T10 command and free-text conflict publishes neither result', () async {
    final _FakeRecognizer command = _FakeRecognizer()
      ..endpoints.add(true)
      ..results.add(_json(text: 'выбрать'));
    final _FakeRecognizer freeText = _FakeRecognizer()
      ..finals.addAll(<String>[_json(), _json(text: 'жёлтый')]);
    final SpeechRecognitionService service = _service(
      command: command,
      freeText: freeText,
    );
    addTearDown(service.dispose);
    await _start(service);
    final List<SegmentedRecognitionResult> finals =
        <SegmentedRecognitionResult>[];
    service.segmentedResultsStream.listen((SegmentedRecognitionResult event) {
      if (event.kind != RecognitionKind.partial) finals.add(event);
    });

    await _processUtterance(service);
    await service.waitForProcessing();

    expect(finals, isEmpty);
    expect(service.conflictCount, 1);
  });

  test('T13 backlog invalidates live result and uses replay fallback',
      () async {
    final _FakeRecognizer command = _FakeRecognizer()
      ..endpoints.add(true)
      ..results.add(_json(text: 'не команда'));
    final _FakeRecognizer freeText = _FakeRecognizer()
      ..finals.addAll(<String>[_json(), _json(text: 'жёлтый')]);
    final SpeechRecognitionService service = _service(
      command: command,
      freeText: freeText,
      backlogBytes: 1,
    );
    addTearDown(service.dispose);
    await _start(service);
    final Future<SegmentedRecognitionResult> phrase = service
        .segmentedResultsStream
        .firstWhere((event) => event.lane == RecognitionLane.freeText);

    await _processUtterance(service);
    await service.waitForProcessing();

    expect((await phrase).text, 'жёлтый');
    expect(service.replayFallbackCount, 1);
    expect(freeText.accepted.length, lessThan(command.accepted.length));
  });

  test('T19 shadow mode publishes replay result only', () async {
    final _FakeRecognizer command = _FakeRecognizer()
      ..endpoints.add(true)
      ..results.add(_json(text: 'не команда'));
    final _FakeRecognizer freeText = _FakeRecognizer()
      ..finals.addAll(<String>[
        _json(),
        _json(text: 'жёлтый'),
        _json(text: 'мобильный'),
      ]);
    final SpeechRecognitionService service = SpeechRecognitionService(
      commandGrammar: const <String>['вверх', 'вниз', 'выбрать', '[unk]'],
      freeTextPipelineMode: FreeTextPipelineMode.shadowLive,
      speechSegmenter: SpeechSegmenter(calibrationDuration: Duration.zero),
      recognizerFactory: (RecognitionLane lane, List<String> grammar) async =>
          lane == RecognitionLane.command ? command : freeText,
    );
    addTearDown(service.dispose);
    await _start(service);
    final List<String> phrases = <String>[];
    service.segmentedResultsStream.listen((event) {
      if (event.lane == RecognitionLane.freeText) phrases.add(event.text);
    });

    await _processUtterance(service);
    await service.waitForProcessing();

    expect(phrases, <String>['мобильный']);
  });

  test('T20 replay-only compatibility keeps sequential replay', () async {
    final _FakeRecognizer command = _FakeRecognizer()
      ..endpoints.add(true)
      ..results.add(_json(text: 'не команда'));
    final _FakeRecognizer freeText = _FakeRecognizer()
      ..finals.add(_json(text: 'жёлтый'));
    final SpeechRecognitionService service = SpeechRecognitionService(
      commandGrammar: const <String>['вверх', 'вниз', 'выбрать', '[unk]'],
      freeTextPipelineMode: FreeTextPipelineMode.replayOnly,
      speechSegmenter: SpeechSegmenter(calibrationDuration: Duration.zero),
      recognizerFactory: (RecognitionLane lane, List<String> grammar) async =>
          lane == RecognitionLane.command ? command : freeText,
    );
    addTearDown(service.dispose);
    await _start(service);
    final Future<SegmentedRecognitionResult> phrase = service
        .segmentedResultsStream
        .firstWhere((event) => event.lane == RecognitionLane.freeText);

    await service.processAudioChunk(_pcmFrame(1000));
    await service.waitForProcessing();

    final SegmentedRecognitionResult replayResult = await phrase;
    expect(replayResult.text, 'жёлтый');
    expect(replayResult.isLiveFreeText, isFalse);
    expect(freeText.accepted, hasLength(1));
  });

  test('T12/T22 live timeout replaces recognizer without mid-call dispose',
      () async {
    final _FakeRecognizer command = _FakeRecognizer()
      ..endpoints.add(true)
      ..results.add(_json(text: 'не команда'));
    final Completer<String> blockedFinal = Completer<String>();
    final _FakeRecognizer blocked = _FakeRecognizer()
      ..finals.add(_json())
      ..finalOverride = () => blockedFinal.future;
    final _FakeRecognizer replacement = _FakeRecognizer()
      ..finals.addAll(<String>[_json(), _json(text: 'жёлтый')]);
    final List<_FakeRecognizer> freeTextRecognizers = <_FakeRecognizer>[
      blocked,
      replacement
    ];
    final SpeechRecognitionService service = SpeechRecognitionService(
      commandGrammar: const <String>['вверх', 'вниз', 'выбрать', '[unk]'],
      freeTextPipelineMode: FreeTextPipelineMode.liveWithReplayFallback,
      speechSegmenter: SpeechSegmenter(calibrationDuration: Duration.zero),
      recognizerOperationTimeout: const Duration(milliseconds: 20),
      recognizerFactory: (RecognitionLane lane, List<String> grammar) async =>
          lane == RecognitionLane.command
              ? command
              : freeTextRecognizers.removeAt(0),
    );
    addTearDown(service.dispose);
    await _start(service);
    final Future<SegmentedRecognitionResult> phrase = service
        .segmentedResultsStream
        .firstWhere((event) => event.lane == RecognitionLane.freeText);

    await _processUtterance(service);
    await service.waitForProcessing();

    expect((await phrase).text, 'жёлтый');
    expect(service.replayFallbackCount, 1);
    expect(blocked.disposeCalls, 0);
    blockedFinal.complete(_json());
    await Future<void>.delayed(Duration.zero);
    expect(blocked.disposeCalls, 1);
  });
}

SpeechRecognitionService _service({
  required _FakeRecognizer command,
  required _FakeRecognizer freeText,
  int backlogBytes = 64000,
}) {
  return SpeechRecognitionService(
    commandGrammar: const <String>['вверх', 'вниз', 'выбрать', '[unk]'],
    freeTextPipelineMode: FreeTextPipelineMode.liveWithReplayFallback,
    freeTextBacklogLimitBytes: backlogBytes,
    speechSegmenter: SpeechSegmenter(calibrationDuration: Duration.zero),
    dynamicItemsProvider: (WearScreenId screen) =>
        const VoiceDynamicItemsSnapshot(
      revision: 1,
      items: <VoiceDynamicItem>[
        VoiceDynamicItem(id: "yellow", label: "жёлтый"),
        VoiceDynamicItem(id: "mobile", label: "мобильный"),
      ],
    ),
    recognizerFactory: (RecognitionLane lane, List<String> grammar) async {
      return lane == RecognitionLane.command ? command : freeText;
    },
  );
}

Future<void> _start(SpeechRecognitionService service) async {
  await service.prepare();
  await service.startSession();
  service.beginProcessingCapture();
  await service.setFreeTextEnabled(true);
}

Future<void> _processUtterance(SpeechRecognitionService service) async {
  await service.processAudioChunk(_pcmFrame(1000));
  for (int index = 0; index < 40; index++) {
    await service.processAudioChunk(_pcmFrame(0));
  }
}

Uint8List _pcmFrame(int sample) {
  final ByteData data = ByteData(640);
  for (int offset = 0; offset < 640; offset += 2) {
    data.setInt16(offset, sample, Endian.little);
  }
  return data.buffer.asUint8List();
}

String _json({String text = '', String partial = ''}) =>
    jsonEncode(<String, String>{'text': text, 'partial': partial});

class _FakeRecognizer implements VoiceRecognizer {
  final List<bool> endpoints = <bool>[];
  final List<String> results = <String>[];
  final List<String> finals = <String>[];
  final List<Uint8List> accepted = <Uint8List>[];
  Future<String> Function()? finalOverride;
  int disposeCalls = 0;

  @override
  Future<bool> acceptWaveformBytes(Uint8List bytes) async {
    accepted.add(Uint8List.fromList(bytes));
    return endpoints.isEmpty ? false : endpoints.removeAt(0);
  }

  @override
  Future<void> dispose() async => disposeCalls++;

  @override
  Future<String> getFinalResult() async {
    if (finals.isNotEmpty) return finals.removeAt(0);
    final Future<String> Function()? override = finalOverride;
    return override == null ? _json() : override();
  }

  @override
  Future<String> getPartialResult() async => _json();

  @override
  Future<String> getResult() async =>
      results.isEmpty ? _json() : results.removeAt(0);

  @override
  Future<void> reset() async {}

  @override
  Future<void> setGrammar(List<String> grammar) async {}
}
