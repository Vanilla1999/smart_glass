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
