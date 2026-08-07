import 'package:flutter_test/flutter_test.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_typing/voice_replay_policy.dart';

void main() {
  const VoiceReplayPolicy policy = VoiceReplayPolicy();

  test('refinement uses a short fixed budget', () {
    expect(
      policy.budgetFor(
        pcmBytes: 160000,
        purpose: VoiceReplayPurpose.refinement,
      ),
      const Duration(seconds: 2),
    );
  });

  test('short standalone ambiguous hint skips refinement', () {
    final decision = policy.ambiguousHintDecision(
      hasStableMatchingPartial: true,
      isSingleToken: true,
      hasVadSilenceBoundary: true,
      replayAudioMs: 1200,
      continuationAudioMs: 220,
    );
    expect(decision.skipReplay, isTrue);
    expect(decision.reason, 'standalone_advertised_hint');
  });

  test('natural endpoint preserves a possible longer phrase', () {
    final decision = policy.ambiguousHintDecision(
      hasStableMatchingPartial: true,
      isSingleToken: true,
      hasVadSilenceBoundary: false,
      replayAudioMs: 1200,
      continuationAudioMs: 0,
    );
    expect(decision.skipReplay, isFalse);
    expect(decision.reason, 'natural_endpoint_may_continue');
  });

  test('speech continuation after a shared hint keeps refinement', () {
    final decision = policy.ambiguousHintDecision(
      hasStableMatchingPartial: true,
      isSingleToken: true,
      hasVadSilenceBoundary: true,
      replayAudioMs: 1200,
      continuationAudioMs: 340,
    );
    expect(decision.skipReplay, isFalse);
    expect(decision.reason, 'speech_continued_after_hint');
  });

  test('long utterance keeps refinement even with a matching partial', () {
    final decision = policy.ambiguousHintDecision(
      hasStableMatchingPartial: true,
      isSingleToken: true,
      hasVadSilenceBoundary: true,
      replayAudioMs: 1320,
      continuationAudioMs: 120,
    );
    expect(decision.skipReplay, isFalse);
    expect(decision.reason, 'utterance_too_long');
  });

  test('unstable partial history keeps refinement', () {
    final decision = policy.ambiguousHintDecision(
      hasStableMatchingPartial: false,
      isSingleToken: true,
      hasVadSilenceBoundary: true,
      replayAudioMs: 900,
      continuationAudioMs: 0,
    );
    expect(decision.skipReplay, isFalse);
    expect(decision.reason, 'partial_final_mismatch');
  });

  test('multi-word command final keeps refinement', () {
    final decision = policy.ambiguousHintDecision(
      hasStableMatchingPartial: true,
      isSingleToken: false,
      hasVadSilenceBoundary: true,
      replayAudioMs: 900,
      continuationAudioMs: 0,
    );
    expect(decision.skipReplay, isFalse);
    expect(decision.reason, 'multi_word_command_final');
  });

  test('short recovery keeps the existing four second floor', () {
    expect(
      policy.budgetFor(
        pcmBytes: 40960,
        purpose: VoiceReplayPurpose.recovery,
      ),
      const Duration(seconds: 4),
    );
  });

  test('five seconds of audio keeps two seconds of recovery headroom', () {
    expect(
      policy.budgetFor(
        pcmBytes: 160000,
        purpose: VoiceReplayPurpose.recovery,
      ),
      const Duration(seconds: 7),
    );
  });

  test('long recovery is bounded by the eight second ceiling', () {
    expect(
      policy.budgetFor(
        pcmBytes: 640000,
        purpose: VoiceReplayPurpose.recovery,
      ),
      const Duration(seconds: 8),
    );
  });

  test('invalid PCM metadata falls back to the recovery floor', () {
    expect(
      policy.budgetFor(
        pcmBytes: 0,
        purpose: VoiceReplayPurpose.recovery,
      ),
      const Duration(seconds: 4),
    );
  });
}
