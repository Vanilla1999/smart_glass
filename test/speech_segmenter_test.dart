import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_typing/speech_segmenter.dart';

void main() {
  test('both lanes can share the same segment identity until silence endpoint',
      () {
    final SpeechSegmenter segmenter = SpeechSegmenter(
      sampleRate: 1,
      endpointSilence: const Duration(seconds: 2),
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
    final SpeechSegmenter segmenter = SpeechSegmenter();
    segmenter.begin(1);
    segmenter.add(Uint8List.fromList(<int>[200, 0]), 1);
    segmenter.begin(2);

    expect(segmenter.add(Uint8List.fromList(<int>[0, 16]), 1), isNull);
    final SpeechSegment fresh =
        segmenter.add(Uint8List.fromList(<int>[200, 0]), 2)!;
    expect((fresh.captureEpoch, fresh.segmentId), (2, 1));
  });

  test('records VAD thresholds used for the current raw PCM frame', () {
    final SpeechSegmenter segmenter = SpeechSegmenter(sampleRate: 1);
    segmenter.begin(1);

    segmenter.add(Uint8List.fromList(<int>[0, 0]), 1);
    final SpeechSegmentDiagnostics silence = segmenter.lastDiagnostics;

    expect(silence.rms, 0);
    expect(silence.noiseFloorRms, 0.0002);
    expect(silence.adaptiveOnRms, 0.001);
    expect(silence.adaptiveOffRms, 0.0007);
    expect(silence.speaking, isFalse);
  });

  test('quiet non-speech frames do not raise the noise floor', () {
    final SpeechSegmenter segmenter = SpeechSegmenter(
      speechOnRms: 0.0005,
      speechOffRms: 0.0003,
    );
    segmenter.begin(1);

    segmenter.add(Uint8List.fromList(<int>[13, 0]), 1);
    final double noiseFloor = segmenter.lastDiagnostics.noiseFloorRms;
    segmenter.add(Uint8List.fromList(<int>[15, 0]), 1);

    expect(segmenter.lastDiagnostics.speaking, isFalse);
    expect(segmenter.lastDiagnostics.noiseFloorRms, noiseFloor);
  });

  test('T2151 quiet speech starts a segment in the first PCM frame', () {
    final SpeechSegmenter segmenter = SpeechSegmenter(
      speechOnRms: 0.0005,
      speechOffRms: 0.0003,
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
    );
    segmenter.begin(1);
    segmenter.add(Uint8List.fromList(<int>[40, 0]), 1);

    SpeechSegment? endpoint;
    for (int index = 0; index < 5; index++) {
      endpoint = segmenter.add(Uint8List.fromList(<int>[0, 0]), 1);
    }

    expect(endpoint!.isEndpoint, isTrue);
  });
}
