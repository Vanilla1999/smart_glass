import 'package:flutter_test/flutter_test.dart';
import 'package:smart_glasses/modules/wear/services/wear_voice_session.dart';

void main() {
  group('VoiceCaptureRecoveryGate', () {
    test('requires physical reconnect after one failed automatic restart', () {
      final VoiceCaptureRecoveryGate gate = VoiceCaptureRecoveryGate();

      expect(
        gate.nextAction(
          continuousZeroAudioAgeMs: 5000,
          captureSilenced: false,
          hasCurrentNonSilentAudio: false,
        ),
        VoiceCaptureRecoveryAction.restart,
      );

      gate.rearmAfterRestart();

      expect(
        gate.nextAction(
          continuousZeroAudioAgeMs: 5000,
          captureSilenced: false,
          hasCurrentNonSilentAudio: false,
        ),
        VoiceCaptureRecoveryAction.requireMicrophoneReconnect,
      );
    });

    test('resets the restart limit after non-silent audio', () {
      final VoiceCaptureRecoveryGate gate = VoiceCaptureRecoveryGate();
      gate.nextAction(
        continuousZeroAudioAgeMs: 5000,
        captureSilenced: false,
        hasCurrentNonSilentAudio: false,
      );
      gate.rearmAfterRestart();

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
  });
}
