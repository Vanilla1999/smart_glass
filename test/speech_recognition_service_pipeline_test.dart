import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/wear_voice_command.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/wear_voice_control_service.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/wear_voice_phrase_event.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/voice_utterance_coordinator.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_typing/segmented_recognition_result.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_typing/speech_recognition_service.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_typing/speech_segmenter.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_typing/voice_typing_service.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_typing/voice_replay_ownership.dart';

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
    command.grammarFailuresRemaining = 2;

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
      ..resultSequence.add(_json(text: 'назад'));
    final List<_FakeRecognizer> recognizers = <_FakeRecognizer>[
      failed,
      recovered,
    ];
    final SpeechRecognitionService service = SpeechRecognitionService(
      commandGrammar: const <String>['вверх', '[unk]'],
      speechSegmenter: SpeechSegmenter(calibrationDuration: Duration.zero),
      recognizerFactory: (RecognitionLane lane, List<String> grammar) async =>
          recognizers.removeAt(0),
      recognizerOperationTimeout: const Duration(milliseconds: 20),
    );
    addTearDown(service.dispose);
    await service.prepare();
    final Completer<void> blockedGrammar = Completer<void>();
    failed.grammarBlock = blockedGrammar;

    await service.switchCommandGrammar(
      screen: WearScreenId.help,
      grammar: const <String>['назад', '[unk]'],
    );
    await service.startSession();
    service.beginProcessingCapture();
    final Future<SegmentedRecognitionResult> result = service
        .segmentedResultsStream
        .firstWhere((event) => event.kind == RecognitionKind.endpointResult);
    await service.processAudioChunk(_pcmFrame(1000));

    expect((await result).text, 'назад');
    expect(recovered.grammars.last, const <String>['назад', '[unk]']);
    expect(service.routeRevision, 2);
    expect(service.grammarRevision, 2);
    expect(failed.disposeCalls, 0);
    blockedGrammar.complete();
    await Future<void>.delayed(Duration.zero);
    expect(failed.disposeCalls, 1);
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
    expect(service.routeRevision, 101);
    expect(service.grammarRevision, 101);
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

  test('no-op grammar switch does not cancel active free-text replay',
      () async {
    final _FakeRecognizer command = _FakeRecognizer()
      ..endpointSequence.add(true)
      ..resultSequence.add(_json(text: 'не команда'));
    final Completer<bool> accepted = Completer<bool>();
    final _FakeRecognizer freeText = _FakeRecognizer()
      ..acceptOverride = ((_) => accepted.future)
      ..finalSequence.add(_json(text: 'молоко'));
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

    await service.processAudioChunk(_pcmFrame(1000));
    await service.switchCommandGrammar(
      screen: WearScreenId.menu,
      grammar: const <String>['вверх', '[unk]'],
    );
    accepted.complete(false);
    await service.waitForProcessing();

    expect((await result).text, 'молоко');
  });

  test('initial menu configuration accepts commands with positive revisions',
      () async {
    final _FakeRecognizer command = _FakeRecognizer()
      ..endpointSequence.add(true)
      ..resultSequence.add(_json(text: 'вверх'));
    final SpeechRecognitionService service = _service(command: command);
    final WearVoiceControlService control = WearVoiceControlService(
      speechRecognitionService: service,
      screenProvider: () => WearScreenId.menu,
    );
    addTearDown(control.dispose);
    addTearDown(service.dispose);
    await service.prepare();
    await service.startSession();
    service.beginProcessingCapture();
    final Future<WearVoiceCommand> result = control.commandStream.first;

    await service.processAudioChunk(_pcmFrame(1000));

    expect(await result, WearVoiceCommand.up);
    expect(service.routeRevision, 1);
    expect(service.grammarRevision, 1);
  });

  test('VoiceTypingService drops stale typed phrase context', () async {
    final _FakeRecognizer command = _FakeRecognizer();
    final SpeechRecognitionService service = _service(command: command);
    final StreamController<WearVoicePhraseEvent> phrases =
        StreamController<WearVoicePhraseEvent>.broadcast();
    final VoiceTypingService typing = VoiceTypingService(
      speechRecognitionService: service,
      resolvedPhrases: phrases.stream,
    );
    addTearDown(phrases.close);
    addTearDown(typing.dispose);
    addTearDown(service.dispose);
    final List<String> results = <String>[];
    typing.resultsStream.listen(results.add);

    phrases.add(const WearVoicePhraseEvent(
      phrase: 'один',
      captureEpoch: 1,
      commandUtteranceId: 1,
      sourceScreen: WearScreenId.help,
      routeRevision: 1,
      grammarRevision: 1,
    ));
    phrases.add(const WearVoicePhraseEvent(
      phrase: 'два',
      captureEpoch: 1,
      commandUtteranceId: 2,
      sourceScreen: WearScreenId.menu,
      routeRevision: 1,
      grammarRevision: 1,
    ));
    await Future<void>.delayed(Duration.zero);

    expect(results, <String>['2']);
  });

  test('grammar cutover never replays audio accepted by old grammar', () async {
    final _FakeRecognizer command = _FakeRecognizer();
    final SpeechRecognitionService service = _service(
      command: command,
      segmenter: SpeechSegmenter(
        calibrationDuration: Duration.zero,
        endpointSilence: const Duration(milliseconds: 40),
      ),
    );
    addTearDown(service.dispose);
    await service.prepare();
    await service.startSession();
    service.beginProcessingCapture();

    final Uint8List oldFrame = _pcmFrame(1000);
    final Uint8List newFrame = _pcmFrame(2000);
    await service.processAudioChunk(oldFrame);
    final Future<void> switching = service.switchCommandGrammar(
      screen: WearScreenId.help,
      grammar: const <String>['назад', '[unk]'],
    );
    var completed = false;
    switching.then((_) => completed = true);
    await Future<void>.delayed(Duration.zero);
    expect(completed, isFalse);
    await service.processAudioChunk(_pcmFrame(0));
    await service.processAudioChunk(_pcmFrame(0));
    await switching;
    await service.processAudioChunk(newFrame);

    expect(
        command.accepted, containsAllInOrder(<Uint8List>[oldFrame, newFrame]));
  });

  test('grammar request after frame admission waits for utterance boundary',
      () async {
    final Completer<void> firstGrammarBlock = Completer<void>();
    final Completer<void> firstGrammarStarted = Completer<void>();
    final _FakeRecognizer command = _FakeRecognizer();
    final SpeechRecognitionService service = _service(
      command: command,
      segmenter: SpeechSegmenter(
        calibrationDuration: Duration.zero,
        endpointSilence: const Duration(milliseconds: 40),
      ),
    );
    addTearDown(service.dispose);
    await service.prepare();
    await service.startSession();
    service.beginProcessingCapture();
    command
      ..grammarBlock = firstGrammarBlock
      ..grammarStarted = firstGrammarStarted;

    final Future<void> firstSwitch = service.switchCommandGrammar(
      screen: WearScreenId.help,
      grammar: const <String>['назад', '[unk]'],
    );
    await firstGrammarStarted.future;
    final Future<void> admitted = service.processAudioChunk(_pcmFrame(1000));
    final Future<void> deferred = service.switchCommandGrammar(
      screen: WearScreenId.settings,
      grammar: const <String>['домой', '[unk]'],
    );
    firstGrammarBlock.complete();
    await firstSwitch;
    await admitted;
    await Future<void>.delayed(Duration.zero);

    expect(command.grammars, isNot(contains(const <String>['домой', '[unk]'])));
    expect(service.sourceScreen, WearScreenId.help);

    await service.processAudioChunk(_pcmFrame(0));
    await service.processAudioChunk(_pcmFrame(0));
    await deferred;

    expect(command.grammars.last, const <String>['домой', '[unk]']);
    expect(service.sourceScreen, WearScreenId.settings);
  });

  test('deferred grammar switches coalesce and complete at the boundary',
      () async {
    final _FakeRecognizer command = _FakeRecognizer();
    final SpeechRecognitionService service = _service(
      command: command,
      segmenter: SpeechSegmenter(
        calibrationDuration: Duration.zero,
        endpointSilence: const Duration(milliseconds: 40),
      ),
    );
    addTearDown(service.dispose);
    await service.prepare();
    await service.startSession();
    service.beginProcessingCapture();

    await service.processAudioChunk(_pcmFrame(1000));
    final Future<void> first = service.switchCommandGrammar(
      screen: WearScreenId.help,
      grammar: const <String>['назад', '[unk]'],
    );
    final Future<void> second = service.switchCommandGrammar(
      screen: WearScreenId.settings,
      grammar: const <String>['домой', '[unk]'],
    );
    await service.processAudioChunk(_pcmFrame(0));
    await service.processAudioChunk(_pcmFrame(0));
    await Future.wait(<Future<void>>[first, second]);

    expect(service.sourceScreen, WearScreenId.settings);
    expect(command.grammars.last, const <String>['домой', '[unk]']);
    expect(command.grammars, isNot(contains(const <String>['назад', '[unk]'])));
  });

  test('deferred grammar failure reaches its caller', () async {
    final _FakeRecognizer command = _FakeRecognizer();
    final SpeechRecognitionService service = _service(
      command: command,
      segmenter: SpeechSegmenter(
        calibrationDuration: Duration.zero,
        endpointSilence: const Duration(milliseconds: 40),
      ),
    );
    addTearDown(service.dispose);
    await service.prepare();
    await service.startSession();
    service.beginProcessingCapture();

    await service.processAudioChunk(_pcmFrame(1000));
    command.grammarFailuresRemaining = 2;
    final Future<void> switching = service.switchCommandGrammar(
      screen: WearScreenId.help,
      grammar: const <String>['назад', '[unk]'],
    );
    await service.processAudioChunk(_pcmFrame(0));
    await service.processAudioChunk(_pcmFrame(0));

    await expectLater(switching, throwsStateError);
    expect(service.sourceScreen, WearScreenId.menu);
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

  test('free-text creation failure can be retried', () async {
    final _FakeRecognizer command = _FakeRecognizer()
      ..endpointSequence.add(true)
      ..resultSequence.add(_json(text: 'не команда'));
    final _FakeRecognizer freeText = _FakeRecognizer()
      ..finalSequence.add(_json(text: 'молоко'));
    int freeTextCreations = 0;
    final SpeechRecognitionService service = SpeechRecognitionService(
      commandGrammar: const <String>['вверх', '[unk]'],
      speechSegmenter: SpeechSegmenter(calibrationDuration: Duration.zero),
      recognizerFactory: (RecognitionLane lane, List<String> grammar) async {
        if (lane == RecognitionLane.command) return command;
        freeTextCreations++;
        if (freeTextCreations == 1) throw StateError('temporary failure');
        return freeText;
      },
    );
    addTearDown(service.dispose);
    await service.prepare();
    await service.startSession();
    service.beginProcessingCapture();

    await expectLater(service.setFreeTextEnabled(true), throwsStateError);
    await service.setFreeTextEnabled(true);
    final Future<SegmentedRecognitionResult> result = service
        .segmentedResultsStream
        .firstWhere((event) => event.lane == RecognitionLane.freeText);
    await service.processAudioChunk(_pcmFrame(1000));
    await service.waitForProcessing();

    expect((await result).text, 'молоко');
    expect(freeTextCreations, 2);
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
    expect(
      service.replayOwnership.status,
      VoiceReplayOwnershipStatus.timedOut,
    );
  });

  test('free-text timeout replaces recognizer for the next replay', () async {
    final _FakeRecognizer command = _FakeRecognizer()
      ..endpointSequence.addAll(<bool>[true, true])
      ..resultSequence.addAll(<String>[
        _json(text: 'не команда'),
        _json(text: 'не команда'),
      ]);
    final _FakeRecognizer blocked = _FakeRecognizer()
      ..acceptOverride = (_) => Completer<bool>().future;
    final _FakeRecognizer replacement = _FakeRecognizer()
      ..finalSequence.add(_json(text: 'яблоко'));
    final List<_FakeRecognizer> freeTextRecognizers = <_FakeRecognizer>[
      blocked,
      replacement,
    ];
    final SpeechRecognitionService service = _service(
      command: command,
      freeTextFactory: () async => freeTextRecognizers.removeAt(0),
      recognizerOperationTimeout: const Duration(milliseconds: 20),
    );
    addTearDown(service.dispose);
    await service.prepare();
    await service.startSession();
    service.beginProcessingCapture();
    await service.setFreeTextEnabled(true);

    await service.processAudioChunk(_pcmFrame(1000));
    await service.waitForProcessing();
    final Future<SegmentedRecognitionResult> result = service
        .segmentedResultsStream
        .firstWhere((event) => event.lane == RecognitionLane.freeText);
    await service.processAudioChunk(_pcmFrame(1000));
    await service.waitForProcessing();

    expect((await result).text, 'яблоко');
    expect(blocked.accepted, hasLength(1));
    expect(replacement.accepted, hasLength(1));
  });

  test('silence boundary separates repeated commands without duplicate action',
      () async {
    final _FakeRecognizer command = _FakeRecognizer()
      ..partialSequence.addAll(<String>[
        _json(partial: 'вверх'),
        _json(partial: 'вверх'),
        _json(partial: 'вверх'),
        _json(partial: 'вверх'),
      ])
      ..finalSequence.add(_json(text: 'вверх'));
    final SpeechRecognitionService service = _service(
      command: command,
      segmenter: SpeechSegmenter(
        calibrationDuration: Duration.zero,
        endpointSilence: const Duration(milliseconds: 40),
        maxSegmentDuration: const Duration(seconds: 30),
      ),
    );
    final WearVoiceControlService control = WearVoiceControlService(
      speechRecognitionService: service,
      screenProvider: () => WearScreenId.menu,
    );
    final List<WearVoiceCommand> actions = <WearVoiceCommand>[];
    final StreamSubscription<WearVoiceCommand> subscription =
        control.commandStream.listen(actions.add);
    addTearDown(subscription.cancel);
    addTearDown(control.dispose);
    addTearDown(service.dispose);
    await service.prepare();
    await service.startSession();
    service.beginProcessingCapture();

    await service.processAudioChunk(_pcmFrame(1000));
    await service.processAudioChunk(_pcmFrame(0));
    await service.processAudioChunk(_pcmFrame(0));
    expect(service.commandUtteranceId, 2);

    await service.processAudioChunk(_pcmFrame(1000));
    await service.waitForProcessing();

    expect(actions, <WearVoiceCommand>[
      WearVoiceCommand.up,
      WearVoiceCommand.up,
    ]);
    expect(command.finalCalls, 1);
    expect(service.commandUtteranceId, 2);
  });

  test('natural endpoint before silence boundary makes forced close a no-op',
      () async {
    final _FakeRecognizer command = _FakeRecognizer()
      ..endpointSequence.addAll(<bool>[false, false, true])
      ..resultSequence.add(_json(text: 'вверх'));
    final SpeechRecognitionService service = _service(
      command: command,
      segmenter: SpeechSegmenter(
        calibrationDuration: Duration.zero,
        endpointSilence: const Duration(milliseconds: 40),
        maxSegmentDuration: const Duration(seconds: 30),
      ),
    );
    addTearDown(service.dispose);
    await service.prepare();
    await service.startSession();
    service.beginProcessingCapture();

    await service.processAudioChunk(_pcmFrame(1000));
    await service.processAudioChunk(_pcmFrame(0));
    await service.processAudioChunk(_pcmFrame(0));

    expect(command.resultCalls, 1);
    expect(command.finalCalls, 0);
    expect(service.commandUtteranceId, 2);
  });

  test('next segment PCM waits for silence boundary reset', () async {
    final _FakeRecognizer command = _FakeRecognizer()
      ..finalSequence.add(_json(text: 'вверх'));
    final SpeechRecognitionService service = _service(
      command: command,
      segmenter: SpeechSegmenter(
        calibrationDuration: Duration.zero,
        endpointSilence: const Duration(milliseconds: 40),
        maxSegmentDuration: const Duration(seconds: 30),
      ),
    );
    addTearDown(service.dispose);
    await service.prepare();
    await service.startSession();
    service.beginProcessingCapture();
    final Completer<void> resetBlock = Completer<void>();
    final Completer<void> resetStarted = Completer<void>();
    command
      ..resetBlock = resetBlock
      ..resetStarted = resetStarted;

    await service.processAudioChunk(_pcmFrame(1000));
    await service.processAudioChunk(_pcmFrame(0));
    final Future<void> boundary = service.processAudioChunk(_pcmFrame(0));
    await resetStarted.future;
    final Future<void> nextSegment = service.processAudioChunk(_pcmFrame(1000));
    await Future<void>.delayed(Duration.zero);

    expect(command.accepted, hasLength(3));
    resetBlock.complete();
    await Future.wait<void>(<Future<void>>[boundary, nextSegment]);
    expect(command.accepted, hasLength(4));
    expect(service.commandUtteranceId, 2);
  });

  test('silence boundary timeout replaces uncertain command recognizer',
      () async {
    final Completer<String> blockedFinal = Completer<String>();
    final _FakeRecognizer failed = _FakeRecognizer()
      ..finalOverride = () => blockedFinal.future;
    final _FakeRecognizer replacement = _FakeRecognizer();
    final List<_FakeRecognizer> recognizers = <_FakeRecognizer>[
      failed,
      replacement,
    ];
    final SpeechRecognitionService service = SpeechRecognitionService(
      commandGrammar: const <String>['вверх', '[unk]'],
      speechSegmenter: SpeechSegmenter(
        calibrationDuration: Duration.zero,
        endpointSilence: const Duration(milliseconds: 40),
        maxSegmentDuration: const Duration(seconds: 30),
      ),
      recognizerFactory: (RecognitionLane lane, List<String> grammar) async =>
          recognizers.removeAt(0),
      recognizerOperationTimeout: const Duration(milliseconds: 20),
    );
    addTearDown(service.dispose);
    await service.prepare();
    await service.startSession();
    service.beginProcessingCapture();

    await service.processAudioChunk(_pcmFrame(1000));
    await service.processAudioChunk(_pcmFrame(0));
    await service.processAudioChunk(_pcmFrame(0));
    await service.processAudioChunk(_pcmFrame(1000));

    expect(failed.finalCalls, 1);
    expect(replacement.accepted, hasLength(1));
    expect(service.commandUtteranceId, 2);
    blockedFinal.complete(_json());
    await Future<void>.delayed(Duration.zero);
    expect(failed.disposeCalls, 1);
  });

  test('failed boundary replacement still disposes uncertain recognizer',
      () async {
    final Completer<String> blockedFinal = Completer<String>();
    final _FakeRecognizer failed = _FakeRecognizer()
      ..finalOverride = () => blockedFinal.future;
    int factoryCalls = 0;
    final SpeechRecognitionService service = SpeechRecognitionService(
      commandGrammar: const <String>['вверх', '[unk]'],
      speechSegmenter: SpeechSegmenter(
        calibrationDuration: Duration.zero,
        endpointSilence: const Duration(milliseconds: 40),
        maxSegmentDuration: const Duration(seconds: 30),
      ),
      recognizerFactory: (RecognitionLane lane, List<String> grammar) async {
        if (factoryCalls++ == 0) return failed;
        throw StateError('replacement failed');
      },
      recognizerOperationTimeout: const Duration(milliseconds: 20),
    );
    addTearDown(service.dispose);
    await service.prepare();
    await service.startSession();
    service.beginProcessingCapture();

    await service.processAudioChunk(_pcmFrame(1000));
    await service.processAudioChunk(_pcmFrame(0));
    await service.processAudioChunk(_pcmFrame(0));

    expect(failed.disposeCalls, 0);
    blockedFinal.complete(_json());
    await Future<void>.delayed(Duration.zero);
    expect(failed.disposeCalls, 1);
  });

  test('silence boundary separates different commands and utterance ids',
      () async {
    final _FakeRecognizer command = _FakeRecognizer()
      ..partialSequence.addAll(<String>[
        _json(partial: 'вниз'),
        _json(partial: 'вниз'),
        _json(partial: 'вниз'),
        _json(partial: 'вверх'),
      ])
      ..finalSequence.add(_json(text: 'вниз'));
    final SpeechRecognitionService service = _service(
      command: command,
      segmenter: SpeechSegmenter(
        calibrationDuration: Duration.zero,
        endpointSilence: const Duration(milliseconds: 40),
        maxSegmentDuration: const Duration(seconds: 30),
      ),
    );
    final WearVoiceControlService control = WearVoiceControlService(
      speechRecognitionService: service,
      screenProvider: () => WearScreenId.menu,
    );
    final List<WearVoiceCommand> actions = <WearVoiceCommand>[];
    final List<int> utteranceIds = <int>[];
    final StreamSubscription<WearVoiceCommand> commandSubscription =
        control.commandStream.listen(actions.add);
    final StreamSubscription<SegmentedRecognitionResult> resultSubscription =
        service.segmentedResultsStream.listen((event) {
      if (event.kind == RecognitionKind.partial &&
          event.parsedCommand != null) {
        utteranceIds.add(event.commandUtteranceId);
      }
    });
    addTearDown(commandSubscription.cancel);
    addTearDown(resultSubscription.cancel);
    addTearDown(control.dispose);
    addTearDown(service.dispose);
    await service.prepare();
    await service.startSession();
    service.beginProcessingCapture();

    await service.processAudioChunk(_pcmFrame(1000));
    await service.processAudioChunk(_pcmFrame(0));
    await service.processAudioChunk(_pcmFrame(0));
    await service.processAudioChunk(_pcmFrame(1000));
    await Future<void>.delayed(Duration.zero);

    expect(actions, <WearVoiceCommand>[
      WearVoiceCommand.down,
      WearVoiceCommand.up,
    ]);
    expect(utteranceIds, <int>[1, 2]);
  });

  test('silence no-command final replays buffered PCM to free-text', () async {
    final _FakeRecognizer command = _FakeRecognizer()
      ..finalSequence.add(_json(text: 'красное яблоко'));
    final _FakeRecognizer freeText = _FakeRecognizer()
      ..finalSequence.add(_json(text: 'красное яблоко'));
    final SpeechRecognitionService service = _service(
      command: command,
      freeTextFactory: () async => freeText,
      segmenter: SpeechSegmenter(
        calibrationDuration: Duration.zero,
        endpointSilence: const Duration(milliseconds: 40),
        maxSegmentDuration: const Duration(seconds: 30),
      ),
    );
    addTearDown(service.dispose);
    await service.prepare();
    await service.startSession();
    service.beginProcessingCapture();
    await service.setFreeTextEnabled(true);
    final Future<SegmentedRecognitionResult> result = service
        .segmentedResultsStream
        .firstWhere((event) => event.lane == RecognitionLane.freeText);

    await service.processAudioChunk(_pcmFrame(1000));
    await service.processAudioChunk(_pcmFrame(0));
    await service.processAudioChunk(_pcmFrame(0));
    await service.waitForProcessing();

    expect((await result).text, 'красное яблоко');
    expect(freeText.accepted, isNotEmpty);
  });

  test('exact advertised dynamic final skips free-text replay', () async {
    final _FakeRecognizer command = _FakeRecognizer()
      ..endpointSequence.addAll(<bool>[false, true])
      ..partialSequence.add(_json(partial: 'молочная'))
      ..resultSequence.add(_json(text: 'молочная'));
    final _FakeRecognizer freeText = _FakeRecognizer()
      ..finalSequence.add(_json(text: 'не должно использоваться'));
    const VoiceDynamicItemsSnapshot items = VoiceDynamicItemsSnapshot(
      revision: 7,
      items: <VoiceDynamicItem>[
        VoiceDynamicItem(id: 'dairy', label: 'Молочная'),
      ],
    );
    final SpeechRecognitionService service = _service(
      command: command,
      freeTextFactory: () async => freeText,
      dynamicItemsProvider: (_) => items,
    );
    final WearVoiceControlService control = WearVoiceControlService(
      speechRecognitionService: service,
      screenProvider: () => WearScreenId.availabilityGroup,
    );
    addTearDown(control.dispose);
    addTearDown(service.dispose);
    await service.prepare();
    await service.switchCommandGrammar(
      screen: WearScreenId.availabilityGroup,
      grammar: const <String>['назад', 'молочная', '[unk]'],
    );
    await service.prepareVoiceHints(WearScreenId.availabilityGroup);
    await service.startSession();
    service.beginProcessingCapture();
    await service.setFreeTextEnabled(true);
    final Future<String> phrase = control.phraseStream.first;
    final Future<SegmentedRecognitionResult> result =
        service.segmentedResultsStream.firstWhere((event) =>
            event.lane == RecognitionLane.freeText &&
            event.kind == RecognitionKind.streamFinal);

    await service.processAudioChunk(_pcmFrame(1000));
    await service.processAudioChunk(_pcmFrame(1000));

    final SegmentedRecognitionResult resolved =
        await result.timeout(const Duration(seconds: 1));
    expect(await phrase.timeout(const Duration(seconds: 1)), 'молочная');
    expect(resolved.text, 'молочная');
    expect(resolved.dynamicItemId, 'dairy');
    expect(resolved.listRevision, 7);
    expect(freeText.accepted, isEmpty);
    expect(freeText.finalCalls, 0);
  });

  test('corrected command final keeps free-text replay fallback', () async {
    final _FakeRecognizer command = _FakeRecognizer()
      ..endpointSequence.addAll(<bool>[false, true])
      ..partialSequence.add(_json(partial: 'молочная'))
      ..resultSequence.add(_json(text: 'бакалея'));
    final _FakeRecognizer freeText = _FakeRecognizer()
      ..finalSequence.add(_json(text: 'бакалея'));
    const VoiceDynamicItemsSnapshot items = VoiceDynamicItemsSnapshot(
      revision: 8,
      items: <VoiceDynamicItem>[
        VoiceDynamicItem(id: 'dairy', label: 'Молочная'),
        VoiceDynamicItem(id: 'grocery', label: 'Бакалея'),
      ],
    );
    final SpeechRecognitionService service = _service(
      command: command,
      freeTextFactory: () async => freeText,
      dynamicItemsProvider: (_) => items,
    );
    addTearDown(service.dispose);
    await service.prepare();
    await service.switchCommandGrammar(
      screen: WearScreenId.availabilityGroup,
      grammar: const <String>['назад', 'молочная', 'бакалея', '[unk]'],
    );
    await service.prepareVoiceHints(WearScreenId.availabilityGroup);
    await service.startSession();
    service.beginProcessingCapture();
    await service.setFreeTextEnabled(true);
    final Future<SegmentedRecognitionResult> result = service
        .segmentedResultsStream
        .firstWhere((event) => event.lane == RecognitionLane.freeText);

    await service.processAudioChunk(_pcmFrame(1000));
    await service.processAudioChunk(_pcmFrame(1000));
    await service.waitForProcessing();

    expect((await result).text, 'бакалея');
    expect(freeText.accepted, hasLength(1));
    expect(freeText.finalCalls, 1);
  });

  test('ambiguous runtime match keeps free-text replay fallback', () async {
    final _FakeRecognizer command = _FakeRecognizer()
      ..endpointSequence.addAll(<bool>[false, true])
      ..partialSequence.add(_json(partial: 'молочная'))
      ..resultSequence.add(_json(text: 'молочная'));
    final _FakeRecognizer freeText = _FakeRecognizer()
      ..finalSequence.add(_json(text: 'молочная'));
    const VoiceDynamicItemsSnapshot items = VoiceDynamicItemsSnapshot(
      revision: 9,
      items: <VoiceDynamicItem>[
        VoiceDynamicItem(id: 'dairy', label: 'Молочная'),
        VoiceDynamicItem(id: 'dairy-department', label: 'Молочный отдел'),
      ],
    );
    final SpeechRecognitionService service = _service(
      command: command,
      freeTextFactory: () async => freeText,
      dynamicItemsProvider: (_) => items,
    );
    addTearDown(service.dispose);
    await service.prepare();
    await service.switchCommandGrammar(
      screen: WearScreenId.availabilityGroup,
      grammar: const <String>['назад', 'молочная', 'молочный', '[unk]'],
    );
    await service.prepareVoiceHints(WearScreenId.availabilityGroup);
    await service.startSession();
    service.beginProcessingCapture();
    await service.setFreeTextEnabled(true);
    final Future<SegmentedRecognitionResult> result = service
        .segmentedResultsStream
        .firstWhere((event) => event.lane == RecognitionLane.freeText);

    await service.processAudioChunk(_pcmFrame(1000));
    await service.processAudioChunk(_pcmFrame(1000));
    await service.waitForProcessing();

    expect((await result).text, 'молочная');
    expect(freeText.accepted, hasLength(1));
    expect(freeText.finalCalls, 1);
  });

  for (final WearScreenId screen in const <WearScreenId>[
    WearScreenId.availabilityGroup,
    WearScreenId.availabilityProduct,
    WearScreenId.availabilityDirectScan,
    WearScreenId.printerSelect,
    WearScreenId.productSelect,
    WearScreenId.voiceClarification,
  ]) {
    test(
      'shared advertised command survives a non-matching replay on '
      '${screen.name}',
      () async {
        final _FakeRecognizer command = _FakeRecognizer()
          ..endpointSequence.addAll(<bool>[false, true])
          ..partialSequence.add(_json(partial: 'напиток'))
          ..resultSequence.add(_json(text: 'напиток'));
        final _FakeRecognizer freeText = _FakeRecognizer()
          ..finalSequence.add(_json(text: 'на итог'));
        const VoiceDynamicItemsSnapshot items = VoiceDynamicItemsSnapshot(
          revision: 11,
          items: <VoiceDynamicItem>[
            VoiceDynamicItem(id: 'cola', label: 'Напиток кола'),
            VoiceDynamicItem(id: 'lemon', label: 'Напиток лимон'),
          ],
        );
        final SpeechRecognitionService service = _service(
          command: command,
          freeTextFactory: () async => freeText,
          dynamicItemsProvider: (_) => items,
        );
        final WearVoiceControlService control = WearVoiceControlService(
          speechRecognitionService: service,
          screenProvider: () => screen,
        );
        addTearDown(control.dispose);
        addTearDown(service.dispose);
        await service.prepare();
        await service.switchCommandGrammar(
          screen: screen,
          grammar: const <String>['назад', 'напиток', '[unk]'],
        );
        await service.prepareVoiceHints(screen);
        await service.startSession();
        service.beginProcessingCapture();
        await service.setFreeTextEnabled(true);
        final Future<String> phrase = control.phraseStream.first;
        final Future<SegmentedRecognitionResult> result =
            service.segmentedResultsStream.firstWhere((event) =>
                event.lane == RecognitionLane.freeText &&
                event.kind == RecognitionKind.streamFinal);

        await service.processAudioChunk(_pcmFrame(1000));
        await service.processAudioChunk(_pcmFrame(1000));
        await service.waitForProcessing();

        final SegmentedRecognitionResult resolved =
            await result.timeout(const Duration(seconds: 1));
        expect(await phrase.timeout(const Duration(seconds: 1)), 'напиток');
        expect(resolved.text, 'напиток');
        expect(resolved.dynamicItemId, isNull);
        expect(freeText.accepted, isNotEmpty);
        expect(freeText.finalCalls, 1);
        expect(
          service.replayOwnership.status,
          VoiceReplayOwnershipStatus.resolvedAsDynamicPhrase,
        );
      },
    );
  }

  test('exact advertised printer final skips free-text replay', () async {
    final _FakeRecognizer command = _FakeRecognizer()
      ..endpointSequence.addAll(<bool>[false, true])
      ..partialSequence.add(_json(partial: 'зебра'))
      ..resultSequence.add(_json(text: 'зебра'));
    final _FakeRecognizer freeText = _FakeRecognizer()
      ..finalSequence.add(_json(text: 'не должно использоваться'));
    const VoiceDynamicItemsSnapshot items = VoiceDynamicItemsSnapshot(
      revision: 16,
      items: <VoiceDynamicItem>[
        VoiceDynamicItem(id: 'printer-1', label: 'Зебра первая'),
      ],
    );
    final SpeechRecognitionService service = _service(
      command: command,
      freeTextFactory: () async => freeText,
      dynamicItemsProvider: (_) => items,
    );
    addTearDown(service.dispose);
    await service.prepare();
    await service.switchCommandGrammar(
      screen: WearScreenId.printerSelect,
      grammar: const <String>['назад', 'зебра', '[unk]'],
    );
    await service.prepareVoiceHints(WearScreenId.printerSelect);
    await service.startSession();
    service.beginProcessingCapture();
    await service.setFreeTextEnabled(true);
    final Future<SegmentedRecognitionResult> result =
        service.segmentedResultsStream.firstWhere((event) =>
            event.lane == RecognitionLane.freeText &&
            event.kind == RecognitionKind.streamFinal);

    await service.processAudioChunk(_pcmFrame(1000));
    await service.processAudioChunk(_pcmFrame(1000));
    await service.waitForProcessing();

    final SegmentedRecognitionResult resolved =
        await result.timeout(const Duration(seconds: 1));
    expect(resolved.text, 'зебра');
    expect(resolved.dynamicItemId, 'printer-1');
    expect(freeText.accepted, isEmpty);
    expect(freeText.finalCalls, 0);
  });

  test('clarification uses hints generated after excluded words', () async {
    final _FakeRecognizer command = _FakeRecognizer()
      ..endpointSequence.addAll(<bool>[false, true])
      ..partialSequence.add(_json(partial: 'лимон'))
      ..resultSequence.add(_json(text: 'лимон'));
    final _FakeRecognizer freeText = _FakeRecognizer()
      ..finalSequence.add(_json(text: 'на итог'));
    const VoiceDynamicItemsSnapshot items = VoiceDynamicItemsSnapshot(
      revision: 17,
      excludedWords: <String>{'напиток'},
      items: <VoiceDynamicItem>[
        VoiceDynamicItem(id: 'lemon-small', label: 'Напиток лимон маленький'),
        VoiceDynamicItem(id: 'lemon-large', label: 'Напиток лимон большой'),
        VoiceDynamicItem(id: 'cola', label: 'Напиток кола большая'),
      ],
    );
    final SpeechRecognitionService service = _service(
      command: command,
      freeTextFactory: () async => freeText,
      dynamicItemsProvider: (_) => items,
    );
    addTearDown(service.dispose);
    await service.prepare();
    await service.switchCommandGrammar(
      screen: WearScreenId.voiceClarification,
      grammar: const <String>['назад', 'лимон', 'кола', '[unk]'],
    );
    await service.prepareVoiceHints(WearScreenId.voiceClarification);
    await service.startSession();
    service.beginProcessingCapture();
    await service.setFreeTextEnabled(true);
    final Future<SegmentedRecognitionResult> result =
        service.segmentedResultsStream.firstWhere((event) =>
            event.lane == RecognitionLane.freeText &&
            event.kind == RecognitionKind.streamFinal);

    await service.processAudioChunk(_pcmFrame(1000));
    await service.processAudioChunk(_pcmFrame(1000));
    await service.waitForProcessing();

    final SegmentedRecognitionResult resolved =
        await result.timeout(const Duration(seconds: 1));
    expect(resolved.text, 'лимон');
    expect(resolved.dynamicItemId, isNull);
    expect(freeText.finalCalls, 1);
  });

  test('printer list revision change cancels a captured command fallback',
      () async {
    final _FakeRecognizer command = _FakeRecognizer()
      ..endpointSequence.addAll(<bool>[false, true])
      ..partialSequence.add(_json(partial: 'принтер'))
      ..resultSequence.add(_json(text: 'принтер'));
    final Completer<void> replayStarted = Completer<void>();
    final Completer<bool> releaseReplay = Completer<bool>();
    final _FakeRecognizer firstFreeText = _FakeRecognizer()
      ..acceptOverride = (_) {
        if (!replayStarted.isCompleted) replayStarted.complete();
        return releaseReplay.future;
      }
      ..finalSequence.add(_json(text: 'на итог'));
    final _FakeRecognizer replacement = _FakeRecognizer();
    var factoryCalls = 0;
    var listRevision = 18;
    VoiceDynamicItemsSnapshot currentItems() => VoiceDynamicItemsSnapshot(
          revision: listRevision,
          items: const <VoiceDynamicItem>[
            VoiceDynamicItem(id: 'white', label: 'Принтер белый'),
            VoiceDynamicItem(id: 'yellow', label: 'Принтер жёлтый'),
          ],
        );
    final SpeechRecognitionService service = _service(
      command: command,
      freeTextFactory: () async {
        factoryCalls++;
        return factoryCalls == 1 ? firstFreeText : replacement;
      },
      dynamicItemsProvider: (_) => currentItems(),
    );
    addTearDown(service.dispose);
    await service.prepare();
    await service.switchCommandGrammar(
      screen: WearScreenId.printerSelect,
      grammar: const <String>['назад', 'принтер', '[unk]'],
    );
    await service.prepareVoiceHints(WearScreenId.printerSelect);
    await service.startSession();
    service.beginProcessingCapture();
    await service.setFreeTextEnabled(true);
    final List<SegmentedRecognitionResult> results =
        <SegmentedRecognitionResult>[];
    service.segmentedResultsStream.listen(results.add);

    await service.processAudioChunk(_pcmFrame(1000));
    await service.processAudioChunk(_pcmFrame(1000));
    await replayStarted.future;
    listRevision++;
    releaseReplay.complete(false);
    await service.waitForProcessing();
    await Future<void>.delayed(Duration.zero);

    expect(
      results.where((event) => event.lane == RecognitionLane.freeText),
      isEmpty,
    );
    expect(firstFreeText.finalCalls, 0);
    expect(firstFreeText.disposeCalls, 1);
    expect(factoryCalls, 2);
    expect(
      service.replayOwnership.status,
      VoiceReplayOwnershipStatus.cancelledByContextChange,
    );
    expect(
      service.replayOwnership.cancellation,
      VoiceReplayContextCancellation.dynamicItemsChanged,
    );
  });

  for (final WearScreenId screen in const <WearScreenId>[
    WearScreenId.availabilityFill,
    WearScreenId.printCodeInput,
  ]) {
    test(
      'free-form input does not preserve a constrained list hypothesis on '
      '${screen.name}',
      () async {
        final _FakeRecognizer command = _FakeRecognizer()
          ..endpointSequence.addAll(<bool>[false, true])
          ..partialSequence.add(_json(partial: 'напиток'))
          ..resultSequence.add(_json(text: 'напиток'));
        final _FakeRecognizer freeText = _FakeRecognizer()
          ..finalSequence.add(_json(text: 'на итог'));
        const VoiceDynamicItemsSnapshot items = VoiceDynamicItemsSnapshot(
          revision: 19,
          items: <VoiceDynamicItem>[
            VoiceDynamicItem(id: 'cola', label: 'Напиток кола'),
            VoiceDynamicItem(id: 'lemon', label: 'Напиток лимон'),
          ],
        );
        final SpeechRecognitionService service = _service(
          command: command,
          freeTextFactory: () async => freeText,
          dynamicItemsProvider: (_) => items,
        );
        addTearDown(service.dispose);
        await service.prepare();
        await service.switchCommandGrammar(
          screen: screen,
          grammar: const <String>['напиток', '[unk]'],
        );
        await service.prepareVoiceHints(screen);
        await service.startSession();
        service.beginProcessingCapture();
        await service.setFreeTextEnabled(true);
        final Future<SegmentedRecognitionResult> result =
            service.segmentedResultsStream.firstWhere((event) =>
                event.lane == RecognitionLane.freeText &&
                event.kind == RecognitionKind.streamFinal);

        await service.processAudioChunk(_pcmFrame(1000));
        await service.processAudioChunk(_pcmFrame(1000));
        await service.waitForProcessing();

        final SegmentedRecognitionResult resolved =
            await result.timeout(const Duration(seconds: 1));
        expect(resolved.text, 'на итог');
        expect(resolved.dynamicItemId, isNull);
        expect(freeText.finalCalls, 1);
      },
    );
  }

  test('stable dynamic hint is not replaced by a replay command', () async {
    final _FakeRecognizer command = _FakeRecognizer()
      ..endpointSequence.addAll(<bool>[false, true])
      ..partialSequence.add(_json(partial: 'принтер'))
      ..resultSequence.add(_json(text: 'принтер'));
    final _FakeRecognizer freeText = _FakeRecognizer()
      ..finalSequence.add(_json(text: 'назад'));
    const VoiceDynamicItemsSnapshot items = VoiceDynamicItemsSnapshot(
      revision: 20,
      items: <VoiceDynamicItem>[
        VoiceDynamicItem(id: 'white', label: 'Принтер белый'),
        VoiceDynamicItem(id: 'yellow', label: 'Принтер жёлтый'),
      ],
    );
    final SpeechRecognitionService service = _service(
      command: command,
      freeTextFactory: () async => freeText,
      dynamicItemsProvider: (_) => items,
    );
    final WearVoiceControlService control = WearVoiceControlService(
      speechRecognitionService: service,
      screenProvider: () => WearScreenId.printerSelect,
    );
    final List<WearVoiceCommand> commands = <WearVoiceCommand>[];
    final List<String> phrases = <String>[];
    final StreamSubscription<WearVoiceCommand> commandSubscription =
        control.commandStream.listen(commands.add);
    final StreamSubscription<String> phraseSubscription =
        control.phraseStream.listen(phrases.add);
    addTearDown(commandSubscription.cancel);
    addTearDown(phraseSubscription.cancel);
    addTearDown(control.dispose);
    addTearDown(service.dispose);
    await service.prepare();
    await service.switchCommandGrammar(
      screen: WearScreenId.printerSelect,
      grammar: const <String>['назад', 'принтер', '[unk]'],
    );
    await service.prepareVoiceHints(WearScreenId.printerSelect);
    await service.startSession();
    service.beginProcessingCapture();
    await service.setFreeTextEnabled(true);

    await service.processAudioChunk(_pcmFrame(1000));
    await service.processAudioChunk(_pcmFrame(1000));
    await service.waitForProcessing();
    await Future<void>.delayed(Duration.zero);

    expect(commands, isEmpty);
    expect(phrases, <String>['принтер']);
  });

  test('replay command still works without a stable dynamic hint', () async {
    final _FakeRecognizer command = _FakeRecognizer()
      ..endpointSequence.add(true)
      ..resultSequence.add(_json());
    final _FakeRecognizer freeText = _FakeRecognizer()
      ..finalSequence.add(_json(text: 'назад'));
    final SpeechRecognitionService service = _service(
      command: command,
      freeTextFactory: () async => freeText,
      dynamicItemsProvider: (_) => const VoiceDynamicItemsSnapshot(
        revision: 21,
        items: <VoiceDynamicItem>[
          VoiceDynamicItem(id: 'white', label: 'Принтер белый'),
          VoiceDynamicItem(id: 'yellow', label: 'Принтер жёлтый'),
        ],
      ),
    );
    final WearVoiceControlService control = WearVoiceControlService(
      speechRecognitionService: service,
      screenProvider: () => WearScreenId.printerSelect,
    );
    final List<WearVoiceCommand> commands = <WearVoiceCommand>[];
    final List<String> phrases = <String>[];
    final StreamSubscription<WearVoiceCommand> commandSubscription =
        control.commandStream.listen(commands.add);
    final StreamSubscription<String> phraseSubscription =
        control.phraseStream.listen(phrases.add);
    addTearDown(commandSubscription.cancel);
    addTearDown(phraseSubscription.cancel);
    addTearDown(control.dispose);
    addTearDown(service.dispose);
    await service.prepare();
    await service.switchCommandGrammar(
      screen: WearScreenId.printerSelect,
      grammar: const <String>['назад', 'принтер', '[unk]'],
    );
    await service.prepareVoiceHints(WearScreenId.printerSelect);
    await service.startSession();
    service.beginProcessingCapture();
    await service.setFreeTextEnabled(true);

    await service.processAudioChunk(_pcmFrame(1000));
    await service.waitForProcessing();
    await Future<void>.delayed(Duration.zero);

    expect(commands, <WearVoiceCommand>[WearVoiceCommand.back]);
    expect(phrases, isEmpty);
  });

  test('unique replay inside the command candidate set wins arbitration',
      () async {
    final _FakeRecognizer command = _FakeRecognizer()
      ..endpointSequence.addAll(<bool>[false, true])
      ..partialSequence.add(_json(partial: 'напиток'))
      ..resultSequence.add(_json(text: 'напиток'));
    final _FakeRecognizer freeText = _FakeRecognizer()
      ..finalSequence.add(_json(text: 'напиток лимон'));
    const VoiceDynamicItemsSnapshot items = VoiceDynamicItemsSnapshot(
      revision: 12,
      items: <VoiceDynamicItem>[
        VoiceDynamicItem(id: 'cola', label: 'Напиток кола'),
        VoiceDynamicItem(id: 'lemon', label: 'Напиток лимон'),
      ],
    );
    final SpeechRecognitionService service = _service(
      command: command,
      freeTextFactory: () async => freeText,
      dynamicItemsProvider: (_) => items,
    );
    addTearDown(service.dispose);
    await service.prepare();
    await service.switchCommandGrammar(
      screen: WearScreenId.availabilityProduct,
      grammar: const <String>['назад', 'напиток', '[unk]'],
    );
    await service.prepareVoiceHints(WearScreenId.availabilityProduct);
    await service.startSession();
    service.beginProcessingCapture();
    await service.setFreeTextEnabled(true);
    final Future<SegmentedRecognitionResult> result =
        service.segmentedResultsStream.firstWhere((event) =>
            event.lane == RecognitionLane.freeText &&
            event.kind == RecognitionKind.streamFinal);

    await service.processAudioChunk(_pcmFrame(1000));
    await service.processAudioChunk(_pcmFrame(1000));
    await service.waitForProcessing();

    final SegmentedRecognitionResult resolved =
        await result.timeout(const Duration(seconds: 1));
    expect(resolved.text, 'напиток лимон');
    expect(resolved.dynamicItemId, 'lemon');
    expect(freeText.finalCalls, 1);
  });

  test('narrower ambiguous replay keeps the refined clarification phrase',
      () async {
    final _FakeRecognizer command = _FakeRecognizer()
      ..endpointSequence.addAll(<bool>[false, true])
      ..partialSequence.add(_json(partial: 'напиток'))
      ..resultSequence.add(_json(text: 'напиток'));
    final _FakeRecognizer freeText = _FakeRecognizer()
      ..finalSequence.add(_json(text: 'напиток лимон'));
    const VoiceDynamicItemsSnapshot items = VoiceDynamicItemsSnapshot(
      revision: 13,
      items: <VoiceDynamicItem>[
        VoiceDynamicItem(id: 'cola', label: 'Напиток кола'),
        VoiceDynamicItem(id: 'lemon-small', label: 'Напиток лимон 0.5'),
        VoiceDynamicItem(id: 'lemon-large', label: 'Напиток лимон 1.0'),
      ],
    );
    final SpeechRecognitionService service = _service(
      command: command,
      freeTextFactory: () async => freeText,
      dynamicItemsProvider: (_) => items,
    );
    addTearDown(service.dispose);
    await service.prepare();
    await service.switchCommandGrammar(
      screen: WearScreenId.availabilityProduct,
      grammar: const <String>['назад', 'напиток', '[unk]'],
    );
    await service.prepareVoiceHints(WearScreenId.availabilityProduct);
    await service.startSession();
    service.beginProcessingCapture();
    await service.setFreeTextEnabled(true);
    final Future<SegmentedRecognitionResult> result =
        service.segmentedResultsStream.firstWhere((event) =>
            event.lane == RecognitionLane.freeText &&
            event.kind == RecognitionKind.streamFinal);

    await service.processAudioChunk(_pcmFrame(1000));
    await service.processAudioChunk(_pcmFrame(1000));
    await service.waitForProcessing();

    final SegmentedRecognitionResult resolved =
        await result.timeout(const Duration(seconds: 1));
    expect(resolved.text, 'напиток лимон');
    expect(resolved.dynamicItemId, isNull);
  });

  test('distinguishing word alone cannot override a shared command hint',
      () async {
    final _FakeRecognizer command = _FakeRecognizer()
      ..endpointSequence.addAll(<bool>[false, true])
      ..partialSequence.add(_json(partial: 'напиток'))
      ..resultSequence.add(_json(text: 'напиток'));
    final _FakeRecognizer freeText = _FakeRecognizer()
      ..finalSequence.add(_json(text: 'лимон'));
    const VoiceDynamicItemsSnapshot items = VoiceDynamicItemsSnapshot(
      revision: 14,
      items: <VoiceDynamicItem>[
        VoiceDynamicItem(id: 'cola', label: 'Напиток кола'),
        VoiceDynamicItem(id: 'lemon', label: 'Напиток лимон'),
      ],
    );
    final SpeechRecognitionService service = _service(
      command: command,
      freeTextFactory: () async => freeText,
      dynamicItemsProvider: (_) => items,
    );
    addTearDown(service.dispose);
    await service.prepare();
    await service.switchCommandGrammar(
      screen: WearScreenId.availabilityProduct,
      grammar: const <String>['назад', 'напиток', '[unk]'],
    );
    await service.prepareVoiceHints(WearScreenId.availabilityProduct);
    await service.startSession();
    service.beginProcessingCapture();
    await service.setFreeTextEnabled(true);
    final Future<SegmentedRecognitionResult> result =
        service.segmentedResultsStream.firstWhere((event) =>
            event.lane == RecognitionLane.freeText &&
            event.kind == RecognitionKind.streamFinal);

    await service.processAudioChunk(_pcmFrame(1000));
    await service.processAudioChunk(_pcmFrame(1000));
    await service.waitForProcessing();

    final SegmentedRecognitionResult resolved =
        await result.timeout(const Duration(seconds: 1));
    expect(resolved.text, 'напиток');
    expect(resolved.dynamicItemId, isNull);
  });

  test('unrelated unique replay cannot override a shared command hint',
      () async {
    final _FakeRecognizer command = _FakeRecognizer()
      ..endpointSequence.addAll(<bool>[false, true])
      ..partialSequence.add(_json(partial: 'напиток'))
      ..resultSequence.add(_json(text: 'напиток'));
    final _FakeRecognizer freeText = _FakeRecognizer()
      ..finalSequence.add(_json(text: 'молоко'));
    const VoiceDynamicItemsSnapshot items = VoiceDynamicItemsSnapshot(
      revision: 15,
      items: <VoiceDynamicItem>[
        VoiceDynamicItem(id: 'cola', label: 'Напиток кола'),
        VoiceDynamicItem(id: 'lemon', label: 'Напиток лимон'),
        VoiceDynamicItem(id: 'milk', label: 'Молоко фермерское'),
      ],
    );
    final SpeechRecognitionService service = _service(
      command: command,
      freeTextFactory: () async => freeText,
      dynamicItemsProvider: (_) => items,
    );
    addTearDown(service.dispose);
    await service.prepare();
    await service.switchCommandGrammar(
      screen: WearScreenId.availabilityProduct,
      grammar: const <String>['назад', 'напиток', 'молоко', '[unk]'],
    );
    await service.prepareVoiceHints(WearScreenId.availabilityProduct);
    await service.startSession();
    service.beginProcessingCapture();
    await service.setFreeTextEnabled(true);
    final Future<SegmentedRecognitionResult> result =
        service.segmentedResultsStream.firstWhere((event) =>
            event.lane == RecognitionLane.freeText &&
            event.kind == RecognitionKind.streamFinal);

    await service.processAudioChunk(_pcmFrame(1000));
    await service.processAudioChunk(_pcmFrame(1000));
    await service.waitForProcessing();

    final SegmentedRecognitionResult resolved =
        await result.timeout(const Duration(seconds: 1));
    expect(resolved.text, 'напиток');
    expect(resolved.dynamicItemId, isNull);
  });

  test('non-advertised wider phrase keeps free-text replay fallback', () async {
    final _FakeRecognizer command = _FakeRecognizer()
      ..endpointSequence.addAll(<bool>[false, true])
      ..partialSequence.add(_json(partial: 'чудо коктейль'))
      ..resultSequence.add(_json(text: 'чудо коктейль'));
    final _FakeRecognizer freeText = _FakeRecognizer()
      ..finalSequence.add(_json(text: 'чудо коктейль молочный'));
    const VoiceDynamicItemsSnapshot items = VoiceDynamicItemsSnapshot(
      revision: 10,
      items: <VoiceDynamicItem>[
        VoiceDynamicItem(
          id: 'exact',
          label: 'Чудо коктейль молочный',
        ),
        VoiceDynamicItem(
          id: 'reordered',
          label: 'Коктейль чудо молочный',
        ),
      ],
    );
    final SpeechRecognitionService service = _service(
      command: command,
      freeTextFactory: () async => freeText,
      dynamicItemsProvider: (_) => items,
    );
    addTearDown(service.dispose);
    await service.prepare();
    await service.switchCommandGrammar(
      screen: WearScreenId.availabilityProduct,
      grammar: const <String>['назад', 'чудо коктейль', '[unk]'],
    );
    await service.prepareVoiceHints(WearScreenId.availabilityProduct);
    await service.startSession();
    service.beginProcessingCapture();
    await service.setFreeTextEnabled(true);
    final Future<SegmentedRecognitionResult> result =
        service.segmentedResultsStream.firstWhere((event) =>
            event.lane == RecognitionLane.freeText &&
            event.kind == RecognitionKind.streamFinal);

    await service.processAudioChunk(_pcmFrame(1000));
    await service.processAudioChunk(_pcmFrame(1000));
    await service.waitForProcessing();

    final SegmentedRecognitionResult resolved =
        await result.timeout(const Duration(seconds: 1));
    expect(resolved.text, 'чудо коктейль молочный');
    expect(resolved.dynamicItemId, isNull);
    expect(freeText.accepted, isNotEmpty);
    expect(freeText.finalCalls, 1);
  });

  test('queued command batch keeps its admission utterance identity', () async {
    final Completer<void> firstAcceptStarted = Completer<void>();
    final Completer<bool> releaseFirstAccept = Completer<bool>();
    var acceptCalls = 0;
    final _FakeRecognizer command = _FakeRecognizer()
      ..acceptOverride = (_) {
        acceptCalls++;
        if (acceptCalls == 1) {
          firstAcceptStarted.complete();
          return releaseFirstAccept.future;
        }
        return Future<bool>.value(false);
      }
      ..resultSequence.add(_json(text: 'вверх'));
    final SpeechRecognitionService service = _service(
      command: command,
      segmenter: SpeechSegmenter(
        calibrationDuration: Duration.zero,
        endpointSilence: const Duration(seconds: 5),
        maxSegmentDuration: const Duration(seconds: 30),
      ),
    );
    addTearDown(service.dispose);
    await service.prepare();
    await service.startSession();
    service.beginProcessingCapture();

    final Future<void> first = service.processAudioChunk(_pcmFrame(1000));
    await firstAcceptStarted.future;
    final Future<void> queuedTail = service.processAudioChunk(_pcmFrame(1000));
    releaseFirstAccept.complete(true);

    await Future.wait<void>(<Future<void>>[first, queuedTail]);
    await service.waitForProcessing();

    expect(command.accepted, hasLength(1));
    expect(service.commandUtteranceId, 2);
  });

  test('silent VAD tail after natural endpoint does not replay twice',
      () async {
    final _FakeRecognizer command = _FakeRecognizer()
      ..endpointSequence.add(true)
      ..resultSequence.add(_json(text: 'чудо'));
    final _FakeRecognizer freeText = _FakeRecognizer()
      ..finalSequence.addAll(<String>[
        _json(text: 'чудо коктейль молочный'),
        _json(text: 'ложный хвост'),
      ]);
    final SpeechRecognitionService service = _service(
      command: command,
      freeTextFactory: () async => freeText,
      segmenter: SpeechSegmenter(
        calibrationDuration: Duration.zero,
        endpointSilence: const Duration(milliseconds: 40),
        maxSegmentDuration: const Duration(seconds: 30),
      ),
    );
    addTearDown(service.dispose);
    await service.prepare();
    await service.startSession();
    service.beginProcessingCapture();
    await service.setFreeTextEnabled(true);
    final List<String> results = <String>[];
    service.segmentedResultsStream
        .where((event) => event.lane == RecognitionLane.freeText)
        .listen((event) => results.add(event.text));

    await service.processAudioChunk(_pcmFrame(1000));
    await service.processAudioChunk(_pcmFrame(0));
    await service.processAudioChunk(_pcmFrame(0));
    await service.waitForProcessing();

    expect(command.accepted, hasLength(1));
    expect(freeText.finalCalls, 1);
    expect(results, <String>['чудо коктейль молочный']);
    expect(service.commandUtteranceId, 2);
  });

  test('natural endpoint on an acoustic boundary aligns next admission',
      () async {
    final _FakeRecognizer command = _FakeRecognizer()
      ..endpointSequence.addAll(<bool>[true, true])
      ..resultSequence.addAll(<String>[
        _json(text: 'вверх'),
        _json(text: 'назад'),
      ]);
    final SpeechRecognitionService service = _service(
      command: command,
      segmenter: SpeechSegmenter(
        calibrationDuration: Duration.zero,
        maxSegmentDuration: const Duration(milliseconds: 20),
      ),
    );
    addTearDown(service.dispose);
    await service.prepare();
    await service.startSession();
    service.beginProcessingCapture();

    await service.processAudioChunk(_pcmFrame(1000));
    await service.processAudioChunk(_pcmFrame(1000));
    await service.waitForProcessing();

    expect(command.accepted, hasLength(2));
    expect(command.resultCalls, 2);
    expect(service.commandUtteranceId, 3);
  });

  test('new segment resynchronizes admission after a lagging endpoint',
      () async {
    final Completer<void> firstAcceptStarted = Completer<void>();
    final Completer<bool> releaseFirstAccept = Completer<bool>();
    var acceptCalls = 0;
    final _FakeRecognizer command = _FakeRecognizer()
      ..acceptOverride = (_) {
        acceptCalls++;
        if (acceptCalls == 1) {
          firstAcceptStarted.complete();
          return releaseFirstAccept.future;
        }
        return Future<bool>.value(false);
      }
      ..resultSequence.add(_json(text: 'вверх'));
    final SpeechRecognitionService service = _service(
      command: command,
      segmenter: _ScriptedSpeechSegmenter(const <SpeechSegment>[
        SpeechSegment(
          captureEpoch: 1,
          segmentId: 1,
          lastChunkId: 1,
          isEndpoint: false,
          started: true,
        ),
        SpeechSegment(
          captureEpoch: 1,
          segmentId: 2,
          lastChunkId: 2,
          isEndpoint: false,
          started: true,
        ),
        SpeechSegment(
          captureEpoch: 1,
          segmentId: 2,
          lastChunkId: 3,
          isEndpoint: false,
          started: false,
        ),
      ]),
    );
    addTearDown(service.dispose);
    await service.prepare();
    await service.startSession();
    service.beginProcessingCapture();

    final Future<void> first = service.processAudioChunk(_pcmFrame(1000));
    await firstAcceptStarted.future;
    final Future<void> staleQueued = service.processAudioChunk(_pcmFrame(1000));
    releaseFirstAccept.complete(true);
    await Future.wait<void>(<Future<void>>[first, staleQueued]);
    expect(service.commandUtteranceId, 2);

    await service.processAudioChunk(_pcmFrame(1000));
    await service.waitForProcessing();

    expect(command.accepted, hasLength(2));
    expect(command.resultCalls, 1);
    expect(service.commandUtteranceId, 2);
  });

  test('new speech rearms recognition after a natural endpoint', () async {
    final _FakeRecognizer command = _FakeRecognizer()
      ..endpointSequence.addAll(<bool>[true, true])
      ..resultSequence.addAll(<String>[
        _json(text: 'вверх'),
        _json(text: 'назад'),
      ]);
    final SpeechRecognitionService service = _service(
      command: command,
      segmenter: SpeechSegmenter(
        calibrationDuration: Duration.zero,
        endpointSilence: const Duration(seconds: 5),
        maxSegmentDuration: const Duration(seconds: 30),
      ),
    );
    addTearDown(service.dispose);
    await service.prepare();
    await service.startSession();
    service.beginProcessingCapture();

    await service.processAudioChunk(_pcmFrame(1000));
    await service.processAudioChunk(_pcmFrame(1000));
    await service.waitForProcessing();

    expect(command.accepted, hasLength(2));
    expect(command.resultCalls, 2);
    expect(service.commandUtteranceId, 3);
  });

  test('cancelled replay after PCM retires its free-text recognizer', () async {
    final _FakeRecognizer command = _FakeRecognizer()
      ..endpointSequence.addAll(<bool>[true, true])
      ..resultSequence.addAll(<String>[
        _json(text: 'первая'),
        _json(text: 'вторая'),
      ]);
    final Completer<void> firstReplayStarted = Completer<void>();
    final Completer<bool> releaseFirstReplay = Completer<bool>();
    final _FakeRecognizer firstFreeText = _FakeRecognizer()
      ..acceptOverride = (_) {
        if (!firstReplayStarted.isCompleted) firstReplayStarted.complete();
        return releaseFirstReplay.future;
      };
    final _FakeRecognizer replacement = _FakeRecognizer()
      ..finalSequence.add(_json(text: 'вторая'));
    var listRevision = 1;
    var factoryCalls = 0;
    final SpeechRecognitionService service = _service(
      command: command,
      freeTextFactory: () async {
        factoryCalls++;
        return factoryCalls == 1 ? firstFreeText : replacement;
      },
      dynamicItemsProvider: (_) => VoiceDynamicItemsSnapshot(
        revision: listRevision,
        items: const <VoiceDynamicItem>[],
      ),
    );
    addTearDown(service.dispose);
    await service.prepare();
    await service.startSession();
    service.beginProcessingCapture();
    await service.setFreeTextEnabled(true);
    final List<String> results = <String>[];
    service.segmentedResultsStream
        .where((event) => event.lane == RecognitionLane.freeText)
        .listen((event) => results.add(event.text));

    await service.processAudioChunk(_pcmFrame(1000));
    await firstReplayStarted.future;
    listRevision = 2;
    releaseFirstReplay.complete(false);
    await service.waitForProcessing();
    await Future<void>.delayed(Duration.zero);

    expect(factoryCalls, 2);
    expect(firstFreeText.disposeCalls, 1);
    expect(results, isEmpty);

    await service.processAudioChunk(_pcmFrame(1000));
    await service.waitForProcessing();

    expect(results, <String>['вторая']);
    expect(replacement.accepted, isNotEmpty);
    expect(
      service.replayOwnership.status,
      VoiceReplayOwnershipStatus.resolvedAsDynamicPhrase,
    );
  });

  test('empty trailing utterance does not discard delayed free-text replay',
      () async {
    final _FakeRecognizer command = _FakeRecognizer()
      ..endpointSequence.addAll(<bool>[true, true])
      ..resultSequence.addAll(<String>[
        _json(text: 'молочная'),
        _json(),
      ]);
    final Completer<void> firstReplayStarted = Completer<void>();
    final Completer<bool> releaseFirstReplay = Completer<bool>();
    var replayAcceptCalls = 0;
    final _FakeRecognizer freeText = _FakeRecognizer()
      ..acceptOverride = ((_) {
        replayAcceptCalls++;
        if (replayAcceptCalls == 1) {
          firstReplayStarted.complete();
          return releaseFirstReplay.future;
        }
        return Future<bool>.value(false);
      })
      ..finalSequence.addAll(<String>[
        _json(text: 'молочную'),
        _json(),
      ]);
    final SpeechRecognitionService service = _service(
      command: command,
      freeTextFactory: () async => freeText,
    );
    addTearDown(service.dispose);
    await service.prepare();
    await service.startSession();
    service.beginProcessingCapture();
    await service.setFreeTextEnabled(true);
    final List<SegmentedRecognitionResult> freeTextResults =
        <SegmentedRecognitionResult>[];
    final StreamSubscription<SegmentedRecognitionResult> subscription = service
        .segmentedResultsStream
        .where((event) => event.lane == RecognitionLane.freeText)
        .listen(freeTextResults.add);
    addTearDown(subscription.cancel);

    await service.processAudioChunk(_pcmFrame(1000));
    await firstReplayStarted.future;
    await service.processAudioChunk(_pcmFrame(0));
    releaseFirstReplay.complete(false);
    await service.waitForProcessing();

    expect(service.commandUtteranceId, 2);
    expect(freeTextResults.map((event) => event.text), <String>['молочную']);
    expect(freeTextResults.single.commandUtteranceId, 1);
    expect(
      service.replayOwnership.status,
      VoiceReplayOwnershipStatus.resolvedAsDynamicPhrase,
    );
  });

  test('free-text replay remains valid after more than 1700 milliseconds',
      () async {
    final _FakeRecognizer command = _FakeRecognizer()
      ..endpointSequence.add(true)
      ..resultSequence.add(_json(text: 'молочная'));
    final _FakeRecognizer freeText = _FakeRecognizer()
      ..acceptOverride = (_) async {
        await Future<void>.delayed(const Duration(milliseconds: 1750));
        return false;
      }
      ..finalSequence.add(_json(text: 'молочную'));
    final SpeechRecognitionService service = _service(
      command: command,
      freeTextFactory: () async => freeText,
      recognizerOperationTimeout: const Duration(seconds: 3),
    );
    addTearDown(service.dispose);
    await service.prepare();
    await service.startSession();
    service.beginProcessingCapture();
    await service.setFreeTextEnabled(true);
    final Future<SegmentedRecognitionResult> result = service
        .segmentedResultsStream
        .firstWhere((event) => event.lane == RecognitionLane.freeText);

    await service.processAudioChunk(_pcmFrame(1000));
    await service.waitForProcessing();

    expect((await result).text, 'молочную');
    expect(
      service.replayOwnership.status,
      VoiceReplayOwnershipStatus.resolvedAsDynamicPhrase,
    );
    expect(service.metricsSnapshot.slowReplayAcceptCount, 1);
    expect(service.metricsSnapshot.replayAcceptLatency.p99, greaterThan(1700));
  });

  test('free-text replay separates per-call timeout from total budget',
      () async {
    final _FakeRecognizer command = _FakeRecognizer()
      ..endpointSequence.addAll(<bool>[
        ...List<bool>.filled(23, false),
        true,
      ])
      ..resultSequence.add(_json(text: 'молочная'));
    final _FakeRecognizer freeText = _FakeRecognizer()
      ..acceptOverride = (_) async {
        await Future<void>.delayed(const Duration(milliseconds: 30));
        return false;
      }
      ..finalSequence.add(_json(text: 'молочная'));
    final SpeechRecognitionService service = _service(
      command: command,
      freeTextFactory: () async => freeText,
      recognizerOperationTimeout: const Duration(milliseconds: 100),
    );
    addTearDown(service.dispose);
    await service.prepare();
    await service.startSession();
    service.beginProcessingCapture();
    await service.setFreeTextEnabled(true);
    final Future<SegmentedRecognitionResult> result = service
        .segmentedResultsStream
        .firstWhere((event) => event.lane == RecognitionLane.freeText);

    for (int index = 0; index < 24; index++) {
      await service.processAudioChunk(_pcmFrame(1000));
    }
    await service.waitForProcessing();

    expect(
      (await result.timeout(const Duration(seconds: 1))).text,
      'молочная',
    );
    expect(freeText.accepted, hasLength(6));
    expect(freeText.finalCalls, 1);
    expect(
      service.replayOwnership.status,
      VoiceReplayOwnershipStatus.resolvedAsDynamicPhrase,
    );
  });

  test('newer actionable command supersedes delayed free-text replay',
      () async {
    final _FakeRecognizer command = _FakeRecognizer()
      ..endpointSequence.addAll(<bool>[true, true])
      ..resultSequence.addAll(<String>[
        _json(text: 'молочная'),
        _json(text: 'вверх'),
      ]);
    final Completer<void> firstReplayStarted = Completer<void>();
    final Completer<bool> releaseFirstReplay = Completer<bool>();
    final _FakeRecognizer freeText = _FakeRecognizer()
      ..acceptOverride = ((_) {
        firstReplayStarted.complete();
        return releaseFirstReplay.future;
      })
      ..finalSequence.add(_json(text: 'молочную'));
    final SpeechRecognitionService service = _service(
      command: command,
      freeTextFactory: () async => freeText,
    );
    addTearDown(service.dispose);
    await service.prepare();
    await service.startSession();
    service.beginProcessingCapture();
    await service.setFreeTextEnabled(true);
    final List<SegmentedRecognitionResult> freeTextResults =
        <SegmentedRecognitionResult>[];
    final StreamSubscription<SegmentedRecognitionResult> subscription = service
        .segmentedResultsStream
        .where((event) => event.lane == RecognitionLane.freeText)
        .listen(freeTextResults.add);
    addTearDown(subscription.cancel);

    await service.processAudioChunk(_pcmFrame(1000));
    await firstReplayStarted.future;
    await service.processAudioChunk(_pcmFrame(1000));
    releaseFirstReplay.complete(false);
    await service.waitForProcessing();

    expect(freeTextResults, isEmpty);
    expect(service.metricsSnapshot.staleResultCount, 1);
    expect(
      service.replayOwnership.status,
      VoiceReplayOwnershipStatus.supersededByActionableUtterance,
    );
  });

  test('actionable partial immediately supersedes older replay', () async {
    final _FakeRecognizer command = _FakeRecognizer()
      ..endpointSequence.addAll(<bool>[true, false])
      ..resultSequence.add(_json(text: 'молочная'))
      ..partialSequence.add(_json(partial: 'вверх'));
    final Completer<void> replayStarted = Completer<void>();
    final Completer<bool> releaseReplay = Completer<bool>();
    final _FakeRecognizer freeText = _FakeRecognizer()
      ..acceptOverride = (_) {
        replayStarted.complete();
        return releaseReplay.future;
      }
      ..finalSequence.add(_json(text: 'молочную'));
    final SpeechRecognitionService service = _service(
      command: command,
      freeTextFactory: () async => freeText,
    );
    final WearVoiceControlService control = WearVoiceControlService(
      speechRecognitionService: service,
      screenProvider: () => WearScreenId.menu,
    );
    final List<WearVoiceCommand> commands = <WearVoiceCommand>[];
    control.commandStream.listen(commands.add);
    addTearDown(control.dispose);
    addTearDown(service.dispose);
    await service.prepare();
    await service.startSession();
    service.beginProcessingCapture();
    await service.setFreeTextEnabled(true);

    await service.processAudioChunk(_pcmFrame(1000));
    await replayStarted.future;
    await service.processAudioChunk(_pcmFrame(1000));
    await Future<void>.delayed(Duration.zero);

    expect(commands, <WearVoiceCommand>[WearVoiceCommand.up]);
    expect(
      service.replayOwnership.status,
      VoiceReplayOwnershipStatus.supersededByActionableUtterance,
    );
    releaseReplay.complete(false);
    await service.waitForProcessing();
    expect(freeText.finalCalls, 0);
  });

  test('empty-command replay yields to a newer acoustic segment', () async {
    final _FakeRecognizer command = _FakeRecognizer()
      ..endpointSequence.addAll(<bool>[true, false])
      ..resultSequence.add(_json());
    final Completer<void> replayStarted = Completer<void>();
    final Completer<bool> releaseReplay = Completer<bool>();
    final _FakeRecognizer firstFreeText = _FakeRecognizer()
      ..acceptOverride = (_) {
        if (!replayStarted.isCompleted) replayStarted.complete();
        return releaseReplay.future;
      };
    final _FakeRecognizer replacement = _FakeRecognizer();
    var freeTextFactoryCalls = 0;
    final SpeechRecognitionService service = _service(
      command: command,
      freeTextFactory: () async {
        freeTextFactoryCalls++;
        return freeTextFactoryCalls == 1 ? firstFreeText : replacement;
      },
      segmenter: _ScriptedSpeechSegmenter(const <SpeechSegment>[
        SpeechSegment(
          captureEpoch: 1,
          segmentId: 1,
          lastChunkId: 1,
          isEndpoint: false,
          started: true,
        ),
        SpeechSegment(
          captureEpoch: 1,
          segmentId: 2,
          lastChunkId: 2,
          isEndpoint: false,
          started: true,
        ),
      ]),
    );
    addTearDown(service.dispose);
    await service.prepare();
    await service.startSession();
    service.beginProcessingCapture();
    await service.setFreeTextEnabled(true);

    await service.processAudioChunk(_pcmFrame(1000));
    await replayStarted.future;
    await service.processAudioChunk(_pcmFrame(1000));
    releaseReplay.complete(false);
    await service.waitForProcessing();
    await Future<void>.delayed(Duration.zero);

    expect(firstFreeText.finalCalls, 0);
    expect(firstFreeText.disposeCalls, 1);
    expect(freeTextFactoryCalls, 2);
    expect(
      service.replayOwnership.status,
      VoiceReplayOwnershipStatus.cancelledByContextChange,
    );
    expect(
      service.replayOwnership.cancellation,
      VoiceReplayContextCancellation.newerSegmentStarted,
    );
  });

  test('empty replay still applies final context cancellation', () async {
    final _FakeRecognizer command = _FakeRecognizer()
      ..endpointSequence.add(true)
      ..resultSequence.add(_json(text: 'молочная'));
    final Completer<bool> releaseReplay = Completer<bool>();
    final _FakeRecognizer freeText = _FakeRecognizer()
      ..acceptOverride = ((_) => releaseReplay.future)
      ..finalSequence.add(_json());
    var listRevision = 1;
    final SpeechRecognitionService service = _service(
      command: command,
      freeTextFactory: () async => freeText,
      dynamicItemsProvider: (_) => VoiceDynamicItemsSnapshot(
        revision: listRevision,
        items: const <VoiceDynamicItem>[],
      ),
    );
    addTearDown(service.dispose);
    await service.prepare();
    await service.startSession();
    service.beginProcessingCapture();
    await service.setFreeTextEnabled(true);

    await service.processAudioChunk(_pcmFrame(1000));
    listRevision = 2;
    releaseReplay.complete(false);
    await service.waitForProcessing();

    expect(
      service.replayOwnership.status,
      VoiceReplayOwnershipStatus.cancelledByContextChange,
    );
    expect(
      service.replayOwnership.cancellation,
      VoiceReplayContextCancellation.dynamicItemsChanged,
    );
  });

  test('failed replay replacement allows a later replay to recover', () async {
    final _FakeRecognizer command = _FakeRecognizer()
      ..endpointSequence.addAll(<bool>[true, true])
      ..resultSequence.addAll(<String>[
        _json(text: 'молочная'),
        _json(text: 'бакалея'),
      ]);
    final _FakeRecognizer blocked = _FakeRecognizer()
      ..acceptOverride = (_) => Completer<bool>().future;
    final _FakeRecognizer recovered = _FakeRecognizer()
      ..finalSequence.add(_json(text: 'бакалею'));
    var factoryCalls = 0;
    final SpeechRecognitionService service = _service(
      command: command,
      freeTextFactory: () async {
        factoryCalls++;
        if (factoryCalls == 1) return blocked;
        if (factoryCalls == 2) throw StateError('replacement failed');
        return recovered;
      },
      recognizerOperationTimeout: const Duration(milliseconds: 20),
    );
    addTearDown(service.dispose);
    await service.prepare();
    await service.startSession();
    service.beginProcessingCapture();
    await service.setFreeTextEnabled(true);

    await service.processAudioChunk(_pcmFrame(1000));
    await service.waitForProcessing();
    final Future<SegmentedRecognitionResult> result = service
        .segmentedResultsStream
        .firstWhere((event) => event.lane == RecognitionLane.freeText);
    await service.processAudioChunk(_pcmFrame(1000));
    await service.waitForProcessing();

    expect((await result).text, 'бакалею');
    expect(factoryCalls, 3);
  });

  test('dynamic list revision change rejects delayed free-text replay',
      () async {
    final _FakeRecognizer command = _FakeRecognizer()
      ..endpointSequence.add(true)
      ..resultSequence.add(_json(text: 'молочная'));
    final Completer<bool> releaseReplay = Completer<bool>();
    final _FakeRecognizer freeText = _FakeRecognizer();
    freeText.acceptOverride = (_) => releaseReplay.future;
    freeText.finalSequence.add(_json(text: 'молочную'));
    var listRevision = 1;
    final SpeechRecognitionService service = _service(
      command: command,
      freeTextFactory: () async => freeText,
      dynamicItemsProvider: (_) => VoiceDynamicItemsSnapshot(
        revision: listRevision,
        items: const <VoiceDynamicItem>[],
      ),
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
    listRevision = 2;
    releaseReplay.complete(false);
    await service.waitForProcessing();

    expect(results.where((event) => event.lane == RecognitionLane.freeText),
        isEmpty);
    expect(service.metricsSnapshot.staleResultCount, 1);
    expect(
      service.replayOwnership.cancellation,
      VoiceReplayContextCancellation.dynamicItemsChanged,
    );
  });

  test('two delayed dynamic utterances publish once in utterance order',
      () async {
    final _FakeRecognizer command = _FakeRecognizer()
      ..endpointSequence.addAll(<bool>[true, true])
      ..resultSequence.addAll(<String>[
        _json(text: 'молочная'),
        _json(text: 'бакалея'),
      ]);
    final Completer<bool> releaseFirst = Completer<bool>();
    var acceptCalls = 0;
    final _FakeRecognizer freeText = _FakeRecognizer()
      ..acceptOverride = (_) {
        acceptCalls++;
        return acceptCalls == 1 ? releaseFirst.future : Future.value(false);
      }
      ..finalSequence.addAll(<String>[
        _json(text: 'молочную'),
        _json(text: 'бакалею'),
      ]);
    final SpeechRecognitionService service = _service(
      command: command,
      freeTextFactory: () async => freeText,
    );
    addTearDown(service.dispose);
    await service.prepare();
    await service.startSession();
    service.beginProcessingCapture();
    await service.setFreeTextEnabled(true);
    final List<String> phrases = <String>[];
    service.segmentedResultsStream
        .where((event) => event.lane == RecognitionLane.freeText)
        .listen((event) => phrases.add(event.text));

    await service.processAudioChunk(_pcmFrame(1000));
    await service.processAudioChunk(_pcmFrame(1000));
    releaseFirst.complete(false);
    await service.waitForProcessing();

    expect(phrases, <String>['молочную', 'бакалею']);
  });

  test('empty forced final after command partial does not replay free-text',
      () async {
    final _FakeRecognizer command = _FakeRecognizer()
      ..partialSequence.addAll(<String>[
        _json(partial: 'вверх'),
        _json(partial: 'вверх'),
        _json(partial: 'вверх'),
      ])
      ..finalSequence.add(_json());
    final _FakeRecognizer freeText = _FakeRecognizer();
    final SpeechRecognitionService service = _service(
      command: command,
      freeTextFactory: () async => freeText,
      segmenter: SpeechSegmenter(
        calibrationDuration: Duration.zero,
        endpointSilence: const Duration(milliseconds: 40),
        maxSegmentDuration: const Duration(seconds: 30),
      ),
    );
    addTearDown(service.dispose);
    await service.prepare();
    await service.startSession();
    service.beginProcessingCapture();
    await service.setFreeTextEnabled(true);

    await service.processAudioChunk(_pcmFrame(1000));
    await service.processAudioChunk(_pcmFrame(0));
    await service.processAudioChunk(_pcmFrame(0));
    await service.waitForProcessing();

    expect(freeText.accepted, isEmpty);
    expect(service.commandUtteranceId, 2);
  });

  test('capture restart invalidates a pending silence boundary', () async {
    final Completer<String> blockedFinal = Completer<String>();
    final Completer<void> finalStarted = Completer<void>();
    final _FakeRecognizer command = _FakeRecognizer()
      ..finalOverride = () {
        finalStarted.complete();
        return blockedFinal.future;
      };
    final SpeechRecognitionService service = _service(
      command: command,
      segmenter: SpeechSegmenter(
        calibrationDuration: Duration.zero,
        endpointSilence: const Duration(milliseconds: 40),
        maxSegmentDuration: const Duration(seconds: 30),
      ),
    );
    addTearDown(service.dispose);
    await service.prepare();
    await service.startSession();
    service.beginProcessingCapture();

    await service.processAudioChunk(_pcmFrame(1000));
    await service.processAudioChunk(_pcmFrame(0));
    final Future<void> boundary = service.processAudioChunk(_pcmFrame(0));
    await finalStarted.future;
    service.beginProcessingCapture();
    blockedFinal.complete(_json(text: 'вверх'));
    await boundary;

    expect(service.commandUtteranceId, 1);
    expect(command.resetCalls, 1);
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
  VoiceDynamicItemsSnapshot Function(WearScreenId)? dynamicItemsProvider,
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
    dynamicItemsProvider: dynamicItemsProvider,
  );
}

class _ScriptedSpeechSegmenter extends SpeechSegmenter {
  _ScriptedSpeechSegmenter(this._segments)
      : super(calibrationDuration: Duration.zero);

  final List<SpeechSegment> _segments;
  int _index = 0;

  @override
  SpeechSegment? add(Uint8List bytes, int captureEpoch) {
    if (_index >= _segments.length) return null;
    return _segments[_index++];
  }

  @override
  SpeechSegmentDiagnostics get lastDiagnostics =>
      const SpeechSegmentDiagnostics(
        rms: 0.01,
        noiseFloorRms: 0.001,
        adaptiveOnRms: 0.0025,
        adaptiveOffRms: 0.0013,
        speaking: true,
      );
}

class _FakeRecognizer implements VoiceRecognizer {
  final List<bool> endpointSequence = <bool>[];
  final List<String> resultSequence = <String>[];
  final List<String> finalSequence = <String>[];
  final List<String> partialSequence = <String>[];
  final List<Uint8List> accepted = <Uint8List>[];
  final List<List<String>> grammars = <List<String>>[];
  bool failNextGrammar = false;
  int grammarFailuresRemaining = 0;
  Completer<void>? grammarBlock;
  Completer<void>? grammarStarted;
  Completer<void>? resetBlock;
  Completer<void>? resetStarted;
  Future<bool> Function(Uint8List bytes)? acceptOverride;
  Future<String> Function()? finalOverride;
  int resetCalls = 0;
  int resultCalls = 0;
  int finalCalls = 0;
  int disposeCalls = 0;

  @override
  Future<bool> acceptWaveformBytes(Uint8List bytes) async {
    accepted.add(Uint8List.fromList(bytes));
    final Future<bool> Function(Uint8List bytes)? override = acceptOverride;
    if (override != null) return override(bytes);
    return endpointSequence.isEmpty ? false : endpointSequence.removeAt(0);
  }

  @override
  Future<void> dispose() async {
    disposeCalls++;
  }

  @override
  Future<String> getFinalResult() async {
    finalCalls++;
    final Future<String> Function()? override = finalOverride;
    if (override != null) return override();
    return finalSequence.isEmpty ? _json() : finalSequence.removeAt(0);
  }

  @override
  Future<String> getPartialResult() async => partialSequence.isEmpty
      ? _json(partial: '')
      : partialSequence.removeAt(0);

  @override
  Future<String> getResult() async {
    resultCalls++;
    return resultSequence.isEmpty ? _json() : resultSequence.removeAt(0);
  }

  @override
  Future<void> reset() async {
    resetCalls++;
    final Completer<void>? started = resetStarted;
    if (started != null && !started.isCompleted) started.complete();
    final Completer<void>? block = resetBlock;
    if (block != null) {
      resetBlock = null;
      await block.future;
    }
  }

  @override
  Future<void> setGrammar(List<String> grammar) async {
    final Completer<void>? started = grammarStarted;
    if (started != null && !started.isCompleted) started.complete();
    final Completer<void>? block = grammarBlock;
    if (block != null) {
      grammarBlock = null;
      await block.future;
    }
    if (failNextGrammar || grammarFailuresRemaining > 0) {
      failNextGrammar = false;
      if (grammarFailuresRemaining > 0) grammarFailuresRemaining--;
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
