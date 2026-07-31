import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_typing/free_text_pipeline_mode.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/voice_action_catalog.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/voice_hint_generator.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/voice_hint_index_cache.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/voice_utterance_coordinator.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/wear_voice_command.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_typing/segmented_recognition_result.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_typing/speech_recognition_service.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_typing/speech_segmenter.dart';

void main() {
  test('live free-text publishes a contextual partial before final', () async {
    final _FakeRecognizer command = _FakeRecognizer();
    final _FakeRecognizer freeText = _FakeRecognizer()
      ..partials.add(_json(partial: 'жёлтый'));
    final SpeechRecognitionService service = _service(
      command: command,
      freeText: freeText,
    );
    addTearDown(service.dispose);
    final List<SegmentedRecognitionResult> events =
        <SegmentedRecognitionResult>[];
    final subscription = service.segmentedResultsStream.listen(events.add);
    addTearDown(subscription.cancel);

    await _start(service);
    await service.processAudioChunk(_pcmFrame(1000));
    await service.waitForProcessing();

    final SegmentedRecognitionResult partial = events.singleWhere((event) =>
        event.lane == RecognitionLane.freeText &&
        event.kind == RecognitionKind.partial &&
        event.text == 'жёлтый');
    expect(partial.freeTextEpoch, service.freeTextEpoch);
    expect(partial.listRevision, 1);
    expect(partial.commandUtteranceId, 1);
  });

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
      ..finalDelay = const Duration(milliseconds: 5)
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
    expect(service.metricsSnapshot.freeTextFinalization.p50,
        greaterThanOrEqualTo(5));
    expect(service.metricsSnapshot.endpointToFreeTextFinal.p50,
        greaterThanOrEqualTo(5));
    expect(service.metricsSnapshot.endpointToDecision.p50,
        greaterThanOrEqualTo(5));
    expect(service.metricsSnapshot.speechToPhrase.p50, greaterThanOrEqualTo(5));
  });

  test('free-text exact command navigates clarification pages', () async {
    final _FakeRecognizer command = _FakeRecognizer()
      ..endpoints.add(true)
      ..results.add(_json(text: 'не команда'));
    final _FakeRecognizer freeText = _FakeRecognizer()
      ..partials.add(_json(partial: 'жёлтый'))
      ..finals.addAll(<String>[
        _json(),
        _json(text: 'следующая страница'),
      ]);
    final SpeechRecognitionService service = _service(
      command: command,
      freeText: freeText,
      dynamicItems: const VoiceDynamicItemsSnapshot(
        revision: 1,
        items: <VoiceDynamicItem>[
          VoiceDynamicItem(id: 'page', label: 'следующая страница'),
        ],
      ),
    );
    addTearDown(service.dispose);
    await _start(service);
    await service.switchCommandGrammar(
      screen: WearScreenId.voiceClarification,
      grammar: VoiceActionCatalog().grammarFor(WearScreenId.voiceClarification),
    );
    final Future<SegmentedRecognitionResult> result =
        service.segmentedResultsStream.firstWhere((event) =>
            event.lane == RecognitionLane.command &&
            event.kind == RecognitionKind.streamFinal);

    await _processUtterance(service);
    await service.waitForProcessing();

    final SegmentedRecognitionResult commandResult = await result;
    expect(commandResult.text, 'следующая страница');
    expect(commandResult.parsedCommand, WearVoiceCommand.nextPage);
  });

  test('ambiguous free text is published for clarification', () async {
    final _FakeRecognizer command = _FakeRecognizer()
      ..endpoints.add(true)
      ..results.add(_json(text: 'не команда'));
    final _FakeRecognizer freeText = _FakeRecognizer()
      ..finals.addAll(<String>[
        _json(),
        _json(text: 'коровка из кореновки'),
      ]);
    final SpeechRecognitionService service = _service(
      command: command,
      freeText: freeText,
      dynamicItems: const VoiceDynamicItemsSnapshot(
        revision: 2,
        items: <VoiceDynamicItem>[
          VoiceDynamicItem(
            id: '1',
            label: 'Коровка из Кореновки пломбир',
          ),
          VoiceDynamicItem(
            id: '2',
            label: 'Коровка из Кореновки стакан',
          ),
        ],
      ),
    );
    addTearDown(service.dispose);
    await _start(service);
    final Future<SegmentedRecognitionResult> phrase = service
        .segmentedResultsStream
        .firstWhere((event) => event.lane == RecognitionLane.freeText);

    await _processUtterance(service);
    await service.waitForProcessing();

    expect((await phrase).text, 'коровка из кореновки');
  });

  test('T10 exact dynamic hint takes priority over a false command match',
      () async {
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

    expect(finals, hasLength(1));
    expect(finals.single.lane, RecognitionLane.freeText);
    expect(finals.single.text, 'жёлтый');
    expect(service.conflictCount, 0);
  });

  test('cold final does not generate hints or change command arbitration',
      () async {
    final Completer<VoiceHintSet> hintBuild = Completer<VoiceHintSet>();
    var buildCount = 0;
    final VoiceHintIndexCache hintIndexCache = VoiceHintIndexCache(
      builder: (snapshot, reserved, excluded) {
        buildCount++;
        return hintBuild.future;
      },
    );
    final List<VoiceDynamicItem> items = <VoiceDynamicItem>[
      const VoiceDynamicItem(id: 'yellow', label: 'Жёлтый товар'),
      for (int index = 0; index < 32; index++)
        VoiceDynamicItem(id: 'item-$index', label: 'Позиция номер $index'),
    ];
    final VoiceDynamicItemsSnapshot snapshot = VoiceDynamicItemsSnapshot(
      revision: 33,
      items: items,
    );
    final _FakeRecognizer command = _FakeRecognizer()
      ..endpoints.add(true)
      ..results.add(_json(text: 'выбрать'));
    final _FakeRecognizer freeText = _FakeRecognizer()
      ..finals.addAll(<String>[_json(), _json(text: 'жёлтый')]);
    final SpeechRecognitionService service = _service(
      command: command,
      freeText: freeText,
      dynamicItems: snapshot,
      hintIndexCache: hintIndexCache,
      prewarmHints: false,
    );
    addTearDown(service.dispose);
    await _start(service);
    final Future<SegmentedRecognitionResult> result = service
        .segmentedResultsStream
        .firstWhere((event) => event.kind == RecognitionKind.streamFinal);

    await _processUtterance(service);
    await service.waitForProcessing();

    final SegmentedRecognitionResult decision = await result;
    expect(decision.lane, RecognitionLane.command);
    expect(decision.text, 'выбрать');
    expect(buildCount, 0);
  });

  test('screen preparation preserves exact-hint dynamic priority', () async {
    final Completer<VoiceHintSet> hintBuild = Completer<VoiceHintSet>();
    final VoiceHintIndexCache hintIndexCache = VoiceHintIndexCache(
      builder: (snapshot, reserved, excluded) => hintBuild.future,
    );
    final List<VoiceDynamicItem> items = <VoiceDynamicItem>[
      const VoiceDynamicItem(id: 'yellow', label: 'Жёлтый товар'),
      for (int index = 0; index < 32; index++)
        VoiceDynamicItem(id: 'item-$index', label: 'Позиция номер $index'),
    ];
    final VoiceDynamicItemsSnapshot snapshot = VoiceDynamicItemsSnapshot(
      revision: 33,
      items: items,
    );
    final _FakeRecognizer command = _FakeRecognizer()
      ..endpoints.add(true)
      ..results.add(_json(text: 'выбрать'));
    final _FakeRecognizer freeText = _FakeRecognizer()
      ..finals.addAll(<String>[_json(), _json(text: 'товар')]);
    final SpeechRecognitionService service = _service(
      command: command,
      freeText: freeText,
      dynamicItems: snapshot,
      hintIndexCache: hintIndexCache,
      prewarmHints: false,
    );
    addTearDown(service.dispose);
    await _start(service);
    final Future<void> preparing = service.prepareVoiceHints(WearScreenId.menu);
    hintBuild.complete(VoiceHintGenerator.generate(
      snapshot,
      reservedPhrases: VoiceActionCatalog().phrasesFor(WearScreenId.menu),
    ));
    await preparing;
    final Future<SegmentedRecognitionResult> result = service
        .segmentedResultsStream
        .firstWhere((event) => event.kind == RecognitionKind.streamFinal);

    await _processUtterance(service);
    await service.waitForProcessing();

    final SegmentedRecognitionResult decision = await result;
    expect(decision.lane, RecognitionLane.freeText);
    expect(decision.text, 'товар');
  });

  test('production callback batches four VAD frames per recognizer call',
      () async {
    final _FakeRecognizer command = _FakeRecognizer();
    final _FakeRecognizer freeText = _FakeRecognizer();
    final SpeechRecognitionService service = _service(
      command: command,
      freeText: freeText,
    );
    addTearDown(service.dispose);
    await _start(service);

    for (int index = 0; index < 3; index++) {
      expect(service.processAudioPacketForTest(_pcmFrame(1000)), isTrue);
    }
    expect(command.accepted, isEmpty);
    expect(service.processAudioPacketForTest(_pcmFrame(1000)), isTrue);
    await service.waitForProcessing();

    expect(command.accepted, hasLength(1));
    expect(command.accepted.single.lengthInBytes, 2560);
    expect(freeText.accepted.last.lengthInBytes, 2560);
  });

  test('production callback flushes an incomplete batch at VAD endpoint',
      () async {
    final _FakeRecognizer command = _FakeRecognizer();
    final _FakeRecognizer freeText = _FakeRecognizer();
    final SpeechRecognitionService service = _service(
      command: command,
      freeText: freeText,
      speechSegmenter: SpeechSegmenter(
        calibrationDuration: Duration.zero,
        endpointSilence: const Duration(milliseconds: 20),
      ),
    );
    addTearDown(service.dispose);
    await _start(service);

    expect(service.processAudioPacketForTest(_pcmFrame(1000)), isTrue);
    expect(service.processAudioPacketForTest(_pcmFrame(0)), isTrue);
    await service.waitForProcessing();

    expect(command.accepted.single.lengthInBytes, 1280);
    expect(
      freeText.accepted.map((bytes) => bytes.lengthInBytes),
      contains(1280),
    );
  });

  test('backlog rejection preserves the admitted incomplete batch', () async {
    final _FakeRecognizer command = _FakeRecognizer();
    final _FakeRecognizer freeText = _FakeRecognizer();
    final SpeechRecognitionService service = _service(
      command: command,
      freeText: freeText,
      commandBacklogBytes: 640,
    );
    addTearDown(service.dispose);
    await _start(service);

    expect(service.processAudioPacketForTest(_pcmFrame(1000)), isTrue);
    expect(service.processAudioPacketForTest(_pcmFrame(1000)), isFalse);
    await service.stopListening();

    expect(command.accepted, hasLength(1));
    expect(command.accepted.single.lengthInBytes, 640);
  });

  test('free-text disable drains an incomplete production batch', () async {
    final _FakeRecognizer command = _FakeRecognizer();
    final _FakeRecognizer freeText = _FakeRecognizer();
    final SpeechRecognitionService service = _service(
      command: command,
      freeText: freeText,
    );
    addTearDown(service.dispose);
    await _start(service);

    expect(service.processAudioPacketForTest(_pcmFrame(1000)), isTrue);
    await service.setFreeTextEnabled(false);
    await service.waitForProcessing();

    expect(command.accepted.single.lengthInBytes, 640);
    expect(
      freeText.accepted.map((bytes) => bytes.lengthInBytes),
      contains(640),
    );
    expect(service.usesFreeTextRecognition, isFalse);
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

  test('slow live lane stops accepting the invalidated utterance', () async {
    final _FakeRecognizer command = _FakeRecognizer();
    final _FakeRecognizer freeText = _FakeRecognizer();
    final SpeechRecognitionService service = _service(
      command: command,
      freeText: freeText,
    );
    addTearDown(service.dispose);
    await _start(service);
    command.accepted.clear();
    freeText.accepted.clear();
    final Completer<bool> blockedAccept = Completer<bool>();
    freeText.acceptOverride = (_) => blockedAccept.future;

    for (int index = 0; index < 12; index++) {
      expect(service.processAudioPacketForTest(_pcmFrame(1000)), isTrue);
    }
    await Future<void>.delayed(Duration.zero);
    blockedAccept.complete(false);
    await service.waitForProcessing();

    expect(command.accepted, hasLength(3));
    expect(freeText.accepted, hasLength(2));
  });

  test('enabling live lane resyncs after grammar-only natural endpoints',
      () async {
    final _FakeRecognizer command = _FakeRecognizer()
      ..endpoints.addAll(<bool>[true, true])
      ..results.addAll(<String>[
        _json(text: 'вверх'),
        _json(text: 'вниз'),
      ]);
    final _FakeRecognizer freeText = _FakeRecognizer()
      ..finals.addAll(<String>[
        _json(),
        _json(text: 'жёлтый'),
      ]);
    final SpeechRecognitionService service = _service(
      command: command,
      freeText: freeText,
      speechSegmenter: SpeechSegmenter(
        calibrationDuration: Duration.zero,
        endpointSilence: const Duration(milliseconds: 20),
      ),
    );
    addTearDown(service.dispose);
    await service.prepare();
    await service.startSession();
    service.beginProcessingCapture();

    await service.processAudioChunk(_pcmFrame(1000));
    await service.processAudioChunk(_pcmFrame(1000));
    await service.processAudioChunk(_pcmFrame(0));
    await service.setFreeTextEnabled(true);
    final Future<SegmentedRecognitionResult> phrase = service
        .segmentedResultsStream
        .firstWhere((event) => event.lane == RecognitionLane.freeText);

    await _processUtterance(service);
    await service.waitForProcessing().timeout(const Duration(seconds: 1));

    expect((await phrase).text, 'жёлтый');
  });

  test('live free-text is prewarmed but receives PCM only after enable',
      () async {
    final _FakeRecognizer command = _FakeRecognizer();
    final _FakeRecognizer freeText = _FakeRecognizer();
    final SpeechRecognitionService service = _service(
      command: command,
      freeText: freeText,
    );
    addTearDown(service.dispose);

    await service.prepare();
    expect(freeText.accepted, hasLength(1));
    await service.startSession();
    service.beginProcessingCapture();
    await service.processAudioChunk(_pcmFrame(1000));
    await service.waitForProcessing();
    expect(freeText.accepted, hasLength(1));

    await service.setFreeTextEnabled(true);
    await service.processAudioChunk(_pcmFrame(1000));
    await service.waitForProcessing();
    expect(freeText.accepted, hasLength(2));
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
    final List<SegmentedRecognitionResult> phrases =
        <SegmentedRecognitionResult>[];
    service.segmentedResultsStream.listen((event) {
      if (event.lane == RecognitionLane.freeText) phrases.add(event);
    });

    await _processUtterance(service);
    await service.waitForProcessing();

    expect(phrases.map((event) => event.text), <String>['мобильный']);
    expect(phrases.single.kind, RecognitionKind.streamFinal);
  });

  test('command-lane dynamic key partial carries typed preview identity',
      () async {
    final _FakeRecognizer command = _FakeRecognizer()
      ..endpoints.add(false)
      ..partials.add(_json(partial: 'жёлтый'));
    final _FakeRecognizer freeText = _FakeRecognizer();
    final SpeechRecognitionService service = _service(
      command: command,
      freeText: freeText,
    );
    addTearDown(service.dispose);
    await _start(service);
    final Future<SegmentedRecognitionResult> partial = service
        .segmentedResultsStream
        .firstWhere((event) => event.kind == RecognitionKind.partial);

    await service.processAudioChunk(_pcmFrame(1000));

    final SegmentedRecognitionResult result = await partial;
    expect(result.lane, RecognitionLane.command);
    expect(result.dynamicItemId, 'yellow');
    expect(result.listRevision, 1);
  });

  test('delayed live final is rejected after a newer utterance starts',
      () async {
    final Completer<String> blockedFinal = Completer<String>();
    final Completer<void> finalStarted = Completer<void>();
    final _FakeRecognizer command = _FakeRecognizer()
      ..endpoints.addAll(<bool>[true, false])
      ..results.add(_json(text: 'не команда'));
    final _FakeRecognizer freeText = _FakeRecognizer()
      ..finals.add(_json())
      ..finalOverride = () {
        if (!finalStarted.isCompleted) finalStarted.complete();
        return blockedFinal.future;
      };
    final SpeechRecognitionService service = _service(
      command: command,
      freeText: freeText,
    );
    addTearDown(service.dispose);
    await _start(service);
    final List<SegmentedRecognitionResult> finals =
        <SegmentedRecognitionResult>[];
    service.segmentedResultsStream.listen((event) {
      if (event.lane == RecognitionLane.freeText &&
          event.kind != RecognitionKind.partial) {
        finals.add(event);
      }
    });

    final Future<void> firstUtterance = _processUtterance(service);
    await finalStarted.future;
    final Future<void> newerUtterance =
        service.processAudioChunk(_pcmFrame(1000));
    await Future<void>.delayed(Duration.zero);
    blockedFinal.complete(_json(text: 'жёлтый'));
    await firstUtterance;
    await newerUtterance;
    await service.waitForProcessing();

    expect(finals, isEmpty);
    expect(service.metricsSnapshot.staleResultCount, 1);
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

  test('stored natural final is cleared by capture restart', () async {
    final _FakeRecognizer command = _FakeRecognizer()
      ..endpoints.addAll(<bool>[true, false])
      ..results.add(_json(text: 'вверх'))
      ..finals.add(_json());
    final _FakeRecognizer freeText = _FakeRecognizer();
    final SpeechRecognitionService service = _service(
      command: command,
      freeText: freeText,
    );
    addTearDown(service.dispose);
    final List<SegmentedRecognitionResult> finals =
        <SegmentedRecognitionResult>[];
    service.segmentedResultsStream.listen((event) {
      if (event.lane == RecognitionLane.command &&
          event.kind == RecognitionKind.streamFinal) {
        finals.add(event);
      }
    });
    await _start(service);

    await service.processAudioChunk(_pcmFrame(1000));
    service.beginProcessingCapture();
    await service.processAudioChunk(_pcmFrame(2000));
    await _silenceEndpoint(service);
    await service.waitForProcessing();

    expect(finals.where((event) => event.text == 'вверх'), isEmpty);
  });

  test('capture restart accepts a final after segment numbering resets',
      () async {
    final _FakeRecognizer command = _FakeRecognizer();
    final _FakeRecognizer freeText = _FakeRecognizer()
      ..finals.addAll(<String>[
        _json(),
        _json(),
        _json(),
        _json(text: 'жёлтый'),
      ]);
    final SpeechRecognitionService service = _service(
      command: command,
      freeText: freeText,
    );
    addTearDown(service.dispose);
    await _start(service);

    for (int index = 0; index < 2; index++) {
      await _processUtterance(service);
    }
    service.beginProcessingCapture();
    final Future<SegmentedRecognitionResult> phrase = service
        .segmentedResultsStream
        .firstWhere((event) => event.lane == RecognitionLane.freeText);

    await _processUtterance(service);
    await service.waitForProcessing();

    expect((await phrase).text, 'жёлтый');
  });

  test(
      'overlapping live PCM waits for prior final reset and uses next utterance id',
      () async {
    final Completer<String> blockedFinal = Completer<String>();
    final Completer<void> finalStarted = Completer<void>();
    var currentSample = 0;
    final _FakeRecognizer command = _FakeRecognizer()
      ..endpoints.add(true)
      ..results.add(_json(text: 'не команда'));
    final _FakeRecognizer freeText = _FakeRecognizer()..finals.add(_json());
    freeText.acceptOverride = (bytes) async {
      currentSample = ByteData.sublistView(bytes).getInt16(0, Endian.little);
      return false;
    };
    freeText.partialOverride =
        () async => _json(partial: currentSample == 2000 ? 'мобильный' : '');
    freeText.finalOverride = () {
      if (!finalStarted.isCompleted) finalStarted.complete();
      return blockedFinal.future;
    };
    final SpeechRecognitionService service = _service(
      command: command,
      freeText: freeText,
    );
    addTearDown(service.dispose);
    final List<SegmentedRecognitionResult> partials =
        <SegmentedRecognitionResult>[];
    service.segmentedResultsStream.listen((event) {
      if (event.lane == RecognitionLane.freeText &&
          event.kind == RecognitionKind.partial &&
          event.text == 'мобильный') {
        partials.add(event);
      }
    });
    await _start(service);
    final Completer<void> resetBlock = Completer<void>();
    final Completer<void> resetStarted = Completer<void>();
    freeText
      ..resetBlock = resetBlock
      ..resetStarted = resetStarted;

    final Future<void> first = _processUtterance(service);
    await finalStarted.future;
    final int acceptedBeforeNext = freeText.accepted.length;
    final Future<void> next = service.processAudioChunk(_pcmFrame(2000));
    await Future<void>.delayed(Duration.zero);
    expect(freeText.accepted, hasLength(acceptedBeforeNext));

    blockedFinal.complete(_json(text: 'жёлтый'));
    await resetStarted.future;
    expect(freeText.accepted, hasLength(acceptedBeforeNext));
    resetBlock.complete();
    await Future.wait<void>(<Future<void>>[first, next]);
    await service.waitForProcessing();

    expect(partials, hasLength(1));
    expect(partials.single.commandUtteranceId, 2);
    expect(
      freeText.accepted.map(
        (bytes) => ByteData.sublistView(bytes).getInt16(0, Endian.little),
      ),
      contains(2000),
    );
  });

  test('shadow overlap emits replay production result and not live result',
      () async {
    final Completer<String> blockedLiveFinal = Completer<String>();
    final Completer<void> liveFinalStarted = Completer<void>();
    var finalCalls = 0;
    final _FakeRecognizer command = _FakeRecognizer()
      ..endpoints.add(true)
      ..results.add(_json(text: 'не команда'));
    final _FakeRecognizer freeText = _FakeRecognizer()
      ..finals.add(_json())
      ..finalOverride = () {
        finalCalls++;
        if (finalCalls == 1) {
          liveFinalStarted.complete();
          return blockedLiveFinal.future;
        }
        return Future<String>.value(_json(text: 'мобильный'));
      };
    final SpeechRecognitionService service = SpeechRecognitionService(
      commandGrammar: const <String>['вверх', 'вниз', 'выбрать', '[unk]'],
      freeTextPipelineMode: FreeTextPipelineMode.shadowLive,
      speechSegmenter: SpeechSegmenter(calibrationDuration: Duration.zero),
      recognizerFactory: (RecognitionLane lane, List<String> grammar) async =>
          lane == RecognitionLane.command ? command : freeText,
    );
    addTearDown(service.dispose);
    final List<SegmentedRecognitionResult> finals =
        <SegmentedRecognitionResult>[];
    service.segmentedResultsStream.listen((event) {
      if (event.lane == RecognitionLane.freeText &&
          event.kind != RecognitionKind.partial) {
        finals.add(event);
      }
    });
    await _start(service);

    final Future<void> first = _processUtterance(service);
    await liveFinalStarted.future;
    final Future<void> next = service.processAudioChunk(_pcmFrame(2000));
    blockedLiveFinal.complete(_json(text: 'жёлтый'));
    await Future.wait<void>(<Future<void>>[first, next]);
    await service.waitForProcessing();

    expect(finals.map((event) => event.text), <String>['мобильный']);
    expect(finals.single.isLiveFreeText, isFalse);
  });

  test('deferred grammar commits after live decision before next command PCM',
      () async {
    final Completer<String> blockedFinal = Completer<String>();
    final Completer<void> finalStarted = Completer<void>();
    final List<String> operations = <String>[];
    final _FakeRecognizer command = _FakeRecognizer()
      ..endpoints.add(true)
      ..results.add(_json(text: 'не команда'))
      ..onAccept = (bytes) {
        final int sample =
            ByteData.sublistView(bytes).getInt16(0, Endian.little);
        if (sample == 2000) operations.add('next-command-pcm');
      }
      ..onGrammar = (_) => operations.add('grammar');
    final _FakeRecognizer freeText = _FakeRecognizer()
      ..finals.add(_json())
      ..finalOverride = () {
        if (!finalStarted.isCompleted) finalStarted.complete();
        return blockedFinal.future;
      };
    final SpeechRecognitionService service = _service(
      command: command,
      freeText: freeText,
    );
    addTearDown(service.dispose);
    await _start(service);
    operations.clear();
    final int routeRevision = service.routeRevision;

    await service.processAudioChunk(_pcmFrame(1000));
    final Future<void> switching = service.switchCommandGrammar(
      screen: WearScreenId.help,
      grammar: const <String>['назад', '[unk]'],
    );
    final Future<void> boundary = _silenceEndpoint(service);
    await finalStarted.future;
    final Future<void> next = service.processAudioChunk(_pcmFrame(2000));
    await Future<void>.delayed(Duration.zero);

    expect(service.routeRevision, routeRevision);
    expect(operations, isNot(contains('grammar')));
    expect(operations, isNot(contains('next-command-pcm')));

    blockedFinal.complete(_json(text: 'жёлтый'));
    await Future.wait<void>(<Future<void>>[
      switching,
      boundary,
      next,
    ]);
    await service.waitForProcessing();

    expect(operations,
        containsAllInOrder(<String>['grammar', 'next-command-pcm']));
    expect(service.sourceScreen, WearScreenId.help);
  });

  test(
      'identical free-text partial previews publish for consecutive utterances',
      () async {
    var currentSample = 0;
    final _FakeRecognizer command = _FakeRecognizer();
    final _FakeRecognizer freeText = _FakeRecognizer()
      ..acceptOverride = (bytes) async {
        currentSample = ByteData.sublistView(bytes).getInt16(0, Endian.little);
        return false;
      }
      ..partialOverride =
          () async => _json(partial: currentSample > 0 ? 'жёлтый' : '');
    final SpeechRecognitionService service = _service(
      command: command,
      freeText: freeText,
    );
    addTearDown(service.dispose);
    final List<int> utteranceIds = <int>[];
    service.segmentedResultsStream.listen((event) {
      if (event.lane == RecognitionLane.freeText &&
          event.kind == RecognitionKind.partial &&
          event.text == 'жёлтый') {
        utteranceIds.add(event.commandUtteranceId);
      }
    });
    await _start(service);

    await _processUtterance(service);
    await _processUtterance(service);
    await service.waitForProcessing();

    expect(utteranceIds, <int>[1, 2]);
  });
}

SpeechRecognitionService _service({
  required _FakeRecognizer command,
  required _FakeRecognizer freeText,
  int backlogBytes = 5120,
  int commandBacklogBytes = 64000,
  SpeechSegmenter? speechSegmenter,
  VoiceHintIndexCache? hintIndexCache,
  bool prewarmHints = true,
  VoiceDynamicItemsSnapshot dynamicItems = const VoiceDynamicItemsSnapshot(
    revision: 1,
    items: <VoiceDynamicItem>[
      VoiceDynamicItem(id: "yellow", label: "жёлтый"),
      VoiceDynamicItem(id: "mobile", label: "мобильный"),
    ],
  ),
}) {
  final VoiceActionCatalog actionCatalog = VoiceActionCatalog();
  final Set<String> reservedPhrases =
      actionCatalog.phrasesFor(WearScreenId.menu);
  final VoiceHintIndexCache cache = hintIndexCache ?? VoiceHintIndexCache();
  if (prewarmHints) {
    cache.store(
      snapshot: dynamicItems,
      screen: WearScreenId.menu.name,
      reservedPhrases: reservedPhrases,
      hints: VoiceHintGenerator.generate(
        dynamicItems,
        reservedPhrases: reservedPhrases,
      ),
    );
  }
  return SpeechRecognitionService(
    commandGrammar: const <String>['вверх', 'вниз', 'выбрать', '[unk]'],
    freeTextPipelineMode: FreeTextPipelineMode.liveWithReplayFallback,
    commandBacklogLimitBytes: commandBacklogBytes,
    freeTextBacklogLimitBytes: backlogBytes,
    speechSegmenter:
        speechSegmenter ?? SpeechSegmenter(calibrationDuration: Duration.zero),
    actionCatalog: actionCatalog,
    dynamicItemsProvider: (WearScreenId screen) => dynamicItems,
    voiceHintIndexCache: cache,
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
  await _silenceEndpoint(service);
}

Future<void> _silenceEndpoint(SpeechRecognitionService service) async {
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
  final List<String> partials = <String>[];
  final List<Uint8List> accepted = <Uint8List>[];
  Future<String> Function()? finalOverride;
  Future<String> Function()? partialOverride;
  Future<bool> Function(Uint8List bytes)? acceptOverride;
  void Function(Uint8List bytes)? onAccept;
  void Function(List<String> grammar)? onGrammar;
  Completer<void>? resetBlock;
  Completer<void>? resetStarted;
  Duration finalDelay = Duration.zero;
  int disposeCalls = 0;
  int finalCalls = 0;

  @override
  Future<bool> acceptWaveformBytes(Uint8List bytes) async {
    accepted.add(Uint8List.fromList(bytes));
    onAccept?.call(bytes);
    final Future<bool> Function(Uint8List bytes)? override = acceptOverride;
    if (override != null) return override(bytes);
    return endpoints.isEmpty ? false : endpoints.removeAt(0);
  }

  @override
  Future<void> dispose() async => disposeCalls++;

  @override
  Future<String> getFinalResult() async {
    finalCalls++;
    if (finalDelay > Duration.zero) await Future<void>.delayed(finalDelay);
    if (finals.isNotEmpty) return finals.removeAt(0);
    final Future<String> Function()? override = finalOverride;
    return override == null ? _json() : override();
  }

  @override
  Future<String> getPartialResult() async => partialOverride != null
      ? partialOverride!()
      : partials.isEmpty
          ? _json()
          : partials.removeAt(0);

  @override
  Future<String> getResult() async =>
      results.isEmpty ? _json() : results.removeAt(0);

  @override
  Future<void> reset() async {
    final Completer<void>? started = resetStarted;
    if (started != null && !started.isCompleted) started.complete();
    final Completer<void>? block = resetBlock;
    if (block != null) {
      resetBlock = null;
      await block.future;
    }
  }

  @override
  Future<void> setGrammar(List<String> grammar) async =>
      onGrammar?.call(grammar);
}
