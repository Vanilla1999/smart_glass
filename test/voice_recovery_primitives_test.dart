import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_typing/audio_stream_service.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_typing/speech_recognition_service.dart';
import 'package:smart_glasses/modules/wear/services/wear_voice_session.dart';

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

  test('recorder recreation stops, disposes, then replaces the recorder',
      () async {
    final List<String> calls = <String>[];

    await VoiceRecorderLifecycle.recreate(
      stop: () async => calls.add('stop'),
      dispose: () async => calls.add('dispose'),
      create: () => calls.add('create'),
    );

    expect(calls, <String>['stop', 'dispose', 'create']);
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
}
