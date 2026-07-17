import 'package:flutter_test/flutter_test.dart';
import 'package:smart_glasses/modules/wear/services/wear_voice_session.dart';

void main() {
  test('zero audio recovery waits for threshold and ignores silencing', () {
    final VoiceCaptureRecoveryGate gate = VoiceCaptureRecoveryGate();

    expect(
      gate.shouldRestart(
        continuousZeroAudioAgeMs: 4999,
        captureSilenced: false,
        hasCurrentNonSilentAudio: false,
      ),
      isFalse,
    );
    expect(
      gate.shouldRestart(
        continuousZeroAudioAgeMs: 5000,
        captureSilenced: true,
        hasCurrentNonSilentAudio: false,
      ),
      isFalse,
    );
    expect(
      gate.shouldRestart(
        continuousZeroAudioAgeMs: 5000,
        captureSilenced: false,
        hasCurrentNonSilentAudio: false,
      ),
      isTrue,
    );
  });

  test('zero audio recovery rearms only after non-silent audio', () {
    final VoiceCaptureRecoveryGate gate = VoiceCaptureRecoveryGate();

    expect(
      gate.shouldRestart(
        continuousZeroAudioAgeMs: 5000,
        captureSilenced: false,
        hasCurrentNonSilentAudio: false,
      ),
      isTrue,
    );
    expect(
      gate.shouldRestart(
        continuousZeroAudioAgeMs: 10000,
        captureSilenced: false,
        hasCurrentNonSilentAudio: false,
      ),
      isFalse,
    );
    expect(
      gate.shouldRestart(
        continuousZeroAudioAgeMs: null,
        captureSilenced: false,
        hasCurrentNonSilentAudio: true,
      ),
      isFalse,
    );
    expect(
      gate.shouldRestart(
        continuousZeroAudioAgeMs: 5000,
        captureSilenced: false,
        hasCurrentNonSilentAudio: false,
      ),
      isTrue,
    );
  });
}
