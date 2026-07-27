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
        isCaptureRunning: true,
        chunksReceived: 2,
        lastAudioAtMillis: 1001,
        lastNonSilentAudioAtMillis: null,
        continuousZeroAudioStartedAtMillis: 1001,
        requireNonZeroPcm: false,
        hasExpectedInputDevice: true,
        nativeRouteMatchesExpected: true,
        nowMillis: 1001,
      ),
      isFalse,
    );
    expect(
      gate.isReady(
        captureStartedAtMillis: 1000,
        isCaptureRunning: true,
        chunksReceived: 3,
        lastAudioAtMillis: 1001,
        lastNonSilentAudioAtMillis: null,
        continuousZeroAudioStartedAtMillis: 1001,
        requireNonZeroPcm: false,
        hasExpectedInputDevice: true,
        nativeRouteMatchesExpected: true,
        nowMillis: 1001,
      ),
      isTrue,
    );
    expect(
      gate.isReady(
        captureStartedAtMillis: 1000,
        isCaptureRunning: false,
        chunksReceived: 3,
        lastAudioAtMillis: 1001,
        lastNonSilentAudioAtMillis: null,
        continuousZeroAudioStartedAtMillis: 1001,
        requireNonZeroPcm: false,
        hasExpectedInputDevice: true,
        nativeRouteMatchesExpected: true,
        nowMillis: 1001,
      ),
      isFalse,
    );
    expect(
      gate.isTimedOut(
        captureStartedAtMillis: 1000,
        nowMillis: 2999,
        timeout: const Duration(milliseconds: 2000),
      ),
      isFalse,
    );
    expect(
      gate.isTimedOut(
        captureStartedAtMillis: 1000,
        nowMillis: 3000,
        timeout: const Duration(milliseconds: 2000),
      ),
      isTrue,
    );
  });

  test('T2151 voice recognition does not become ready from exact-zero PCM', () {
    final VoiceCaptureStartupGate gate = VoiceCaptureStartupGate();

    expect(
      gate.isReady(
        captureStartedAtMillis: 1000,
        isCaptureRunning: true,
        chunksReceived: 3,
        lastAudioAtMillis: 1100,
        lastNonSilentAudioAtMillis: null,
        continuousZeroAudioStartedAtMillis: 1001,
        requireNonZeroPcm: true,
        hasExpectedInputDevice: true,
        nativeRouteMatchesExpected: true,
        nowMillis: 1100,
      ),
      isFalse,
    );
    expect(
      gate.isWaitingForNonZeroPcm(
        chunksReceived: 3,
        continuousZeroAudioStartedAtMillis: 1001,
      ),
      isTrue,
    );
  });

  test('low non-zero PCM makes T2151 voice recognition ready', () {
    final VoiceCaptureStartupGate gate = VoiceCaptureStartupGate();

    expect(
      gate.isReady(
        captureStartedAtMillis: 1000,
        isCaptureRunning: true,
        chunksReceived: 3,
        lastAudioAtMillis: 1100,
        lastNonSilentAudioAtMillis: 1100,
        continuousZeroAudioStartedAtMillis: null,
        requireNonZeroPcm: true,
        hasExpectedInputDevice: true,
        nativeRouteMatchesExpected: true,
        nowMillis: 1100,
      ),
      isTrue,
    );
  });

  test('exact-zero startup grace is measured from the first zero chunk', () {
    final VoiceCaptureStartupGate gate = VoiceCaptureStartupGate();

    expect(
      gate.hasExceededExactZeroGrace(
        continuousZeroAudioStartedAtMillis: 1000,
        nowMillis: 2199,
        grace: const Duration(milliseconds: 1200),
      ),
      isFalse,
    );
    expect(
      gate.hasExceededExactZeroGrace(
        continuousZeroAudioStartedAtMillis: 1000,
        nowMillis: 2200,
        grace: const Duration(milliseconds: 1200),
      ),
      isTrue,
    );
  });
}
