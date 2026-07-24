import 'package:flutter_test/flutter_test.dart';
import 'package:smart_glasses/modules/wear/services/wear_voice_session.dart';

void main() {
  test('zero audio recovery waits for threshold and ignores silencing', () {
    final VoiceCaptureRecoveryGate gate = VoiceCaptureRecoveryGate();

    expect(
      gate.nextAction(
        continuousZeroAudioAgeMs: 4999,
        captureSilenced: false,
        hasCurrentNonSilentAudio: false,
      ),
      VoiceCaptureRecoveryAction.none,
    );
    expect(
      gate.nextAction(
        continuousZeroAudioAgeMs: 5000,
        captureSilenced: true,
        hasCurrentNonSilentAudio: false,
      ),
      VoiceCaptureRecoveryAction.none,
    );
    expect(
      gate.nextAction(
        continuousZeroAudioAgeMs: 5000,
        captureSilenced: false,
        hasCurrentNonSilentAudio: false,
      ),
      VoiceCaptureRecoveryAction.restart,
    );
  });

  test('zero audio recovery rearms only after non-silent audio', () {
    final VoiceCaptureRecoveryGate gate = VoiceCaptureRecoveryGate();

    expect(
      gate.nextAction(
        continuousZeroAudioAgeMs: 5000,
        captureSilenced: false,
        hasCurrentNonSilentAudio: false,
      ),
      VoiceCaptureRecoveryAction.restart,
    );
    expect(
      gate.nextAction(
        continuousZeroAudioAgeMs: 10000,
        captureSilenced: false,
        hasCurrentNonSilentAudio: false,
      ),
      VoiceCaptureRecoveryAction.none,
    );
    expect(
      gate.nextAction(
        continuousZeroAudioAgeMs: null,
        captureSilenced: false,
        hasCurrentNonSilentAudio: true,
      ),
      VoiceCaptureRecoveryAction.none,
    );
    expect(
      gate.nextAction(
        continuousZeroAudioAgeMs: 5000,
        captureSilenced: false,
        hasCurrentNonSilentAudio: false,
      ),
      VoiceCaptureRecoveryAction.restart,
    );
  });

  test('startup becomes ready after technical PCM readiness without speech',
      () {
    final VoiceCaptureStartupGate gate = VoiceCaptureStartupGate();

    expect(
      gate.isReady(
        captureStartedAtMillis: 1000,
        chunksReceived: 2,
        lastAudioAtMillis: 1001,
        nowMillis: 1001,
      ),
      isFalse,
    );
    expect(
      gate.isReady(
        captureStartedAtMillis: 1000,
        chunksReceived: 3,
        lastAudioAtMillis: 1001,
        nowMillis: 1001,
      ),
      isTrue,
    );
    expect(
      gate.isTimedOut(
        captureStartedAtMillis: 1000,
        nowMillis: 2999,
      ),
      isFalse,
    );
    expect(
      gate.isTimedOut(
        captureStartedAtMillis: 1000,
        nowMillis: 3000,
      ),
      isTrue,
    );
  });
}
