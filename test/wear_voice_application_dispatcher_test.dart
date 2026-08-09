import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_glasses/modules/wear/application/ports/wear_glasses_output.dart';
import 'package:smart_glasses/modules/wear/application/ports/wear_navigation_output.dart';
import 'package:smart_glasses/modules/wear/application/wear_flow_controller.dart';
import 'package:smart_glasses/modules/wear/application/wear_navigation_entry.dart';
import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/application/wear_ui_lifecycle.dart';
import 'package:smart_glasses/modules/wear/application/wear_voice_application_dispatcher.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/voice_utterance_coordinator.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/wear_voice_command.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/wear_voice_command_admission.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/wear_voice_command_event.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/wear_voice_delay_event.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/wear_voice_phrase_event.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/wear_voice_preview_event.dart';
import 'package:smart_glasses/modules/wear/presentation/glasses/wear_glasses_payload.dart';

void main() {
  late _NoopGlassesOutput glasses;
  late _RecordingNavigationOutput navigation;
  late WearFlowController flow;
  late WearVoiceRevisionSnapshot revisions;
  late bool enabled;
  late bool acceptsCommands;
  late WearVoiceApplicationDispatcher dispatcher;

  setUp(() {
    glasses = _NoopGlassesOutput();
    navigation = _RecordingNavigationOutput();
    flow = WearFlowController(
      glassesOutput: glasses,
      navigationOutput: navigation,
    )
      ..setUiLifecycle(WearUiLifecycle.active)
      ..enterScreen(WearScreenId.menu);
    revisions = (
      captureEpoch: 1,
      recognitionContextId: 1,
      routeRevision: 2,
      grammarRevision: 3,
      freeTextEpoch: 4,
      commandUtteranceId: 7,
      commandPartialRevision: 0,
      freeTextPartialRevision: 0,
    );
    enabled = true;
    acceptsCommands = true;
    dispatcher = WearVoiceApplicationDispatcher(
      flowController: flow,
      revisionSnapshotProvider: () => revisions,
      commandsEnabledProvider: () => enabled,
      commandsEnabledSetter: (bool value) => enabled = value,
      acceptsCommandsProvider: () => acceptsCommands,
      log: (_) {},
    );
  });

  test('duplicate typed command performs one business action', () async {
    final WearVoiceCommandEvent event = _commandEvent();

    expect(
      await dispatcher.dispatchCommand(event.command, event: event),
      WearVoiceAdmissionDecision.accepted,
    );
    expect(
      await dispatcher.dispatchCommand(event.command, event: event),
      WearVoiceAdmissionDecision.duplicate,
    );

    expect(flow.state.menuFocusedIndex, 1);
  });

  test('stale microphone command cannot mutate the current session', () async {
    final WearVoiceCommandEvent staleStop = _commandEvent(
      command: WearVoiceCommand.stopMicrophone,
      captureEpoch: 0,
    );

    expect(
      await dispatcher.dispatchCommand(
        staleStop.command,
        event: staleStop,
      ),
      WearVoiceAdmissionDecision.stale,
    );
    expect(enabled, isTrue);
  });

  test('an in-flight event cannot execute concurrently twice', () async {
    final Completer<void> release = Completer<void>();
    var photoCalls = 0;
    flow.registerScreenActions(
      WearScreenId.menu,
      WearScreenActionHandler(onPhoto: () async {
        photoCalls++;
        await release.future;
      }),
    );
    final WearVoiceCommandEvent event = _commandEvent(
      command: WearVoiceCommand.takePhoto,
    );

    final Future<WearVoiceAdmissionDecision> first =
        dispatcher.dispatchCommand(event.command, event: event);
    await Future<void>.delayed(Duration.zero);
    expect(
      await dispatcher.dispatchCommand(event.command, event: event),
      WearVoiceAdmissionDecision.duplicate,
    );
    expect(photoCalls, 1);

    release.complete();
    expect(await first, WearVoiceAdmissionDecision.accepted);
  });

  test('command and phrase lanes cannot double-act one utterance', () async {
    var phraseCalls = 0;
    flow.registerScreenActions(
      WearScreenId.menu,
      WearScreenActionHandler(onPhrase: (_) => phraseCalls++),
    );
    final WearVoiceCommandEvent command = _commandEvent();
    final WearVoicePhraseEvent phrase = _phraseEvent(
      commandUtteranceId: command.commandUtteranceId,
      listRevision: 0,
    );

    expect(
      await dispatcher.dispatchCommand(command.command, event: command),
      WearVoiceAdmissionDecision.accepted,
    );
    expect(
      await dispatcher.dispatchPhrase(phrase.phrase, event: phrase),
      WearVoiceAdmissionDecision.duplicate,
    );
    expect(flow.state.menuFocusedIndex, 1);
    expect(phraseCalls, 0);
  });

  test('current yellow phrase selects the dynamic item exactly once', () async {
    const VoiceDynamicItemsSnapshot items = VoiceDynamicItemsSnapshot(
      revision: 9,
      items: <VoiceDynamicItem>[
        VoiceDynamicItem(id: 'white', label: 'Белый'),
        VoiceDynamicItem(
          id: 'yellow',
          label: 'Жёлтый',
          voiceAliases: <String>['желтый'],
        ),
      ],
    );
    final List<String> selections = <String>[];
    flow
      ..enterScreen(WearScreenId.printerSelect)
      ..registerScreenActions(
        WearScreenId.printerSelect,
        WearScreenActionHandler(
          dynamicVoiceItems: () => items,
          onDynamicItem: selections.add,
        ),
      );
    final WearVoicePhraseEvent event = _phraseEvent(
      screen: WearScreenId.printerSelect,
      listRevision: items.revision,
    );

    expect(
      await dispatcher.dispatchPhrase(event.phrase, event: event),
      WearVoiceAdmissionDecision.accepted,
    );
    expect(
      await dispatcher.dispatchPhrase(event.phrase, event: event),
      WearVoiceAdmissionDecision.duplicate,
    );
    expect(selections, <String>['yellow']);
  });

  test('stale yellow list cannot select a replacement item', () async {
    const VoiceDynamicItemsSnapshot items = VoiceDynamicItemsSnapshot(
      revision: 10,
      items: <VoiceDynamicItem>[
        VoiceDynamicItem(id: 'yellow-v2', label: 'Жёлтый'),
      ],
    );
    final List<String> selections = <String>[];
    flow
      ..enterScreen(WearScreenId.printerSelect)
      ..registerScreenActions(
        WearScreenId.printerSelect,
        WearScreenActionHandler(
          dynamicVoiceItems: () => items,
          onDynamicItem: selections.add,
        ),
      );
    final WearVoicePhraseEvent event = _phraseEvent(
      screen: WearScreenId.printerSelect,
      listRevision: 9,
    );

    expect(
      await dispatcher.dispatchPhrase(event.phrase, event: event),
      WearVoiceAdmissionDecision.stale,
    );
    expect(selections, isEmpty);
  });

  test('current dynamic preview uses production partial dispatch once',
      () async {
    const VoiceDynamicItemsSnapshot items = VoiceDynamicItemsSnapshot(
      revision: 9,
      items: <VoiceDynamicItem>[
        VoiceDynamicItem(id: 'yellow', label: 'Жёлтый'),
      ],
    );
    var partialCalls = 0;
    var usefulCalls = 0;
    flow
      ..enterScreen(WearScreenId.printerSelect)
      ..registerScreenActions(
        WearScreenId.printerSelect,
        WearScreenActionHandler(
          dynamicVoiceItems: () => items,
          onPartialPhrase: (_) {
            partialCalls++;
            return true;
          },
        ),
      );
    dispatcher = WearVoiceApplicationDispatcher(
      flowController: flow,
      revisionSnapshotProvider: () => revisions,
      commandsEnabledProvider: () => enabled,
      commandsEnabledSetter: (bool value) => enabled = value,
      acceptsCommandsProvider: () => acceptsCommands,
      onPreviewUseful: (_) => usefulCalls++,
      log: (_) {},
    );
    const WearVoicePreviewEvent current = WearVoicePreviewEvent(
      text: 'жёлтый',
      captureEpoch: 1,
      commandUtteranceId: 7,
      routeRevision: 2,
      grammarRevision: 3,
      freeTextEpoch: 4,
      sourceScreen: WearScreenId.printerSelect,
      partialRevision: 0,
      recognizedAtMillis: 1,
      listRevision: 9,
      segmentId: 11,
      itemId: 'yellow',
      isCommandLane: false,
    );

    expect(await dispatcher.dispatchPreview(current), isTrue);
    expect(partialCalls, 1);
    expect(usefulCalls, 1);

    expect(
      await dispatcher.dispatchPreview(const WearVoicePreviewEvent(
        text: 'жёлтый',
        captureEpoch: 1,
        commandUtteranceId: 7,
        routeRevision: 2,
        grammarRevision: 3,
        freeTextEpoch: 4,
        sourceScreen: WearScreenId.printerSelect,
        partialRevision: 1,
        recognizedAtMillis: 2,
        listRevision: 9,
        segmentId: 11,
        itemId: 'yellow',
        isCommandLane: false,
      )),
      isFalse,
    );
    expect(partialCalls, 1);
    expect(usefulCalls, 1);
  });

  test('processing feedback is projected and stale hide cannot erase it',
      () async {
    flow.rememberScreenPayload(WearScreenId.menu, WearGlassesPayload.menu());
    await flow.renderCurrentGlasses();
    const WearVoiceDelayEvent visible = WearVoiceDelayEvent(
      visible: true,
      captureEpoch: 1,
      segmentId: 11,
      commandUtteranceId: 7,
      sourceScreen: WearScreenId.menu,
      routeRevision: 2,
      grammarRevision: 3,
      freeTextEpoch: 4,
      kind: WearVoiceDelayKind.processing,
      statusText: 'Распознаю...',
    );

    expect(await dispatcher.dispatchDelay(visible), isTrue);
    expect(glasses.payloads.last.statusText, 'Распознаю...');

    expect(
      await dispatcher.dispatchDelay(const WearVoiceDelayEvent(
        visible: false,
        captureEpoch: 1,
        segmentId: 10,
        commandUtteranceId: 6,
        sourceScreen: WearScreenId.menu,
        routeRevision: 2,
        grammarRevision: 3,
        freeTextEpoch: 4,
        kind: WearVoiceDelayKind.processing,
      )),
      isFalse,
    );
    expect(glasses.payloads.last.statusText, 'Распознаю...');

    expect(
      await dispatcher.dispatchDelay(const WearVoiceDelayEvent(
        visible: false,
        captureEpoch: 1,
        segmentId: 11,
        commandUtteranceId: 7,
        sourceScreen: WearScreenId.menu,
        routeRevision: 2,
        grammarRevision: 3,
        freeTextEpoch: 4,
        kind: WearVoiceDelayKind.processing,
      )),
      isTrue,
    );
    expect(glasses.payloads.last.statusText, isNull);

    expect(
      await dispatcher.dispatchDelay(const WearVoiceDelayEvent(
        visible: true,
        captureEpoch: 1,
        segmentId: 12,
        commandUtteranceId: 8,
        sourceScreen: WearScreenId.menu,
        routeRevision: 2,
        grammarRevision: 3,
        freeTextEpoch: 4,
        kind: WearVoiceDelayKind.processing,
        statusText: 'Не распознано',
      )),
      isTrue,
    );
    expect(glasses.payloads.last.statusText, 'Не распознано');
  });

  test('suppressed event is consumed and cannot replay after resume', () async {
    enabled = false;
    final WearVoiceCommandEvent event = _commandEvent();

    expect(
      await dispatcher.dispatchCommand(event.command, event: event),
      WearVoiceAdmissionDecision.accepted,
    );
    enabled = true;
    expect(
      await dispatcher.dispatchCommand(event.command, event: event),
      WearVoiceAdmissionDecision.duplicate,
    );
    expect(flow.state.menuFocusedIndex, 0);
  });

  test('failed business action remains retryable', () async {
    var attempts = 0;
    flow.registerScreenActions(
      WearScreenId.menu,
      WearScreenActionHandler(onPhrase: (_) {
        attempts++;
        if (attempts == 1) throw StateError('temporary failure');
      }),
    );
    final WearVoicePhraseEvent event = _phraseEvent(listRevision: 0);

    await expectLater(
      dispatcher.dispatchPhrase(event.phrase, event: event),
      throwsStateError,
    );
    expect(
      await dispatcher.dispatchPhrase(event.phrase, event: event),
      WearVoiceAdmissionDecision.accepted,
    );
    expect(attempts, 2);
  });

  test('accepted phrase keeps canonical trace through business dispatch',
      () async {
    final List<String> logs = <String>[];
    dispatcher = WearVoiceApplicationDispatcher(
      flowController: flow,
      revisionSnapshotProvider: () => revisions,
      commandsEnabledProvider: () => enabled,
      commandsEnabledSetter: (bool value) => enabled = value,
      acceptsCommandsProvider: () => acceptsCommands,
      log: logs.add,
    );
    final WearVoicePhraseEvent event = _phraseEvent(listRevision: 0);

    expect(
      await dispatcher.dispatchPhrase(event.phrase, event: event),
      WearVoiceAdmissionDecision.accepted,
    );

    expect(
      logs.where((String message) => message.contains(event.traceId)),
      hasLength(2),
    );
  });
}

WearVoiceCommandEvent _commandEvent({
  WearVoiceCommand command = WearVoiceCommand.down,
  WearScreenId screen = WearScreenId.menu,
  int captureEpoch = 1,
  int commandUtteranceId = 7,
}) {
  return WearVoiceCommandEvent(
    command: command,
    traceId: 'trace-$commandUtteranceId',
    recognizedAtMillis: 1,
    asrMillis: 1,
    captureEpoch: captureEpoch,
    speechTurnId: commandUtteranceId,
    decoderGeneration: commandUtteranceId,
    commandUtteranceId: commandUtteranceId,
    sourceScreen: screen,
    routeRevision: 2,
    grammarRevision: 3,
  );
}

WearVoicePhraseEvent _phraseEvent({
  String phrase = 'жёлтый',
  WearScreenId screen = WearScreenId.menu,
  int commandUtteranceId = 7,
  int listRevision = 0,
}) {
  return WearVoicePhraseEvent(
    phrase: phrase,
    traceId: '1:$commandUtteranceId:$commandUtteranceId',
    captureEpoch: 1,
    speechTurnId: commandUtteranceId,
    decoderGeneration: commandUtteranceId,
    commandUtteranceId: commandUtteranceId,
    sourceScreen: screen,
    routeRevision: 2,
    grammarRevision: 3,
    freeTextEpoch: 4,
    listRevision: listRevision,
  );
}

class _NoopGlassesOutput implements WearGlassesOutput {
  final List<WearGlassesPayload> payloads = <WearGlassesPayload>[];

  @override
  Future<void> send(WearGlassesPayload payload) async {
    payloads.add(payload);
  }
}

class _RecordingNavigationOutput implements WearNavigationOutput {
  final List<WearScreenId> goToCalls = <WearScreenId>[];

  @override
  Future<void> goTo(WearScreenId screen, {Object? extra}) async {
    goToCalls.add(screen);
  }

  @override
  Future<void> back() async {}

  @override
  Future<void> home() async {}

  @override
  Future<void> replace(WearScreenId screen, {Object? extra}) async {}

  @override
  Future<void> synchronize(List<WearNavigationEntry> history) async {}
}
