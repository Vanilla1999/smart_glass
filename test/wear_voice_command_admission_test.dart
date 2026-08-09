import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/wear_voice_command.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/wear_voice_command_admission.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/wear_voice_command_event.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/wear_voice_phrase_event.dart';

void main() {
  const WearVoiceAdmissionContext current = (
    screen: WearScreenId.menu,
    captureEpoch: 1,
    routeRevision: 2,
    grammarRevision: 3,
    freeTextEpoch: 4,
    listRevision: 5,
  );

  test('rejects a non-positive completed-key capacity', () {
    expect(
      () => WearVoiceEventAdmissionGate(completedCapacity: 0),
      throwsArgumentError,
    );
  });

  test('accepts only the current command and phrase contexts', () {
    expect(
      isCurrentWearVoiceCommandEvent(
        _commandEvent(),
        screen: current.screen,
        captureEpoch: current.captureEpoch,
        routeRevision: current.routeRevision,
        grammarRevision: current.grammarRevision,
      ),
      isTrue,
    );
    expect(
      isCurrentWearVoicePhraseEvent(
        _phraseEvent(),
        screen: current.screen,
        captureEpoch: current.captureEpoch,
        routeRevision: current.routeRevision,
        grammarRevision: current.grammarRevision,
        freeTextEpoch: current.freeTextEpoch,
        listRevision: current.listRevision,
      ),
      isTrue,
    );
    expect(
      isCurrentWearVoicePhraseEvent(
        _phraseEvent(listRevision: 6),
        screen: current.screen,
        captureEpoch: current.captureEpoch,
        routeRevision: current.routeRevision,
        grammarRevision: current.grammarRevision,
        freeTextEpoch: current.freeTextEpoch,
        listRevision: current.listRevision,
      ),
      isFalse,
    );
  });

  test('stale events never invoke their action', () async {
    final WearVoiceEventAdmissionGate gate = WearVoiceEventAdmissionGate();
    var calls = 0;

    final WearVoiceAdmissionDecision decision = await gate.runCommand(
      _commandEvent(captureEpoch: 9),
      context: current,
      action: () => calls++,
    );

    expect(decision, WearVoiceAdmissionDecision.stale);
    expect(calls, 0);
    expect(gate.debugCompletedCount, 0);
  });

  test('a completed utterance is admitted exactly once', () async {
    final WearVoiceEventAdmissionGate gate = WearVoiceEventAdmissionGate();
    final WearVoiceCommandEvent event = _commandEvent();
    var calls = 0;

    expect(
      await gate.runCommand(
        event,
        context: current,
        action: () => calls++,
      ),
      WearVoiceAdmissionDecision.accepted,
    );
    expect(
      await gate.runCommand(
        event,
        context: current,
        action: () => calls++,
      ),
      WearVoiceAdmissionDecision.duplicate,
    );
    expect(calls, 1);
  });

  test('a concurrent delivery cannot overtake an in-flight action', () async {
    final WearVoiceEventAdmissionGate gate = WearVoiceEventAdmissionGate();
    final Completer<void> release = Completer<void>();
    var calls = 0;

    final Future<WearVoiceAdmissionDecision> first = gate.runCommand(
      _commandEvent(),
      context: current,
      action: () async {
        calls++;
        await release.future;
      },
    );
    await Future<void>.delayed(Duration.zero);

    expect(
      await gate.runCommand(
        _commandEvent(),
        context: current,
        action: () => calls++,
      ),
      WearVoiceAdmissionDecision.duplicate,
    );
    expect(gate.debugInFlightCount, 1);

    release.complete();
    expect(await first, WearVoiceAdmissionDecision.accepted);
    expect(calls, 1);
  });

  test('command and free-text phrase share one business-action key', () async {
    final WearVoiceEventAdmissionGate gate = WearVoiceEventAdmissionGate();
    var commandCalls = 0;
    var phraseCalls = 0;

    expect(
      await gate.runCommand(
        _commandEvent(),
        context: current,
        action: () => commandCalls++,
      ),
      WearVoiceAdmissionDecision.accepted,
    );
    expect(
      await gate.runPhrase(
        _phraseEvent(),
        context: current,
        action: () => phraseCalls++,
      ),
      WearVoiceAdmissionDecision.duplicate,
    );
    expect(commandCalls, 1);
    expect(phraseCalls, 0);
  });

  test('natural endpoints admit multiple utterances in one speech turn',
      () async {
    final WearVoiceEventAdmissionGate gate = WearVoiceEventAdmissionGate();
    var calls = 0;

    expect(
      await gate.runCommand(
        _commandEvent(commandUtteranceId: 7, speechTurnId: 1),
        context: current,
        action: () => calls++,
      ),
      WearVoiceAdmissionDecision.accepted,
    );
    expect(
      await gate.runCommand(
        _commandEvent(commandUtteranceId: 8, speechTurnId: 1),
        context: current,
        action: () => calls++,
      ),
      WearVoiceAdmissionDecision.accepted,
    );
    expect(calls, 2);
  });

  test('concurrent command and phrase race executes one action', () async {
    final WearVoiceEventAdmissionGate gate = WearVoiceEventAdmissionGate();
    final Completer<void> release = Completer<void>();
    var commandCalls = 0;
    var phraseCalls = 0;

    final Future<WearVoiceAdmissionDecision> command = gate.runCommand(
      _commandEvent(),
      context: current,
      action: () async {
        commandCalls++;
        await release.future;
      },
    );
    await Future<void>.delayed(Duration.zero);
    final WearVoiceAdmissionDecision phrase = await gate.runPhrase(
      _phraseEvent(),
      context: current,
      action: () => phraseCalls++,
    );
    release.complete();

    expect(await command, WearVoiceAdmissionDecision.accepted);
    expect(phrase, WearVoiceAdmissionDecision.duplicate);
    expect(commandCalls + phraseCalls, 1);
  });

  test('failed application work can be retried', () async {
    final WearVoiceEventAdmissionGate gate = WearVoiceEventAdmissionGate();
    var attempts = 0;

    await expectLater(
      gate.runCommand(
        _commandEvent(),
        context: current,
        action: () {
          attempts++;
          throw StateError('failed');
        },
      ),
      throwsStateError,
    );
    expect(gate.debugCompletedCount, 0);

    expect(
      await gate.runCommand(
        _commandEvent(),
        context: current,
        action: () => attempts++,
      ),
      WearVoiceAdmissionDecision.accepted,
    );
    expect(attempts, 2);
  });

  test('one current context remembers every older utterance in bounded space',
      () async {
    final WearVoiceEventAdmissionGate gate =
        WearVoiceEventAdmissionGate(completedCapacity: 2);

    for (int utterance = 1; utterance <= 1000; utterance++) {
      expect(
        await gate.runCommand(
          _commandEvent(commandUtteranceId: utterance),
          context: current,
          action: () {},
        ),
        WearVoiceAdmissionDecision.accepted,
      );
    }

    expect(gate.debugCompletedCount, 2);
    expect(
      await gate.runCommand(
        _commandEvent(commandUtteranceId: 1),
        context: current,
        action: () {},
      ),
      WearVoiceAdmissionDecision.duplicate,
    );
  });

  test('completed recognition contexts remain bounded', () async {
    final WearVoiceEventAdmissionGate gate =
        WearVoiceEventAdmissionGate(completedCapacity: 2);

    for (int revision = 1; revision <= 3; revision++) {
      final WearVoiceAdmissionContext context = (
        screen: WearScreenId.menu,
        captureEpoch: 1,
        routeRevision: revision,
        grammarRevision: 3,
        freeTextEpoch: 4,
        listRevision: 5,
      );
      expect(
        await gate.runCommand(
          _commandEvent(routeRevision: revision),
          context: context,
          action: () {},
        ),
        WearVoiceAdmissionDecision.accepted,
      );
    }

    expect(gate.debugCompletedCount, 2);
  });
}

WearVoiceCommandEvent _commandEvent({
  WearVoiceCommand command = WearVoiceCommand.down,
  WearScreenId screen = WearScreenId.menu,
  int captureEpoch = 1,
  int commandUtteranceId = 7,
  int? speechTurnId,
  int routeRevision = 2,
  int grammarRevision = 3,
}) {
  return WearVoiceCommandEvent(
    command: command,
    traceId: 'trace-$commandUtteranceId',
    recognizedAtMillis: 1,
    asrMillis: 1,
    captureEpoch: captureEpoch,
    speechTurnId: speechTurnId ?? commandUtteranceId,
    decoderGeneration: commandUtteranceId,
    commandUtteranceId: commandUtteranceId,
    sourceScreen: screen,
    routeRevision: routeRevision,
    grammarRevision: grammarRevision,
  );
}

WearVoicePhraseEvent _phraseEvent({
  String phrase = 'жёлтый',
  WearScreenId screen = WearScreenId.menu,
  int captureEpoch = 1,
  int commandUtteranceId = 7,
  int routeRevision = 2,
  int grammarRevision = 3,
  int freeTextEpoch = 4,
  int listRevision = 5,
}) {
  return WearVoicePhraseEvent(
    phrase: phrase,
    traceId: '$captureEpoch:$commandUtteranceId:$commandUtteranceId',
    captureEpoch: captureEpoch,
    speechTurnId: commandUtteranceId,
    decoderGeneration: commandUtteranceId,
    commandUtteranceId: commandUtteranceId,
    sourceScreen: screen,
    routeRevision: routeRevision,
    grammarRevision: grammarRevision,
    freeTextEpoch: freeTextEpoch,
    listRevision: listRevision,
  );
}
