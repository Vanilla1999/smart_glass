import 'package:flutter_test/flutter_test.dart';

import '../tool/voice_replay/voice_replay_scorer.dart';

void main() {
  const ExpectedVoiceUtterance yellow = ExpectedVoiceUtterance(
    id: 'yellow-1',
    phrase: 'жёлтый',
    screen: 'printerSelect',
  );

  test('verified business action is success', () {
    final VoiceReplayScore score = scoreVoiceReplay(
      expected: const <ExpectedVoiceUtterance>[yellow],
      observations: const <VoiceReplayObservation>[
        VoiceReplayObservation(
          id: 'event-1',
          expectedId: 'yellow-1',
          screen: 'printerSelect',
          recognizedText: 'жёлтый',
          voskFinal: 'жёлтый',
          parserAccepted: true,
          businessAction: true,
        ),
      ],
    );

    expect(score.utterances.single.outcome, VoiceReplayOutcome.success);
    expect(score.falsePositives, isEmpty);
  });

  test('accepted phrase without business action is post-ASR drop', () {
    final VoiceReplayScore score = scoreVoiceReplay(
      expected: const <ExpectedVoiceUtterance>[yellow],
      observations: const <VoiceReplayObservation>[
        VoiceReplayObservation(
          id: 'event-1',
          expectedId: 'yellow-1',
          screen: 'printerSelect',
          recognizedText: 'жёлтый',
          voskFinal: 'жёлтый',
          parserAccepted: true,
          businessAction: false,
          dropReason: 'dynamicItemsChanged',
        ),
      ],
    );

    expect(score.utterances.single.outcome, VoiceReplayOutcome.postAsrDrop);
  });

  test('unknown business action evidence cannot be scored', () {
    expect(
      () => scoreVoiceReplay(
        expected: const <ExpectedVoiceUtterance>[yellow],
        observations: const <VoiceReplayObservation>[
          VoiceReplayObservation(
            id: 'event-1',
            expectedId: 'yellow-1',
            screen: 'printerSelect',
            recognizedText: 'жёлтый',
            voskFinal: 'жёлтый',
            parserAccepted: true,
            businessAction: null,
          ),
        ],
      ),
      throwsStateError,
    );
  });

  test('missing recognition is ASR miss', () {
    final VoiceReplayScore score = scoreVoiceReplay(
      expected: const <ExpectedVoiceUtterance>[yellow],
      observations: const <VoiceReplayObservation>[],
    );

    expect(score.utterances.single.outcome, VoiceReplayOutcome.asrMiss);
  });

  test('command unavailable on its recorded screen is invalid', () {
    const ExpectedVoiceUtterance hot = ExpectedVoiceUtterance(
      id: 'hot-1',
      phrase: 'горячий',
      screen: 'availabilityProduct',
      validForScreen: false,
    );
    final VoiceReplayScore score = scoreVoiceReplay(
      expected: const <ExpectedVoiceUtterance>[hot],
      observations: const <VoiceReplayObservation>[],
    );

    expect(
      score.utterances.single.outcome,
      VoiceReplayOutcome.invalidForScreen,
    );
  });

  test('unspoken accepted phrase is false positive', () {
    final VoiceReplayScore score = scoreVoiceReplay(
      expected: const <ExpectedVoiceUtterance>[yellow],
      observations: const <VoiceReplayObservation>[
        VoiceReplayObservation(
          id: 'box-event',
          screen: 'availabilityGroup',
          recognizedText: 'коробка',
          voskFinal: 'коробка',
          parserAccepted: true,
          businessAction: false,
        ),
      ],
    );

    expect(score.falsePositives.single.id, 'box-event');
    expect(score.utterances.single.outcome, VoiceReplayOutcome.asrMiss);
  });

  test('action for invalid command is also false positive', () {
    const ExpectedVoiceUtterance hot = ExpectedVoiceUtterance(
      id: 'hot-1',
      phrase: 'горячий',
      screen: 'availabilityProduct',
      validForScreen: false,
    );
    const VoiceReplayObservation action = VoiceReplayObservation(
      id: 'hot-event',
      expectedId: 'hot-1',
      screen: 'availabilityProduct',
      recognizedText: 'горячий',
      voskFinal: 'горячий',
      parserAccepted: true,
      businessAction: true,
    );
    final VoiceReplayScore score = scoreVoiceReplay(
      expected: const <ExpectedVoiceUtterance>[hot],
      observations: const <VoiceReplayObservation>[action],
    );

    expect(
      score.utterances.single.outcome,
      VoiceReplayOutcome.invalidForScreen,
    );
    expect(score.falsePositives, const <VoiceReplayObservation>[action]);
  });

  test('duplicate actionable observation is false positive', () {
    final VoiceReplayScore score = scoreVoiceReplay(
      expected: const <ExpectedVoiceUtterance>[yellow],
      observations: const <VoiceReplayObservation>[
        VoiceReplayObservation(
          id: 'event-1',
          expectedId: 'yellow-1',
          screen: 'printerSelect',
          recognizedText: 'жёлтый',
          parserAccepted: true,
          businessAction: true,
        ),
        VoiceReplayObservation(
          id: 'event-2',
          expectedId: 'yellow-1',
          screen: 'printerSelect',
          recognizedText: 'жёлтый',
          parserAccepted: true,
          businessAction: true,
        ),
      ],
    );

    expect(score.utterances.single.outcome, VoiceReplayOutcome.success);
    expect(score.falsePositives.single.id, 'event-2');
  });

  test('non-action feedback is ignored', () {
    final VoiceReplayScore score = scoreVoiceReplay(
      expected: const <ExpectedVoiceUtterance>[yellow],
      observations: const <VoiceReplayObservation>[
        VoiceReplayObservation(
          id: 'feedback',
          screen: 'printerSelect',
          recognizedText: '',
          parserAccepted: false,
          businessAction: false,
        ),
      ],
    );

    expect(score.falsePositives, isEmpty);
  });
}
