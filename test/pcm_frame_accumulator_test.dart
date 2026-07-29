import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_typing/speech_recognition_service.dart';

void main() {
  test('emits only exact PCM frames across irregular packet boundaries', () {
    final PcmFrameAccumulator accumulator =
        PcmFrameAccumulator(frameBytes: 640);

    expect(accumulator.add(Uint8List(512), Uint8List(512)), isEmpty);
    expect(accumulator.add(Uint8List(1024), Uint8List(1024)), hasLength(2));
    expect(accumulator.add(Uint8List(384), Uint8List(384)), hasLength(1));
  });

  test('rejects unaligned or mismatched PCM buffers', () {
    final PcmFrameAccumulator accumulator =
        PcmFrameAccumulator(frameBytes: 640);

    expect(
      () => accumulator.add(Uint8List(3), Uint8List(3)),
      throwsArgumentError,
    );
    expect(
      () => accumulator.add(Uint8List(2), Uint8List(4)),
      throwsArgumentError,
    );
  });

  test('T26 ten 1024-byte packets preserve every byte in 640-byte frames', () {
    final PcmFrameAccumulator accumulator =
        PcmFrameAccumulator(frameBytes: 640);
    final List<int> output = <int>[];
    final List<int> input =
        List<int>.generate(10240, (int index) => index % 256);

    for (int offset = 0; offset < input.length; offset += 1024) {
      final Uint8List packet =
          Uint8List.fromList(input.sublist(offset, offset + 1024));
      for (final PcmFramePair frame in accumulator.add(packet, packet)) {
        expect(frame.raw, hasLength(640));
        output.addAll(frame.raw);
      }
    }

    expect(output, input);
  });

  test('T27 remainder survives packets and reset drops old capture bytes', () {
    final PcmFrameAccumulator accumulator =
        PcmFrameAccumulator(frameBytes: 640);
    expect(accumulator.add(Uint8List(384), Uint8List(384)), isEmpty);
    accumulator.reset();

    final Uint8List packet = Uint8List.fromList(List<int>.filled(640, 7));
    final List<PcmFramePair> frames = accumulator.add(packet, packet);
    expect(frames, hasLength(1));
    expect(frames.single.raw, everyElement(7));
  });

  test('utterance PCM buffer is bounded and isolates the next utterance', () {
    final BoundedPcmBuffer buffer = BoundedPcmBuffer(maxBytes: 8);
    buffer.add(Uint8List.fromList(<int>[1, 2, 3, 4, 5]));
    buffer.add(Uint8List.fromList(<int>[6, 7, 8, 9, 10]));

    expect(buffer.take(), <int>[3, 4, 5, 6, 7, 8, 9, 10]);
    expect(buffer.length, 0);
    buffer.add(Uint8List.fromList(<int>[11, 12]));
    expect(buffer.take(), <int>[11, 12]);
  });
}
