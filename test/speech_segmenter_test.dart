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
    expect((middle.captureEpoch, middle.segmentId), (3, 1));
    expect(endpoint.isEndpoint, isTrue);
    expect((next.captureEpoch, next.segmentId), (3, 2));
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

  test('exact-zero startup frames do not calibrate or lower noise floor', () {
    final SpeechSegmenter segmenter = SpeechSegmenter();
    segmenter.begin(1);

    for (int index = 0; index < 350; index++) {
      expect(segmenter.add(_pcmFrame(0), 1), isNull);
    }

    expect(segmenter.isCalibrated, isFalse);
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
    final SpeechSegment second = segmenter.add(_pcmFrame(328), 1)!;

    expect(endpoint!.isEndpoint, isTrue);
    expect(first.segmentId, 1);
    expect(second.segmentId, 2);
  });
}

Uint8List _pcmFrame(int amplitude, {int samples = 20}) {
  final ByteData bytes = ByteData(samples * 2);
  for (int index = 0; index < samples; index++) {
    bytes.setInt16(index * 2, amplitude, Endian.little);
  }
  return bytes.buffer.asUint8List();
}
