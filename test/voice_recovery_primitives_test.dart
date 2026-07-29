import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_typing/speech_recognition_service.dart';
import 'package:smart_glasses/modules/wear/services/wear_voice_session.dart';
import 'package:smart_glasses/modules/wear/services/voice_capture_diagnostics_store.dart';

void main() {
  test('health gate restarts for missing or stale PCM only', () {
    expect(VoiceCaptureHealthGate.hasStaleAudio(null), isTrue);
    expect(
      VoiceCaptureHealthGate.hasStaleAudio(
        VoiceCaptureHealthGate.staleAudioThresholdMs,
      ),
      isFalse,
    );
    expect(
      VoiceCaptureHealthGate.hasStaleAudio(
        VoiceCaptureHealthGate.staleAudioThresholdMs + 1,
      ),
      isTrue,
    );
  });

  test('retry policy is capped after the final configured delay', () {
    expect(VoiceRetryPolicy.delayFor(1), const Duration(seconds: 1));
    expect(VoiceRetryPolicy.delayFor(3), const Duration(seconds: 3));
    expect(VoiceRetryPolicy.delayFor(6), const Duration(seconds: 60));
    expect(VoiceRetryPolicy.delayFor(99), const Duration(seconds: 60));
  });

  test('single-flight joins concurrent restarts and accepts a later restart',
      () async {
    final VoiceSingleFlight singleFlight = VoiceSingleFlight();
    final Completer<void> pending = Completer<void>();
    var starts = 0;

    Future<void> operation() async {
      starts++;
      await pending.future;
    }

    final Future<void> first = singleFlight.run(operation);
    final Future<void> second = singleFlight.run(operation);
    await Future<void>.delayed(Duration.zero);

    expect(starts, 1);
    expect(identical(first, second), isTrue);

    pending.complete();
    await first;
    await singleFlight.run(() async => starts++);

    expect(starts, 2);
  });

  test('delayed Vosk work is invalidated and does not block a new capture',
      () async {
    final VoiceRecognitionCaptureEpoch epoch = VoiceRecognitionCaptureEpoch();
    final int oldCapture = epoch.begin();
    final Completer<void> delayedVosk = Completer<void>();

    final bool finished = await VoiceRecognitionProcessingQueue(
      stopTimeout: const Duration(milliseconds: 1),
    ).waitForIdle(
      command: delayedVosk.future,
      freeText: Future<void>.value(),
    );
    epoch.invalidate();
    final int newCapture = epoch.begin();

    expect(finished, isFalse);
    expect(epoch.isCurrent(oldCapture), isFalse);
    expect(epoch.isCurrent(newCapture), isTrue);

    delayedVosk.complete();
  });

  test('segment close guard times out a stuck native call', () async {
    final Completer<void> stuckNativeCall = Completer<void>();

    await expectLater(
      VoiceRecognitionSegmentCloseGuard(
        timeout: const Duration(milliseconds: 1),
      ).run(stuckNativeCall.future),
      throwsA(isA<TimeoutException>()),
    );

    stuckNativeCall.complete();
  });

  test('Vosk lane backlog admits at most 64000 bytes and drains exactly', () {
    final VoicePcmBacklog backlog = VoicePcmBacklog();

    expect(backlog.admit(32000), isTrue);
    expect(backlog.admit(32000), isTrue);
    expect(backlog.pendingBytes, 64000);
    expect(backlog.admit(2), isFalse);

    backlog.complete(32000);
    expect(backlog.pendingBytes, 32000);
    expect(backlog.admit(32000), isTrue);
  });

  test('startup requires three fresh packets and fresh non-zero PCM', () {
    final VoiceCaptureStartupGate gate = VoiceCaptureStartupGate();

    expect(
      gate.isReady(
        captureStartedAtMillis: 100,
        isCaptureRunning: true,
        chunksReceived: 2,
        lastAudioAtMillis: 120,
        lastNonSilentAudioAtMillis: 120,
        continuousZeroAudioStartedAtMillis: null,
        requireNonZeroPcm: true,
        hasExpectedInputDevice: true,
        nativeRouteMatchesExpected: true,
        nowMillis: 120,
      ),
      isFalse,
    );
    expect(
      gate.isReady(
        captureStartedAtMillis: 100,
        isCaptureRunning: true,
        chunksReceived: 3,
        lastAudioAtMillis: 130,
        lastNonSilentAudioAtMillis: 130,
        continuousZeroAudioStartedAtMillis: null,
        requireNonZeroPcm: true,
        hasExpectedInputDevice: true,
        nativeRouteMatchesExpected: true,
        nowMillis: 130,
      ),
      isTrue,
    );
    expect(VoiceCaptureStartupGate.timeoutMs, 15000);
  });

  test(
      'native diagnostics ignore stale captures and reject an explicit non-UVC route',
      () {
    final VoiceCaptureDiagnosticsStore store = VoiceCaptureDiagnosticsStore();
    store.beginCapture(2);
    store.accept(<String, dynamic>{
      'captureId': 1,
      'routedDeviceName': 'T2151 built-in microphone',
    });
    expect(store.latest, isNull);

    store.accept(<String, dynamic>{
      'captureId': 2,
      'routedDeviceName': 'T2151 built-in microphone',
    });
    expect(store.hasExplicitNonUvcRoute, isTrue);
  });
}
