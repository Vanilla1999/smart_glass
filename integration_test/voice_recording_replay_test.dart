import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:smart_glasses/core/voice/native_voice_capture.dart';
import 'package:smart_glasses/modules/wear/application/ports/wear_glasses_output.dart';
import 'package:smart_glasses/modules/wear/application/ports/wear_navigation_output.dart';
import 'package:smart_glasses/modules/wear/application/wear_flow_controller.dart';
import 'package:smart_glasses/modules/wear/application/wear_flow_state.dart';
import 'package:smart_glasses/modules/wear/application/wear_navigation_entry.dart';
import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/application/wear_ui_lifecycle.dart';
import 'package:smart_glasses/modules/wear/application/wear_voice_application_dispatcher.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/voice_action_catalog.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/voice_utterance_coordinator.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/wear_voice_command_event.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/wear_voice_delay_event.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/wear_voice_preview_event.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/wear_voice_control_service.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/wear_voice_phrase_event.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_typing/audio_stream_service.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_typing/speech_recognition_service.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_typing/speech_segmenter.dart';
import 'package:smart_glasses/modules/wear/presentation/glasses/wear_glasses_payload.dart';
import 'package:smart_glasses/modules/wear/services/wear_voice_session.dart';

import '../test/support/replay_voice_capture.dart';

const String _wavAsset = String.fromEnvironment('VOICE_REPLAY_WAV_ASSET');
const String _caseName = String.fromEnvironment(
  'VOICE_REPLAY_CASE',
  defaultValue: 'availability',
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('recorded PCM reaches real Android Vosk and application flow',
      (WidgetTester tester) async {
    if (_wavAsset.isEmpty) {
      fail(
        'VOICE_REPLAY_WAV_ASSET is required. Use '
        'tool/voice_replay/run_android_fixture.sh.',
      );
    }
    final ByteData wavData = await rootBundle.load(_wavAsset);
    final Uint8List wavBytes = wavData.buffer.asUint8List(
      wavData.offsetInBytes,
      wavData.lengthInBytes,
    );

    final ReplayVoiceCapture capture = ReplayVoiceCapture();
    final AudioStreamService audio = AudioStreamService(nativeCapture: capture);
    final _RecordingNavigationOutput navigation = _RecordingNavigationOutput();
    final WearFlowController flow = WearFlowController(
      glassesOutput: _NoopGlassesOutput(),
      navigationOutput: navigation,
    )..setUiLifecycle(WearUiLifecycle.active);

    final WearScreenId screen = switch (_caseName) {
      'yellow' || 'unrecognized' => WearScreenId.printerSelect,
      'availability' || 'continuous' => WearScreenId.menu,
      _ => throw ArgumentError.value(
          _caseName,
          'VOICE_REPLAY_CASE',
          'Expected availability, yellow, unrecognized or continuous',
        ),
    };
    flow.enterScreen(screen);

    const VoiceDynamicItemsSnapshot printerItems = VoiceDynamicItemsSnapshot(
      revision: 1,
      items: <VoiceDynamicItem>[
        VoiceDynamicItem(id: 'white', label: 'Белый'),
        VoiceDynamicItem(
          id: 'yellow',
          label: 'Жёлтый',
          voiceAliases: <String>['желтый'],
        ),
      ],
    );
    final List<String> selectedItems = <String>[];
    if (screen == WearScreenId.printerSelect) {
      flow.registerScreenActions(
        screen,
        WearScreenActionHandler(
          dynamicVoiceItems: () => printerItems,
          onDynamicItem: selectedItems.add,
        ),
      );
    }
    if (_caseName == 'continuous') {
      flow.registerScreenActions(
        WearScreenId.printerSelect,
        WearScreenActionHandler(
          dynamicVoiceItems: () => printerItems,
          onDynamicItem: selectedItems.add,
        ),
      );
    }

    final VoiceActionCatalog catalog = VoiceActionCatalog();
    final List<String> grammar = catalog.grammarFor(screen);
    final SpeechRecognitionService speech = SpeechRecognitionService(
      audioStreamService: audio,
      commandGrammar: grammar,
      speechSegmenter: _caseName == 'continuous'
          ? SpeechSegmenter()
          : SpeechSegmenter(calibrationDuration: Duration.zero),
      dynamicItemsProvider: (WearScreenId candidate) =>
          candidate == WearScreenId.printerSelect
              ? printerItems
              : VoiceDynamicItemsSnapshot.empty,
    );
    final WearVoiceControlService control = WearVoiceControlService(
      speechRecognitionService: speech,
      screenProvider: () => flow.state.screen,
    );
    final WearVoiceSession voiceSession = WearVoiceSession(
      speechRecognitionService: speech,
      actionCatalog: catalog,
      dynamicGrammarPhrases: flow.voiceGrammarPhrasesFor,
    );
    Future<void> voiceConfiguration = Future<void>.value();
    void configureVoice(WearScreenId target, {bool force = false}) {
      voiceConfiguration = voiceSession.configureForScreen(
        target,
        force: force,
      );
      unawaited(voiceConfiguration.catchError(
        (Object error, StackTrace stackTrace) => print(
          '[VoiceReplayTest] configure voice failed screen=$target '
          'error=$error\n$stackTrace',
        ),
      ));
    }

    final StreamSubscription<WearScreenId> screenActions =
        flow.screenActionsChanged.listen((WearScreenId changedScreen) {
      if (changedScreen == flow.state.screen) {
        configureVoice(changedScreen, force: true);
      }
    });
    WearScreenId logicalScreen = flow.state.screen;
    final StreamSubscription<WearFlowState> flowStates =
        flow.stateStream.listen((WearFlowState state) {
      if (state.screen == logicalScreen) return;
      logicalScreen = state.screen;
      configureVoice(state.screen);
    });
    var enabled = true;
    var actionCount = 0;
    final Completer<void> firstAction = Completer<void>();
    final Completer<void> notRecognizedVisible = Completer<void>();
    final Completer<void> notRecognizedHidden = Completer<void>();
    var failureWasVisible = false;
    final WearVoiceApplicationDispatcher dispatcher =
        WearVoiceApplicationDispatcher(
      flowController: flow,
      revisionSnapshotProvider: () => (
        captureEpoch: speech.captureEpoch,
        recognitionContextId: speech.recognitionContextId,
        routeRevision: speech.routeRevision,
        grammarRevision: speech.grammarRevision,
        freeTextEpoch: speech.freeTextEpoch,
        commandUtteranceId: speech.commandUtteranceId,
        commandPartialRevision: speech.commandPartialRevision,
        freeTextPartialRevision: speech.freeTextPartialRevision,
      ),
      commandsEnabledProvider: () => enabled,
      commandsEnabledSetter: (bool value) => enabled = value,
      acceptsCommandsProvider: () => true,
      log: (String message) => print(message),
    );

    void markAction() {
      actionCount++;
      if (!firstAction.isCompleted) firstAction.complete();
    }

    navigation.onGoTo = (WearScreenId target) {
      if (_caseName == 'availability' &&
          target == WearScreenId.availabilityInteraction) {
        markAction();
      }
    };

    Future<void> dispatches = Future<void>.value();
    void enqueueDispatch(Future<void> Function() operation) {
      dispatches = dispatches.then<void>((_) => operation());
    }

    Future<void> drainDispatches() async {
      while (true) {
        final Future<void> current = dispatches;
        await current;
        await Future<void>.delayed(Duration.zero);
        if (identical(current, dispatches)) return;
      }
    }

    final StreamSubscription<WearVoiceCommandEvent> commands =
        control.commandEventStream.listen((WearVoiceCommandEvent event) {
      enqueueDispatch(() async {
        final decision =
            await dispatcher.dispatchCommand(event.command, event: event);
        if (_caseName == 'continuous') {
          print('VOICE_CONTINUOUS_EVENT ${jsonEncode(<String, Object?>{
                'stage': 'command',
                'command': event.command.name,
                'decision': decision.name,
                'screen': event.sourceScreen.name,
                'captureEpoch': event.captureEpoch,
                'utteranceId': event.commandUtteranceId,
                'traceId': event.traceId,
                'asrMillis': event.asrMillis,
              })}');
        }
      });
    });
    final StreamSubscription<WearVoicePhraseEvent> phrases =
        control.phraseEventStream.listen((WearVoicePhraseEvent event) {
      enqueueDispatch(() async {
        final int before = selectedItems.length;
        final decision =
            await dispatcher.dispatchPhrase(event.phrase, event: event);
        if (_caseName == 'continuous') {
          print('VOICE_CONTINUOUS_EVENT ${jsonEncode(<String, Object?>{
                'stage': 'phrase',
                'phrase': event.phrase,
                'decision': decision.name,
                'screen': event.sourceScreen.name,
                'captureEpoch': event.captureEpoch,
                'utteranceId': event.commandUtteranceId,
                'freeTextEpoch': event.freeTextEpoch,
                'listRevision': event.listRevision,
              })}');
        }
        if (_caseName == 'yellow' && selectedItems.length > before) {
          markAction();
        }
      });
    });

    final List<WearVoiceDelayEvent> delayEvents = <WearVoiceDelayEvent>[];
    final StreamSubscription<WearVoicePreviewEvent> previews =
        control.previewEventStream.listen((WearVoicePreviewEvent event) {
      enqueueDispatch(() async {
        await dispatcher.dispatchPreview(event);
      });
    });
    final StreamSubscription<WearVoiceDelayEvent> delays =
        control.delayEventStream.listen((WearVoiceDelayEvent event) {
      enqueueDispatch(() async {
        delayEvents.add(event);
        if (_caseName == 'continuous') {
          print('VOICE_CONTINUOUS_EVENT ${jsonEncode(<String, Object?>{
                'stage': 'feedback',
                'kind': event.kind.name,
                'visible': event.visible,
                'status': event.statusText,
                'screen': event.sourceScreen.name,
                'segmentId': event.segmentId,
                'utteranceId': event.commandUtteranceId,
              })}');
        }
        if (event.visible && event.statusText == 'Не распознано') {
          failureWasVisible = true;
          if (!notRecognizedVisible.isCompleted) {
            notRecognizedVisible.complete();
          }
        } else if (!event.visible && failureWasVisible) {
          if (!notRecognizedHidden.isCompleted) {
            notRecognizedHidden.complete();
          }
        }
        await dispatcher.dispatchDelay(event);
      });
    });

    try {
      await speech.prepare();
      configureVoice(screen, force: true);
      await voiceConfiguration;
      await speech.startListening();
      final List<Uint8List> packets =
          ReplayVoiceCapture.readMono16kWavBytes(wavBytes);
      await capture.replay(packets);
      await speech.waitForProcessing();
      await speech.stopListening();
      await voiceConfiguration;
      await speech.waitForProcessing();
      await drainDispatches();
      if (_caseName == 'continuous') {
        // The complete recording has no ground-truth application timeline.
        // Its structured trace is scored after the run instead.
      } else if (_caseName == 'unrecognized') {
        await notRecognizedVisible.future.timeout(const Duration(seconds: 8));
        await notRecognizedHidden.future.timeout(const Duration(seconds: 4));
      } else {
        await firstAction.future.timeout(const Duration(seconds: 8));
      }
      await drainDispatches();

      expect(capture.acknowledgements, everyElement(isTrue));
      expect(
        capture.acknowledgementRecords,
        List<ReplayPcmAcknowledgement>.generate(
          packets.length,
          (int sequence) => (
            status: NativePcmPacketEndpoint.accepted,
            leaseId: 1,
            sequence: sequence,
          ),
        ),
      );
      if (_caseName == 'continuous') {
        print('VOICE_CONTINUOUS_SUMMARY ${jsonEncode(<String, Object?>{
              'packets': packets.length,
              'acceptedAcks':
                  capture.acknowledgements.where((value) => value).length,
              'rejectedAcks':
                  capture.acknowledgements.where((value) => !value).length,
              'goTo':
                  navigation.goToCalls.map((screen) => screen.name).toList(),
              'replace':
                  navigation.replaceCalls.map((screen) => screen.name).toList(),
              'back': navigation.backCalls,
              'home': navigation.homeCalls,
              'selectedItems': selectedItems,
              'processingShown': delayEvents
                  .where((event) =>
                      event.kind == WearVoiceDelayKind.processing &&
                      event.visible)
                  .length,
              'notRecognizedShown': delayEvents
                  .where((event) =>
                      event.visible && event.statusText == 'Не распознано')
                  .length,
              'diagnostics': await speech.diagnostics(),
            })}');
      } else if (_caseName == 'yellow') {
        expect(actionCount, 1);
        expect(selectedItems, <String>['yellow']);
        expect(
          delayEvents.any((WearVoiceDelayEvent event) =>
              event.kind == WearVoiceDelayKind.processing && event.visible),
          isTrue,
        );
        expect(
          delayEvents.any((WearVoiceDelayEvent event) =>
              event.kind == WearVoiceDelayKind.processing && !event.visible),
          isTrue,
        );
      } else if (_caseName == 'availability') {
        expect(actionCount, 1);
        expect(
          navigation.goToCalls,
          <WearScreenId>[WearScreenId.availabilityInteraction],
        );
      } else {
        expect(actionCount, 0);
        expect(selectedItems, isEmpty);
        expect(navigation.goToCalls, isEmpty);
        expect(navigation.replaceCalls, isEmpty);
        expect(navigation.backCalls, 0);
        expect(navigation.homeCalls, 0);
        expect(flow.state.screen, WearScreenId.printerSelect);
        expect(
          delayEvents.any((WearVoiceDelayEvent event) =>
              event.visible && event.statusText == 'Не распознано'),
          isTrue,
        );
        expect(
          delayEvents.any((WearVoiceDelayEvent event) =>
              !event.visible && event.kind == WearVoiceDelayKind.processing),
          isTrue,
        );
      }
    } finally {
      await commands.cancel();
      await phrases.cancel();
      await previews.cancel();
      await delays.cancel();
      await screenActions.cancel();
      await flowStates.cancel();
      await control.dispose();
      await speech.dispose();
      await capture.dispose();
    }
  }, timeout: const Timeout(Duration(minutes: 30)));
}

class _NoopGlassesOutput implements WearGlassesOutput {
  @override
  Future<void> send(WearGlassesPayload payload) async {}
}

class _RecordingNavigationOutput implements WearNavigationOutput {
  final List<WearScreenId> goToCalls = <WearScreenId>[];
  final List<WearScreenId> replaceCalls = <WearScreenId>[];
  int backCalls = 0;
  int homeCalls = 0;
  void Function(WearScreenId screen)? onGoTo;

  @override
  Future<void> goTo(WearScreenId screen, {Object? extra}) async {
    goToCalls.add(screen);
    onGoTo?.call(screen);
  }

  @override
  Future<void> back() async {
    backCalls++;
  }

  @override
  Future<void> home() async {
    homeCalls++;
  }

  @override
  Future<void> replace(WearScreenId screen, {Object? extra}) async {
    replaceCalls.add(screen);
  }

  @override
  Future<void> synchronize(List<WearNavigationEntry> history) async {}
}
