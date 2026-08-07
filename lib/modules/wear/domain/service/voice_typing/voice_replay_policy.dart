enum VoiceReplayPurpose {
  /// A stable constrained hypothesis already exists and free text only gets a
  /// short chance to narrow it, for example `чудо` -> `чудо творожок`.
  refinement,

  /// The constrained recognizer has no safe result, so free text is the last
  /// recovery path, for example a missed `жёлтый` printer command.
  recovery,
}

class VoiceReplayPolicy {
  const VoiceReplayPolicy({
    this.refinementBudget = const Duration(seconds: 2),
    this.minimumRecoveryBudget = const Duration(seconds: 4),
    this.recoveryHeadroom = const Duration(seconds: 2),
    this.maximumRecoveryBudget = const Duration(seconds: 8),
    this.commandYieldPollInterval = const Duration(milliseconds: 5),
  });

  final Duration refinementBudget;
  final Duration minimumRecoveryBudget;
  final Duration recoveryHeadroom;
  final Duration maximumRecoveryBudget;
  final Duration commandYieldPollInterval;

  Duration budgetFor({
    required int pcmBytes,
    required VoiceReplayPurpose purpose,
    int sampleRate = 16000,
    int bytesPerSample = 2,
  }) {
    if (purpose == VoiceReplayPurpose.refinement) {
      return refinementBudget;
    }
    if (pcmBytes <= 0 || sampleRate <= 0 || bytesPerSample <= 0) {
      return minimumRecoveryBudget;
    }
    final int audioMs = pcmBytes * 1000 ~/ (sampleRate * bytesPerSample);
    final int requested = audioMs + recoveryHeadroom.inMilliseconds;
    final int minimum = minimumRecoveryBudget.inMilliseconds;
    final int maximum = maximumRecoveryBudget.inMilliseconds;
    final int bounded = requested < minimum
        ? minimum
        : requested > maximum
            ? maximum
            : requested;
    return Duration(milliseconds: bounded);
  }
}
