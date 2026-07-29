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
}
