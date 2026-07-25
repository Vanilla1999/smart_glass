import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_typing/speech_recognition_service.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_typing/voice_device_profile.dart';
import 'package:smart_glasses/modules/wear/services/wear_voice_session.dart';

void main() {
  group('VoiceSingleFlight', () {
    test('joins concurrent health operations', () async {
      final VoiceSingleFlight singleFlight = VoiceSingleFlight();
      int calls = 0;
      final Future<void> first = singleFlight.run(() async {
        calls++;
        await Future<void>.delayed(Duration.zero);
      });
      final Future<void> second = singleFlight.run(() async {
        calls++;
      });

      expect(identical(first, second), isTrue);
      await Future.wait(<Future<void>>[first, second]);
      expect(calls, 1);
    });
  });

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

  group('WearVoiceSession retry ownership', () {
    test('schedules one retry and its callback owns the next restart',
        () async {
      final _FailingStartSpeechRecognitionService speech =
          _FailingStartSpeechRecognitionService();
      Duration? scheduledDelay;
      void Function()? scheduledRetry;
      final WearVoiceSession session = WearVoiceSession(
        speechRecognitionService: speech,
        ensurePrepared: () async {},
        nowMillis: () => 0,
        delay: (_) async {},
        updateNativeCaptureMonitor: ({
          required bool active,
          required String source,
          required int captureId,
        }) async {},
        scheduleRetry: (Duration delay, void Function() callback) {
          scheduledDelay = delay;
          scheduledRetry = callback;
          return _FakeTimer();
        },
      );

      await expectLater(session.start(), throwsStateError);

      expect(scheduledDelay, const Duration(seconds: 1));
      expect(speech.restartCalls, 0);

      scheduledRetry!.call();
      await Future<void>.delayed(Duration.zero);

      expect(speech.restartCalls, 1);
    });
  });
}

class _FailingStartSpeechRecognitionService extends SpeechRecognitionService {
  bool _listening = false;
  int restartCalls = 0;

  @override
  bool get isListening => _listening;

  @override
  bool get isCaptureRunning => _listening;

  @override
  int get audioChunksReceived => _listening ? 3 : 0;

  @override
  int? get lastAudioChunkAtMillis => _listening ? 0 : null;

  @override
  int? get captureStartedAtMillis => 0;

  @override
  int get audioCaptureId => 0;

  @override
  VoiceDeviceProfile get deviceProfile => VoiceDeviceProfile.defaultProfile;

  @override
  Future<void> startListening() async {
    throw StateError('start failed');
  }

  @override
  Future<void> stopListening() async {}

  @override
  Future<void> restartListening({required String reason}) async {
    restartCalls++;
    _listening = true;
  }

  @override
  Future<String> diagnostics() async => 'fake';
}

class _FakeTimer implements Timer {
  bool _isActive = true;

  @override
  bool get isActive => _isActive;

  @override
  int get tick => 0;

  @override
  void cancel() {
    _isActive = false;
  }
}
