import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_typing/speech_segmenter.dart';

void main() {
  test('both lanes can share the same segment identity until silence endpoint',
      () {
    final SpeechSegmenter segmenter = SpeechSegmenter(
      sampleRate: 1,
      endpointSilence: const Duration(seconds: 2),
      calibrationDuration: Duration.zero,
    );
    segmenter.begin(3);

    final SpeechSegment first =
        segmenter.add(Uint8List.fromList(<int>[200, 0]), 3)!;
    final SpeechSegment middle =
        segmenter.add(Uint8List.fromList(<int>[0, 0]), 3)!;
    final SpeechSegment endpoint =
        segmenter.add(Uint8List.fromList(<int>[0, 0]), 3)!;
    final SpeechSegment next =
        segmenter.add(Uint8List.fromList(<int>[200, 0]), 3)!;

    expect((first.captureEpoch, first.segmentId), (3, 1));
    expect(first.speechTurnId, 1);
    expect((middle.captureEpoch, middle.segmentId), (3, 1));
    expect(middle.speechTurnId, first.speechTurnId);
    expect(endpoint.isEndpoint, isTrue);
    expect((next.captureEpoch, next.segmentId), (3, 2));
    expect(next.speechTurnId, 2);
  });

  test('new capture epoch discards old chunks and restarts segment numbering',
      () {
    final SpeechSegmenter segmenter = SpeechSegmenter(
      calibrationDuration: Duration.zero,
    );
    segmenter.begin(1);
    segmenter.add(Uint8List.fromList(<int>[200, 0]), 1);
    segmenter.begin(2);

    expect(segmenter.add(Uint8List.fromList(<int>[0, 16]), 1), isNull);
    final SpeechSegment fresh =
        segmenter.add(Uint8List.fromList(<int>[200, 0]), 2)!;
    expect((fresh.captureEpoch, fresh.segmentId), (2, 1));
  });

  test('records VAD thresholds used for the current raw PCM frame', () {
    final SpeechSegmenter segmenter = SpeechSegmenter(
      sampleRate: 1,
      calibrationDuration: Duration.zero,
    );
    segmenter.begin(1);

    segmenter.add(Uint8List.fromList(<int>[0, 0]), 1);
    final SpeechSegmentDiagnostics silence = segmenter.lastDiagnostics;

    expect(silence.rms, 0);
    expect(silence.noiseFloorRms, 0.0002);
    expect(silence.adaptiveOnRms, 0.001);
    expect(silence.adaptiveOffRms, 0.0007);
    expect(silence.speaking, isFalse);
  });

  test('quiet non-speech frames slowly adapt the noise floor', () {
    final SpeechSegmenter segmenter = SpeechSegmenter(
      speechOnRms: 0.0005,
      speechOffRms: 0.0003,
      calibrationDuration: Duration.zero,
    );
    segmenter.begin(1);

    segmenter.add(Uint8List.fromList(<int>[13, 0]), 1);
    final double noiseFloor = segmenter.lastDiagnostics.noiseFloorRms;
    segmenter.add(Uint8List.fromList(<int>[15, 0]), 1);

    expect(segmenter.lastDiagnostics.speaking, isFalse);
    expect(segmenter.lastDiagnostics.noiseFloorRms, greaterThan(noiseFloor));
  });

  test('T2151 quiet speech starts a segment in the first PCM frame', () {
    final SpeechSegmenter segmenter = SpeechSegmenter(
      speechOnRms: 0.0005,
      speechOffRms: 0.0003,
      calibrationDuration: Duration.zero,
    );
    segmenter.begin(1);

    final SpeechSegment? segment =
        segmenter.add(Uint8List.fromList(<int>[17, 0]), 1);

    expect(segment, isNotNull);
    expect(segment!.started, isTrue);
  });

  test('ends a segment after 500 ms of silence', () {
    final SpeechSegmenter segmenter = SpeechSegmenter(
      sampleRate: 10,
      endpointSilence: const Duration(milliseconds: 500),
      calibrationDuration: Duration.zero,
    );
    segmenter.begin(1);
    segmenter.add(Uint8List.fromList(<int>[40, 0]), 1);

    SpeechSegment? endpoint;
    for (int index = 0; index < 5; index++) {
      endpoint = segmenter.add(Uint8List.fromList(<int>[0, 0]), 1);
    }

    expect(endpoint!.isEndpoint, isTrue);
  });

  test('exact-zero startup completes calibration without lowering floor', () {
    final SpeechSegmenter segmenter = SpeechSegmenter();
    segmenter.begin(1);

    for (int index = 0; index < 600; index++) {
      expect(segmenter.add(_pcmFrame(0), 1), isNull);
    }

    expect(segmenter.isCalibrated, isTrue);
    expect(segmenter.lastDiagnostics.noiseFloorRms, 0.0002);
  });

  test('calibrates from 750 ms of non-zero background', () {
    final SpeechSegmenter segmenter = SpeechSegmenter(sampleRate: 1000);
    segmenter.begin(1);

    for (int index = 0; index < 38; index++) {
      expect(segmenter.add(_pcmFrame(33), 1), isNull);
    }

    expect(segmenter.isCalibrated, isTrue);
    expect(segmenter.lastDiagnostics.noiseFloorRms, closeTo(33 / 32768, 1e-8));
  });

  test('speech outliers do not inflate p20 calibration noise floor', () {
    final SpeechSegmenter segmenter = SpeechSegmenter(
      sampleRate: 1000,
      calibrationDuration: const Duration(milliseconds: 200),
    );
    segmenter.begin(1);

    for (int index = 0; index < 8; index++) {
      final int amplitude = index < 6 ? 32 : 3200;
      segmenter.add(_pcmFrame(amplitude, samples: 25), 1);
    }

    final SpeechSegmentDiagnostics diagnostics = segmenter.lastDiagnostics;
    expect(segmenter.isCalibrated, isTrue);
    expect(diagnostics.noiseFloorRms, closeTo(32 / 32768, 1e-8));
    expect(diagnostics.calibrationP10Rms, closeTo(32 / 32768, 1e-8));
    expect(diagnostics.calibrationP50Rms, closeTo(32 / 32768, 1e-8));
    expect(diagnostics.calibrationP90Rms, greaterThan(0.09));
  });

  test('background stays idle and speech starts after calibration', () {
    final SpeechSegmenter segmenter = SpeechSegmenter(
      sampleRate: 1000,
      speechOnRms: 0.002,
      speechOffRms: 0.0012,
    );
    segmenter.begin(1);
    for (int index = 0; index < 38; index++) {
      segmenter.add(_pcmFrame(33), 1);
    }

    expect(segmenter.add(_pcmFrame(33), 1), isNull);
    final SpeechSegment? speech = segmenter.add(_pcmFrame(328), 1);

    expect(speech, isNotNull);
    expect(speech!.started, isTrue);
  });

  test('two commands separated by silence get different segment ids', () {
    final SpeechSegmenter segmenter = SpeechSegmenter(
      sampleRate: 1000,
      speechOnRms: 0.002,
      speechOffRms: 0.0012,
      endpointSilence: const Duration(milliseconds: 500),
    );
    segmenter.begin(1);
    for (int index = 0; index < 38; index++) {
      segmenter.add(_pcmFrame(33), 1);
    }

    final SpeechSegment first = segmenter.add(_pcmFrame(328), 1)!;
    SpeechSegment? endpoint;
    for (int index = 0; index < 25; index++) {
      endpoint = segmenter.add(_pcmFrame(33), 1);
    }
    expect(segmenter.add(_pcmFrame(328), 1), isNull);
    final SpeechSegment second = segmenter.add(_pcmFrame(328), 1)!;

    expect(endpoint!.isEndpoint, isTrue);
    expect(first.segmentId, 1);
    expect(second.segmentId, 2);
  });

  test('max-duration rollover preserves acoustic speech turn identity', () {
    final SpeechSegmenter segmenter = SpeechSegmenter(
      sampleRate: 1000,
      calibrationDuration: Duration.zero,
      maxSegmentDuration: const Duration(milliseconds: 40),
      maxDurationContinuation: const Duration(milliseconds: 200),
      restartConfirmation: const Duration(milliseconds: 20),
    );
    segmenter.begin(1);

    final SpeechSegment first = segmenter.add(_pcmFrame(328), 1)!;
    final SpeechSegment rollover = segmenter.add(_pcmFrame(328), 1)!;
    expect(segmenter.add(_pcmFrame(328), 1)!.started, isFalse);
    final SpeechSegment continued = segmenter.add(_pcmFrame(656), 1)!;

    expect(rollover.isEndpoint, isTrue);
    expect(rollover.endpointReason, AcousticEndpointReason.maxDuration);
    expect(continued.started, isTrue);
    expect(continued.segmentId, isNot(first.segmentId));
    expect(continued.speechTurnId, first.speechTurnId);
  });

  test('continuation silence closes rollover turn at configured boundary', () {
    final SpeechSegmenter segmenter = SpeechSegmenter(
      sampleRate: 1000,
      calibrationDuration: Duration.zero,
      maxSegmentDuration: const Duration(milliseconds: 40),
      maxDurationContinuation: const Duration(milliseconds: 40),
      restartConfirmation: const Duration(milliseconds: 20),
    );
    segmenter.begin(1);
    final SpeechSegment first = segmenter.add(_pcmFrame(328), 1)!;
    expect(
      segmenter.add(_pcmFrame(328), 1)!.endpointReason,
      AcousticEndpointReason.maxDuration,
    );

    segmenter.add(_pcmFrame(0), 1);
    final SpeechSegment silenceEndpoint = segmenter.add(_pcmFrame(0), 1)!;
    expect(silenceEndpoint.endpointReason, AcousticEndpointReason.silence);
    expect(silenceEndpoint.speechTurnId, first.speechTurnId);
    expect(segmenter.state, VadState.idle);

    final SpeechSegment next = segmenter.add(_pcmFrame(328), 1)!;
    expect(next.speechTurnId, isNot(first.speechTurnId));
  });

  test('exposes deterministic calibration candidate and speech states', () {
    final SpeechSegmenter segmenter = SpeechSegmenter(
      sampleRate: 1000,
      calibrationDuration: const Duration(milliseconds: 20),
      onsetConfirmation: const Duration(milliseconds: 40),
    );
    segmenter.begin(1);
    expect(segmenter.state, VadState.calibrating);
    segmenter.decide(_pcmFrame(0), 1);
    expect(segmenter.state, VadState.idle);
    final VadFrameDecision candidate = segmenter.decide(_pcmFrame(328), 1);
    expect(segmenter.state, VadState.candidateSpeech);
    expect(candidate.retainFrame, isTrue);
    final VadFrameDecision confirmed = segmenter.decide(_pcmFrame(328), 1);
    expect(segmenter.state, VadState.speaking);
    expect(confirmed.segment!.started, isTrue);
    expect(confirmed.retainFrame, isFalse);
  });

  test('rejected onset candidate requests retained-frame reset', () {
    final SpeechSegmenter segmenter = SpeechSegmenter(
      sampleRate: 1000,
      calibrationDuration: Duration.zero,
      onsetConfirmation: const Duration(milliseconds: 40),
    );
    segmenter.begin(1);
    expect(segmenter.decide(_pcmFrame(328), 1).retainFrame, isTrue);

    final VadFrameDecision rejected = segmenter.decide(_pcmFrame(0), 1);

    expect(rejected.segment, isNull);
    expect(rejected.retainFrame, isFalse);
    expect(rejected.resetRetainedFrames, isTrue);
    expect(segmenter.state, VadState.idle);
  });

  test('local SNR spike is rejected without a confirming frame', () {
    final SpeechSegmenter segmenter = SpeechSegmenter(
      sampleRate: 1000,
      calibrationDuration: Duration.zero,
      onsetConfirmation: const Duration(milliseconds: 40),
    );
    segmenter.begin(1);
    segmenter.decide(_pcmFrame(328), 1);

    expect(segmenter.decide(_pcmFrame(20), 1).resetRetainedFrames, isTrue);
    expect(segmenter.state, VadState.idle);
  });

  test('constant TV-like background does not repeatedly onset after rollover',
      () {
    final SpeechSegmenter segmenter = SpeechSegmenter(
      sampleRate: 1000,
      calibrationDuration: Duration.zero,
      maxSegmentDuration: const Duration(milliseconds: 40),
    );
    segmenter.begin(1);
    segmenter.add(_pcmFrame(328), 1);
    final SpeechSegment rollover = segmenter.add(_pcmFrame(328), 1)!;
    expect(rollover.endpointReason, AcousticEndpointReason.maxDuration);

    for (int index = 0; index < 10; index++) {
      expect(segmenter.add(_pcmFrame(328), 1)!.started, isFalse);
    }
    expect(segmenter.state, VadState.continuationAfterMaxDuration);
  });

  test('foreground rise after stable background creates an onset', () {
    final SpeechSegmenter segmenter = SpeechSegmenter(
      sampleRate: 1000,
      calibrationDuration: Duration.zero,
      speechOnRms: 0.002,
    );
    segmenter.begin(1);
    for (int index = 0; index < 10; index++) {
      expect(segmenter.add(_pcmFrame(50), 1), isNull);
    }

    final SpeechSegment? foreground = segmenter.add(_pcmFrame(328), 1);

    expect(foreground, isNotNull);
    expect(foreground!.speechTurnId, 1);
  });

  test('gradual foreground delta over adapted background creates onset', () {
    final SpeechSegmenter segmenter = SpeechSegmenter(
      sampleRate: 1000,
      calibrationDuration: Duration.zero,
      speechOnRms: 0.001,
      minimumOnsetSnr: 10,
      minimumOnsetRise: 10,
    );
    segmenter.begin(1);
    for (int index = 0; index < 20; index++) {
      segmenter.add(_pcmFrame(25), 1);
    }

    final SpeechSegment? foreground = segmenter.add(_pcmFrame(90), 1);

    expect(foreground, isNotNull);
  });

  test('confirmed silence starts a new acoustic speech turn', () {
    final SpeechSegmenter segmenter = SpeechSegmenter(
      sampleRate: 1000,
      calibrationDuration: Duration.zero,
      endpointSilence: const Duration(milliseconds: 40),
    );
    segmenter.begin(1);
    final SpeechSegment first = segmenter.add(_pcmFrame(328), 1)!;
    segmenter.add(_pcmFrame(0), 1);
    segmenter.add(_pcmFrame(0), 1);
    expect(segmenter.add(_pcmFrame(328), 1), isNull);
    final SpeechSegment next = segmenter.add(_pcmFrame(328), 1)!;
    expect(next.speechTurnId, isNot(first.speechTurnId));
  });

  test('one noisy frame after silence endpoint does not restart VAD', () {
    final SpeechSegmenter segmenter = SpeechSegmenter(
      sampleRate: 1000,
      calibrationDuration: Duration.zero,
      endpointSilence: const Duration(milliseconds: 40),
      restartConfirmation: const Duration(milliseconds: 40),
    );
    segmenter.begin(1);
    segmenter.add(_pcmFrame(328), 1);
    segmenter.add(_pcmFrame(0), 1);
    final SpeechSegment endpoint = segmenter.add(_pcmFrame(0), 1)!;

    expect(endpoint.isEndpoint, isTrue);
    expect(segmenter.add(_pcmFrame(328), 1), isNull);
  });

  test('confirmed speech after silence endpoint starts a new turn', () {
    final SpeechSegmenter segmenter = SpeechSegmenter(
      sampleRate: 1000,
      calibrationDuration: Duration.zero,
      endpointSilence: const Duration(milliseconds: 40),
      restartConfirmation: const Duration(milliseconds: 40),
    );
    segmenter.begin(1);
    final SpeechSegment first = segmenter.add(_pcmFrame(328), 1)!;
    segmenter.add(_pcmFrame(0), 1);
    segmenter.add(_pcmFrame(0), 1);
    expect(segmenter.add(_pcmFrame(328), 1), isNull);
    final SpeechSegment restarted = segmenter.add(_pcmFrame(328), 1)!;
    expect(restarted.speechTurnId, isNot(first.speechTurnId));
  });
}

Uint8List _pcmFrame(int amplitude, {int samples = 20}) {
  final ByteData bytes = ByteData(samples * 2);
  for (int index = 0; index < samples; index++) {
    bytes.setInt16(index * 2, amplitude, Endian.little);
  }
  return bytes.buffer.asUint8List();
}
