import 'dart:async';

enum VoiceReplayPurpose {
  /// A stable constrained hypothesis already exists and free text only gets a
  /// short chance to narrow it, for example `чудо` -> `чудо творожок`.
  refinement,

  /// The constrained recognizer has no safe result, so free text is the last
  /// recovery path, for example a missed `жёлтый` printer command.
  recovery,
}

enum ReplayNativeStage {
  waitReady,
  create,
  reset,
  accept,
  endpointResult,
  finalResult,
  dispose,
}

class ReplayNativeTimeoutException extends TimeoutException {
  ReplayNativeTimeoutException(this.stage, Duration timeout)
      : super('Replay native ${stage.name} timed out', timeout);

  final ReplayNativeStage stage;
}

class VoiceNativeTimeoutPolicy {
  const VoiceNativeTimeoutPolicy({
    this.waitReady = const Duration(seconds: 3),
    this.create = const Duration(seconds: 3),
    this.reset = const Duration(seconds: 3),
    this.accept = const Duration(seconds: 3),
    this.endpointResult = const Duration(seconds: 3),
    this.finalResult = const Duration(seconds: 3),
    this.dispose = const Duration(seconds: 3),
  });

  final Duration waitReady;
  final Duration create;
  final Duration reset;
  final Duration accept;
  final Duration endpointResult;
  final Duration finalResult;
  final Duration dispose;

  Duration forStage(ReplayNativeStage stage) => switch (stage) {
        ReplayNativeStage.waitReady => waitReady,
        ReplayNativeStage.create => create,
        ReplayNativeStage.reset => reset,
        ReplayNativeStage.accept => accept,
        ReplayNativeStage.endpointResult => endpointResult,
        ReplayNativeStage.finalResult => finalResult,
        ReplayNativeStage.dispose => dispose,
      };

  Duration effectiveForStage(ReplayNativeStage stage, {Duration? maximum}) {
    final Duration configured = forStage(stage);
    return maximum != null && maximum < configured ? maximum : configured;
  }

  Future<T> run<T>(ReplayNativeStage stage, Future<T> operation,
      {Duration? maximum}) async {
    final Duration effective = effectiveForStage(stage, maximum: maximum);
    try {
      return await operation.timeout(effective);
    } on TimeoutException {
      throw ReplayNativeTimeoutException(stage, effective);
    }
  }
}

class VoiceReplayPolicy {
  const VoiceReplayPolicy({
    this.refinementBudget = const Duration(milliseconds: 1500),
    this.minimumRecoveryBudget = const Duration(milliseconds: 2500),
    this.recoveryHeadroom = const Duration(milliseconds: 1250),
    this.maximumRecoveryBudget = const Duration(seconds: 5),
    this.commandYieldPollInterval = const Duration(milliseconds: 5),
    this.operationTimeout = const Duration(seconds: 3),
    VoiceNativeTimeoutPolicy? nativeTimeoutPolicy,
    this.recognizerRecoveryDelay = const Duration(milliseconds: 120),
    this.standaloneAmbiguousHintMaxAudio = const Duration(milliseconds: 1300),
    this.standaloneAmbiguousHintMaxContinuation =
        const Duration(milliseconds: 320),
  }) : _nativeTimeoutPolicy = nativeTimeoutPolicy;

  final Duration refinementBudget;
  final Duration minimumRecoveryBudget;
  final Duration recoveryHeadroom;
  final Duration maximumRecoveryBudget;
  final Duration commandYieldPollInterval;
  final Duration operationTimeout;
  final VoiceNativeTimeoutPolicy? _nativeTimeoutPolicy;
  VoiceNativeTimeoutPolicy get nativeTimeoutPolicy =>
      _nativeTimeoutPolicy ??
      VoiceNativeTimeoutPolicy(
        waitReady: operationTimeout,
        create: operationTimeout,
        reset: operationTimeout,
        accept: operationTimeout,
        endpointResult: operationTimeout,
        finalResult: operationTimeout,
        dispose: operationTimeout,
      );
  final Duration recognizerRecoveryDelay;
  final Duration standaloneAmbiguousHintMaxAudio;
  final Duration standaloneAmbiguousHintMaxContinuation;

  ({bool skipReplay, String reason}) ambiguousHintDecision({
    required bool hasStableMatchingPartial,
    required bool isSingleToken,
    required bool hasVadSilenceBoundary,
    required int replayAudioMs,
    required int continuationAudioMs,
  }) {
    if (!hasStableMatchingPartial) {
      return (skipReplay: false, reason: 'partial_final_mismatch');
    }
    if (!isSingleToken) {
      return (skipReplay: false, reason: 'multi_word_command_final');
    }
    if (!hasVadSilenceBoundary) {
      return (skipReplay: false, reason: 'natural_endpoint_may_continue');
    }
    if (replayAudioMs > standaloneAmbiguousHintMaxAudio.inMilliseconds) {
      return (skipReplay: false, reason: 'utterance_too_long');
    }
    if (continuationAudioMs >
        standaloneAmbiguousHintMaxContinuation.inMilliseconds) {
      return (skipReplay: false, reason: 'speech_continued_after_hint');
    }
    return (skipReplay: true, reason: 'standalone_advertised_hint');
  }

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
