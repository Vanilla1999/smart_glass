import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_glasses/core/voice/native_voice_capture.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_typing/speech_recognition_service.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_typing/voice_device_profile.dart';
import 'package:smart_glasses/modules/wear/services/voice_state.dart';
import 'package:smart_glasses/modules/wear/services/wear_voice_session.dart';

import 'support/replay_voice_capture.dart';

void main() {
  test('consumer exception ACK reaches WearVoiceSession as a terminal fault',
      () async {
    final ReplayVoiceCapture capture = ReplayVoiceCapture();
    await capture.start(
      owner: NativeVoiceOwner.wearRecognition,
      onPcm: (_) => throw StateError('decoder failed'),
    );
    final _HealthySpeechRecognitionService speech =
        _HealthySpeechRecognitionService();
    final List<Duration> scheduledDelays = <Duration>[];
    final WearVoiceSession session = WearVoiceSession(
      speechRecognitionService: speech,
      nativeVoiceStateSource: capture,
      ensurePrepared: () async {},
      nowMillis: () => 100,
      delay: (_) async {},
      scheduleRetry: (Duration delay, void Function() callback) {
        scheduledDelays.add(delay);
        return _FakeTimer();
      },
    );
    final StreamSubscription<NativeVoiceStateEvent> states =
        capture.stateEvents.listen(session.handleNativeVoiceState);

    try {
      await session.start();
      expect(await capture.emit(Uint8List(1024)), isFalse);
      await Future<void>.delayed(Duration.zero);

      expect(
        capture.acknowledgementRecords.single.status,
        NativePcmPacketEndpoint.consumerFailure,
      );
      expect(session.state.phase, VoicePhase.unavailable);
      expect(session.state.reason, 'native_PCM_CONSUMER_FAILED');
      expect(scheduledDelays, <Duration>[const Duration(seconds: 60)]);
    } finally {
      await session.stop();
      await states.cancel();
      await capture.dispose();
    }
  });

  test('backpressure ACK reaches one bounded automatic recovery attempt',
      () async {
    final ReplayVoiceCapture capture = ReplayVoiceCapture();
    await capture.start(
      owner: NativeVoiceOwner.wearRecognition,
      onPcm: (_) => false,
    );
    final _HealthySpeechRecognitionService speech =
        _HealthySpeechRecognitionService();
    Duration? retryDelay;
    void Function()? scheduledRetry;
    final WearVoiceSession session = WearVoiceSession(
      speechRecognitionService: speech,
      nativeVoiceStateSource: capture,
      ensurePrepared: () async {},
      nowMillis: () => 100,
      delay: (_) async {},
      scheduleRetry: (Duration delay, void Function() callback) {
        retryDelay = delay;
        scheduledRetry = callback;
        return _FakeTimer();
      },
    );
    final StreamSubscription<NativeVoiceStateEvent> states =
        capture.stateEvents.listen(session.handleNativeVoiceState);

    try {
      await session.start();
      expect(await capture.emit(Uint8List(1024)), isFalse);
      await Future<void>.delayed(Duration.zero);

      expect(
        capture.acknowledgementRecords.single.status,
        NativePcmPacketEndpoint.consumerRejected,
      );
      expect(session.state.phase, VoicePhase.unavailable);
      expect(session.state.reason, 'native_RECOGNITION_BACKLOG');
      expect(retryDelay, const Duration(seconds: 1));
      expect(scheduledRetry, isNotNull);
    } finally {
      await session.stop();
      await states.cancel();
      await capture.dispose();
    }
  });
}

class _HealthySpeechRecognitionService extends SpeechRecognitionService {
  bool _listening = false;

  @override
  bool get isListening => _listening;

  @override
  bool get isVadCalibrated => true;

  @override
  bool get isCaptureRunning => _listening;

  @override
  int get audioChunksReceived => _listening ? 3 : 0;

  @override
  int? get lastAudioChunkAtMillis => _listening ? 100 : null;

  @override
  int? get lastNonSilentAudioChunkAtMillis => _listening ? 100 : null;

  @override
  int? get lastNonZeroNativeInputAtMillis => null;

  @override
  Future<bool> refreshNativeInputActivity() async => false;

  @override
  int? get continuousZeroAudioStartedAtMillis => null;

  @override
  int? get captureStartedAtMillis => 0;

  @override
  int get audioCaptureId => 1;

  @override
  bool get hasExpectedInputDevice => true;

  @override
  VoiceDeviceProfile get deviceProfile => VoiceDeviceProfile.defaultProfile;

  @override
  Future<void> startListening() async {
    _listening = true;
  }

  @override
  Future<void> stopListening() async {
    _listening = false;
  }

  @override
  Future<String> diagnostics() async => 'healthy fake';
}

class _FakeTimer implements Timer {
  bool _active = true;

  @override
  bool get isActive => _active;

  @override
  int get tick => 0;

  @override
  void cancel() {
    _active = false;
  }
}
