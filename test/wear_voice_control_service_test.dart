import 'package:flutter_test/flutter_test.dart';
import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/recognition_arbiter.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/voice_action_catalog.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/wear_voice_command.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_typing/segmented_recognition_result.dart';

void main() {
  group('command utterance arbitration', () {
    test('T11 two utterances execute inside one acoustic segment', () {
      WearScreenId screen = WearScreenId.availabilityInteraction;
      final RecognitionArbiter arbiter = RecognitionArbiter(
        screenProvider: () => screen,
      );

      final RecognitionArbitration? direct = arbiter.accept(_event(
        text: 'прямое сканирование',
        utteranceId: 1,
        screen: screen,
      ));
      screen = WearScreenId.availabilityDirectScan;
      final RecognitionArbitration? back = arbiter.accept(_event(
        text: 'назад',
        utteranceId: 2,
        screen: screen,
      ));

      expect(direct?.command, WearVoiceCommand.openDirectScan);
      expect(back?.command, WearVoiceCommand.back);
    });

    test('T12 partial and endpoint execute at most once', () {
      final RecognitionArbiter arbiter = RecognitionArbiter();

      expect(
        arbiter
            .accept(_event(
              text: 'вверх',
              utteranceId: 1,
              kind: RecognitionKind.partial,
            ))
            ?.command,
        WearVoiceCommand.up,
      );
      expect(
        arbiter.accept(_event(text: 'вверх', utteranceId: 1)),
        isNull,
      );
    });

    test('T02 false accessibility partial is ignored indefinitely', () {
      final RecognitionArbiter arbiter = RecognitionArbiter(
        screenProvider: () => WearScreenId.menu,
      );

      expect(
        arbiter
            .accept(_event(
              text: 'доступность',
              utteranceId: 4,
              kind: RecognitionKind.partial,
            ))
            ?.ignoredEndpointOnly,
        isTrue,
      );
      expect(arbiter.debugRetainedPartialCount, 0);
    });

    test('T03 false accessibility partial corrects to up at endpoint', () {
      final RecognitionArbiter arbiter = RecognitionArbiter();

      expect(
        arbiter
            .accept(_event(
              text: 'доступность',
              utteranceId: 5,
              kind: RecognitionKind.partial,
            ))
            ?.ignoredEndpointOnly,
        isTrue,
      );
      expect(
        arbiter.accept(_event(text: 'вверх', utteranceId: 5))?.command,
        WearVoiceCommand.up,
      );
    });

    test('T04 accessibility executes only at endpoint', () {
      final RecognitionArbiter arbiter = RecognitionArbiter();

      expect(
        arbiter
            .accept(_event(
              text: 'доступность',
              utteranceId: 6,
              kind: RecognitionKind.partial,
            ))
            ?.ignoredEndpointOnly,
        isTrue,
      );
      expect(
        arbiter.accept(_event(text: 'доступность', utteranceId: 6))?.command,
        WearVoiceCommand.openAvailability,
      );
    });

    test('T05 back executes only at endpoint', () {
      final RecognitionArbiter arbiter = RecognitionArbiter(
        screenProvider: () => WearScreenId.help,
      );

      expect(
        arbiter
            .accept(_event(
              text: 'назад',
              utteranceId: 7,
              kind: RecognitionKind.partial,
              screen: WearScreenId.help,
            ))
            ?.ignoredEndpointOnly,
        isTrue,
      );
      expect(
        arbiter
            .accept(_event(
              text: 'назад',
              utteranceId: 7,
              screen: WearScreenId.help,
            ))
            ?.command,
        WearVoiceCommand.back,
      );
    });

    for (final ({String text, WearVoiceCommand command, String id}) testCase
        in <({String text, WearVoiceCommand command, String id})>[
      (text: 'вверх', command: WearVoiceCommand.up, id: 'T06'),
      (text: 'вниз', command: WearVoiceCommand.down, id: 'T07'),
    ]) {
      test('${testCase.id} direction remains immediate and emits once', () {
        final RecognitionArbiter arbiter = RecognitionArbiter();

        expect(
          arbiter
              .accept(_event(
                text: testCase.text,
                utteranceId: 8,
                kind: RecognitionKind.partial,
              ))
              ?.command,
          testCase.command,
        );
        expect(
          arbiter.accept(_event(text: testCase.text, utteranceId: 8)),
          isNull,
        );
      });
    }

    test('T08 other route commands execute only at endpoint', () {
      final List<({String text, WearVoiceCommand command, WearScreenId screen})>
          cases = <({
        String text,
        WearVoiceCommand command,
        WearScreenId screen,
      })>[
        (
          text: 'справка',
          command: WearVoiceCommand.openHelp,
          screen: WearScreenId.menu,
        ),
        (
          text: 'настройки',
          command: WearVoiceCommand.openSettings,
          screen: WearScreenId.menu,
        ),
        (
          text: 'список',
          command: WearVoiceCommand.openList,
          screen: WearScreenId.availabilityInteraction,
        ),
        (
          text: 'прямое',
          command: WearVoiceCommand.openDirectScan,
          screen: WearScreenId.availabilityInteraction,
        ),
        (
          text: 'домой',
          command: WearVoiceCommand.home,
          screen: WearScreenId.availabilityInteraction,
        ),
        (
          text: 'фонарик',
          command: WearVoiceCommand.flashlight,
          screen: WearScreenId.availabilityDirectScan,
        ),
      ];

      for (int index = 0; index < cases.length; index++) {
        final testCase = cases[index];
        final RecognitionArbiter arbiter = RecognitionArbiter(
          screenProvider: () => testCase.screen,
        );
        final RecognitionArbitration? partial = arbiter.accept(_event(
          text: testCase.text,
          utteranceId: index + 20,
          kind: RecognitionKind.partial,
          screen: testCase.screen,
        ));
        expect(
          partial?.ignoredEndpointOnly,
          isTrue,
          reason: '${testCase.command} partial must be ignored',
        );
        expect(
          arbiter
              .accept(_event(
                text: testCase.text,
                utteranceId: index + 20,
                screen: testCase.screen,
              ))
              ?.command,
          testCase.command,
        );
      }
    });

    test('T09 global microphone commands execute only at endpoint', () {
      for (final testCase in <(String, WearVoiceCommand)>[
        ('стоп микрофон', WearVoiceCommand.stopMicrophone),
        ('старт микрофон', WearVoiceCommand.startMicrophone),
      ]) {
        final RecognitionArbiter arbiter = RecognitionArbiter();
        expect(
          arbiter
              .accept(_event(
                text: testCase.$1,
                utteranceId: 30,
                kind: RecognitionKind.partial,
              ))
              ?.ignoredEndpointOnly,
          isTrue,
        );
        expect(
          arbiter.accept(_event(text: testCase.$1, utteranceId: 30))?.command,
          testCase.$2,
        );
      }
    });

    test('T10 production partials never create stable candidates', () {
      final VoiceActionCatalog catalog = VoiceActionCatalog();
      for (final VoiceActionEntry action in catalog.actions) {
        for (final WearScreenId screen in action.screens) {
          if (!catalog.capabilities.canHandle(screen, action.command)) continue;
          for (final String alias in action.fastAliases) {
            final RecognitionArbiter arbiter = RecognitionArbiter(
              actionCatalog: catalog,
              screenProvider: () => screen,
            );
            final RecognitionArbitration? outcome = arbiter.accept(_event(
              text: alias,
              utteranceId: 40,
              kind: RecognitionKind.partial,
              screen: screen,
            ));
            expect(outcome?.stableCandidate, isNull);
            if (action.command == WearVoiceCommand.up ||
                action.command == WearVoiceCommand.down) {
              expect(outcome?.command, action.command);
            } else {
              expect(outcome?.ignoredEndpointOnly, isTrue);
            }
          }
        }
      }
    });

    test('T11 select endpoint behavior remains unchanged', () {
      final RecognitionArbiter arbiter = RecognitionArbiter();
      expect(
        arbiter
            .accept(_event(
              text: 'выбрать',
              utteranceId: 50,
              kind: RecognitionKind.partial,
            ))
            ?.ignoredEndpointOnly,
        isTrue,
      );
      expect(arbiter.debugRetainedPartialCount, 0);
      expect(
        arbiter.accept(_event(text: 'выбрать', utteranceId: 50))?.command,
        WearVoiceCommand.select,
      );
    });

    test('T14 old route endpoint is dropped', () {
      final RecognitionArbiter arbiter = RecognitionArbiter(
        screenProvider: () => WearScreenId.menu,
        routeRevisionProvider: () => 2,
        grammarRevisionProvider: () => 2,
      );

      expect(
        arbiter.accept(_event(
          text: 'доступность',
          utteranceId: 1,
          routeRevision: 1,
          grammarRevision: 1,
        )),
        isNull,
      );
    });

    test('T15 conflicting endpoint cannot execute after partial claim', () {
      final RecognitionArbiter arbiter = RecognitionArbiter();
      arbiter.accept(_event(
        text: 'вверх',
        utteranceId: 7,
        kind: RecognitionKind.partial,
      ));

      expect(
        arbiter.accept(_event(text: 'вниз', utteranceId: 7)),
        isNull,
      );
    });

    test('T16 next endpoint uses independent utterance id', () {
      final RecognitionArbiter arbiter = RecognitionArbiter();

      expect(
        arbiter.accept(_event(text: 'вверх', utteranceId: 1))?.command,
        WearVoiceCommand.up,
      );
      expect(
        arbiter.accept(_event(text: 'вниз', utteranceId: 2))?.command,
        WearVoiceCommand.down,
      );
    });

    test('T19 unknown endpoint does not execute action', () {
      final RecognitionArbiter arbiter = RecognitionArbiter();
      expect(arbiter.accept(_event(text: '[unk]', utteranceId: 1)), isNull);
    });

    test('T29 destructive confirmation action cannot run from partial', () {
      final RecognitionArbiter arbiter = RecognitionArbiter();
      expect(
        arbiter
            .accept(_event(
              text: 'печать',
              utteranceId: 1,
              kind: RecognitionKind.partial,
            ))
            ?.ignoredEndpointOnly,
        isTrue,
      );
    });

    test('microphone stop requires an endpoint', () {
      final RecognitionArbiter arbiter = RecognitionArbiter();

      expect(
        arbiter
            .accept(_event(
              text: 'стоп микрофон',
              utteranceId: 1,
              kind: RecognitionKind.partial,
            ))
            ?.ignoredEndpointOnly,
        isTrue,
      );
      expect(
        arbiter.accept(_event(text: 'стоп микрофон', utteranceId: 1))?.command,
        WearVoiceCommand.stopMicrophone,
      );
    });

    test('T31 command from another screen does not execute', () {
      final RecognitionArbiter arbiter = RecognitionArbiter(
        screenProvider: () => WearScreenId.menu,
      );
      expect(
        arbiter.accept(_event(text: 'прямое', utteranceId: 1)),
        isNull,
      );
    });

    test('partial state remains bounded across many utterances', () {
      final RecognitionArbiter arbiter = RecognitionArbiter();

      for (int utteranceId = 1; utteranceId <= 1000; utteranceId++) {
        arbiter.accept(_event(
          text: 'шум $utteranceId',
          utteranceId: utteranceId,
          kind: RecognitionKind.partial,
        ));
      }

      expect(arbiter.debugRetainedPartialCount, lessThanOrEqualTo(128));
    });
  });
}

SegmentedRecognitionResult _event({
  required String text,
  required int utteranceId,
  RecognitionKind kind = RecognitionKind.endpointResult,
  WearScreenId screen = WearScreenId.menu,
  int routeRevision = 1,
  int grammarRevision = 1,
}) {
  return SegmentedRecognitionResult(
    captureEpoch: 1,
    segmentId: 1,
    lane: RecognitionLane.command,
    kind: kind,
    text: text,
    lastChunkId: 1,
    parsedCommand: null,
    commandUtteranceId: utteranceId,
    routeRevision: routeRevision,
    grammarRevision: grammarRevision,
    sourceScreen: screen,
  );
}
