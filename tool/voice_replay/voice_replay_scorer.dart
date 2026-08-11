enum VoiceReplayOutcome {
  success,
  asrMiss,
  postAsrDrop,
  invalidForScreen,
}

class ExpectedVoiceUtterance {
  const ExpectedVoiceUtterance({
    required this.id,
    required this.phrase,
    required this.screen,
    this.validForScreen = true,
  });

  final String id;
  final String phrase;
  final String screen;
  final bool validForScreen;
}

class VoiceReplayObservation {
  const VoiceReplayObservation({
    required this.id,
    required this.screen,
    required this.recognizedText,
    required this.parserAccepted,
    required this.businessAction,
    this.expectedId,
    this.voskPartial,
    this.voskFinal,
    this.dropReason,
  });

  final String id;
  final String? expectedId;
  final String screen;
  final String recognizedText;
  final String? voskPartial;
  final String? voskFinal;
  final bool parserAccepted;
  final bool? businessAction;
  final String? dropReason;

  bool get isActionable => parserAccepted || businessAction == true;
}

class VoiceUtteranceScore {
  const VoiceUtteranceScore({
    required this.expected,
    required this.outcome,
    this.observation,
  });

  final ExpectedVoiceUtterance expected;
  final VoiceReplayOutcome outcome;
  final VoiceReplayObservation? observation;
}

class VoiceReplayScore {
  const VoiceReplayScore({
    required this.utterances,
    required this.falsePositives,
  });

  final List<VoiceUtteranceScore> utterances;
  final List<VoiceReplayObservation> falsePositives;
}

VoiceReplayScore scoreVoiceReplay({
  required List<ExpectedVoiceUtterance> expected,
  required List<VoiceReplayObservation> observations,
}) {
  final Map<String, ExpectedVoiceUtterance> expectedById =
      <String, ExpectedVoiceUtterance>{
    for (final ExpectedVoiceUtterance utterance in expected)
      utterance.id: utterance,
  };
  if (expectedById.length != expected.length) {
    throw ArgumentError('Expected utterance IDs must be unique');
  }

  final Map<String, List<VoiceReplayObservation>> observationsByExpected =
      <String, List<VoiceReplayObservation>>{};
  final List<VoiceReplayObservation> falsePositives =
      <VoiceReplayObservation>[];
  for (final VoiceReplayObservation observation in observations) {
    final String? expectedId = observation.expectedId;
    if (expectedId == null || !expectedById.containsKey(expectedId)) {
      if (observation.isActionable) falsePositives.add(observation);
      continue;
    }
    observationsByExpected
        .putIfAbsent(expectedId, () => <VoiceReplayObservation>[])
        .add(observation);
  }

  final List<VoiceUtteranceScore> scores = <VoiceUtteranceScore>[];
  for (final ExpectedVoiceUtterance utterance in expected) {
    final List<VoiceReplayObservation> matches =
        observationsByExpected[utterance.id] ??
            const <VoiceReplayObservation>[];
    final VoiceReplayObservation? observation =
        matches.isEmpty ? null : matches.first;
    for (final VoiceReplayObservation duplicate in matches.skip(1)) {
      if (duplicate.isActionable) falsePositives.add(duplicate);
    }

    if (!utterance.validForScreen) {
      if (observation?.isActionable == true) {
        falsePositives.add(observation!);
      }
      scores.add(VoiceUtteranceScore(
        expected: utterance,
        outcome: VoiceReplayOutcome.invalidForScreen,
        observation: observation,
      ));
      continue;
    }
    if (observation == null || observation.recognizedText.isEmpty) {
      scores.add(VoiceUtteranceScore(
        expected: utterance,
        outcome: VoiceReplayOutcome.asrMiss,
        observation: observation,
      ));
      continue;
    }
    final bool? businessAction = observation.businessAction;
    if (businessAction == null) {
      throw StateError(
        'Business action evidence is required for ${observation.id}',
      );
    }
    scores.add(VoiceUtteranceScore(
      expected: utterance,
      outcome: observation.parserAccepted && businessAction
          ? VoiceReplayOutcome.success
          : VoiceReplayOutcome.postAsrDrop,
      observation: observation,
    ));
  }

  return VoiceReplayScore(
    utterances: List<VoiceUtteranceScore>.unmodifiable(scores),
    falsePositives: List<VoiceReplayObservation>.unmodifiable(falsePositives),
  );
}
