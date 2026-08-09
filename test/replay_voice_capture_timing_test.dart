import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_glasses/core/voice/native_voice_capture.dart';

import 'support/replay_voice_capture.dart';

void main() {
  test('real-time replay schedules against capture time, not ACK plus delay',
      () async {
    final _FakeReplayTimeline timeline = _FakeReplayTimeline();
    final ReplayVoiceCapture capture = ReplayVoiceCapture(timeline: timeline);
    addTearDown(capture.dispose);
    await capture.start(
      owner: NativeVoiceOwner.wearRecognition,
      onPcm: (_) {
        timeline.advance(const Duration(milliseconds: 20));
        return true;
      },
    );

    await capture.replay(<Uint8List>[Uint8List(1024), Uint8List(1024)]);

    expect(
      timeline.delays,
      <Duration>[
        const Duration(milliseconds: 12),
        const Duration(milliseconds: 12),
      ],
    );
  });

  test('slow acknowledgements catch up without an artificial extra delay',
      () async {
    final _FakeReplayTimeline timeline = _FakeReplayTimeline();
    final ReplayVoiceCapture capture = ReplayVoiceCapture(timeline: timeline);
    addTearDown(capture.dispose);
    await capture.start(
      owner: NativeVoiceOwner.wearRecognition,
      onPcm: (_) {
        timeline.advance(const Duration(milliseconds: 50));
        return true;
      },
    );

    await capture.replay(<Uint8List>[Uint8List(1024), Uint8List(1024)]);

    expect(timeline.delays, isEmpty);
    expect(capture.acknowledgements, <bool>[true, true]);
  });

  test('replay preserves the complete native acknowledgement identity',
      () async {
    final ReplayVoiceCapture capture = ReplayVoiceCapture();
    addTearDown(capture.dispose);
    await capture.start(
      owner: NativeVoiceOwner.wearRecognition,
      onPcm: (_) => false,
    );

    expect(await capture.emit(Uint8List(1024)), isFalse);
    expect(
      capture.acknowledgementRecords,
      <ReplayPcmAcknowledgement>[
        (
          status: NativePcmPacketEndpoint.consumerRejected,
          leaseId: 1,
          sequence: 0,
        ),
      ],
    );
    expect(capture.isCapturing, isFalse);
  });

  test('consumer exception is distinguishable from ordinary backpressure',
      () async {
    final ReplayVoiceCapture capture = ReplayVoiceCapture();
    addTearDown(capture.dispose);
    await capture.start(
      owner: NativeVoiceOwner.wearRecognition,
      onPcm: (_) => throw StateError('decoder failed'),
    );

    expect(await capture.emit(Uint8List(1024)), isFalse);
    expect(
      capture.acknowledgementRecords.single.status,
      NativePcmPacketEndpoint.consumerFailure,
    );
  });
}

class _FakeReplayTimeline implements ReplayTimeline {
  Duration _elapsed = Duration.zero;
  final List<Duration> delays = <Duration>[];

  @override
  Duration get elapsed => _elapsed;

  void advance(Duration duration) {
    _elapsed += duration;
  }

  @override
  Future<void> delay(Duration duration) async {
    delays.add(duration);
    advance(duration);
  }

  @override
  void reset() {
    _elapsed = Duration.zero;
    delays.clear();
  }
}
