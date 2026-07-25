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
}
