enum VoicePhase {
  disabled,
  preparing,
  ready,
  suspendedBySystem,
  reconnecting,
  unavailable,
}

class VoiceState {
  const VoiceState({
    required this.phase,
    required this.captureEpoch,
    required this.attempt,
    required this.reason,
    required this.lastTransitionAt,
    this.lastError,
    this.nextRetryAt,
  });

  const VoiceState.disabled()
      : phase = VoicePhase.disabled,
        captureEpoch = 0,
        attempt = 0,
        reason = 'initial',
        lastTransitionAt = 0,
        lastError = null,
        nextRetryAt = null;

  final VoicePhase phase;
  final int captureEpoch;
  final int attempt;
  final String reason;
  final int lastTransitionAt;
  final String? lastError;
  final int? nextRetryAt;

  bool get acceptsCommands => phase == VoicePhase.ready;

  VoiceState copyWith({
    VoicePhase? phase,
    int? captureEpoch,
    int? attempt,
    String? reason,
    int? lastTransitionAt,
    String? lastError,
    int? nextRetryAt,
    bool clearError = false,
    bool clearRetry = false,
  }) {
    return VoiceState(
      phase: phase ?? this.phase,
      captureEpoch: captureEpoch ?? this.captureEpoch,
      attempt: attempt ?? this.attempt,
      reason: reason ?? this.reason,
      lastTransitionAt: lastTransitionAt ?? this.lastTransitionAt,
      lastError: clearError ? null : lastError ?? this.lastError,
      nextRetryAt: clearRetry ? null : nextRetryAt ?? this.nextRetryAt,
    );
  }
}
