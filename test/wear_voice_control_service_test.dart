import 'package:flutter_test/flutter_test.dart';
import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/recognition_arbiter.dart';
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

    test('T13 stable back is claimable before acoustic endpoint', () {
      final RecognitionArbiter arbiter = RecognitionArbiter(
        screenProvider: () => WearScreenId.help,
      );
      final SegmentedRecognitionResult partial = _event(
        text: 'назад',
        utteranceId: 4,
        kind: RecognitionKind.partial,
        screen: WearScreenId.help,
      );

      expect(arbiter.accept(partial)?.stableCandidate, same(partial));
      expect(arbiter.claimStable(partial)?.command, WearVoiceCommand.back);
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
        arbiter.accept(_event(
          text: 'печать',
          utteranceId: 1,
          kind: RecognitionKind.partial,
        )),
        isNull,
      );
    });

    test('microphone stop requires an endpoint', () {
      final RecognitionArbiter arbiter = RecognitionArbiter();

      expect(
        arbiter.accept(_event(
          text: 'стоп микрофон',
          utteranceId: 1,
          kind: RecognitionKind.partial,
        )),
        isNull,
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
