import 'package:flutter_test/flutter_test.dart';
import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/recognition_arbiter.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/voice_action_catalog.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/wear_voice_command.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_typing/segmented_recognition_result.dart';

void main() {
  test('free-text fallback reclassifies an exact screen command', () {
    final RecognitionArbiter arbiter = RecognitionArbiter(
      screenProvider: () => WearScreenId.voiceClarification,
      routeRevisionProvider: () => 1,
      grammarRevisionProvider: () => 1,
      freeTextEpochProvider: () => 7,
    );

    final RecognitionArbitration? outcome = arbiter.accept(
      const SegmentedRecognitionResult(
        captureEpoch: 1,
        segmentId: 1,
        lane: RecognitionLane.freeText,
        kind: RecognitionKind.streamFinal,
        text: 'вниз',
        lastChunkId: 1,
        parsedCommand: null,
        commandUtteranceId: 1,
        routeRevision: 1,
        grammarRevision: 1,
        sourceScreen: WearScreenId.voiceClarification,
        freeTextEpoch: 7,
      ),
    );

    expect(outcome?.command, WearVoiceCommand.down);
    expect(outcome?.phrase, isNull);
  });

  test('home confirmation grammar matches its visible labels', () {
    final VoiceActionCatalog catalog = VoiceActionCatalog();

    expect(
      catalog.resolve(WearScreenId.homeConfirm, 'домой')?.command,
      WearVoiceCommand.home,
    );
    expect(
      catalog.resolve(WearScreenId.homeConfirm, 'отмена')?.command,
      WearVoiceCommand.cancel,
    );
    expect(
      catalog.resolve(WearScreenId.homeConfirm, 'да')?.command,
      WearVoiceCommand.yes,
    );
    expect(
      catalog.resolve(WearScreenId.homeConfirm, 'нет')?.command,
      WearVoiceCommand.no,
    );
  });
}
