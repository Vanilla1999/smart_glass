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

  test('command A background then command B replay contains no A PCM', () {
    final SpeechTurnPcmWindows windows = SpeechTurnPcmWindows(
      maxWindowBytes: 80000,
      maxWindows: 2,
    );
    const SpeechTurnPcmKey commandA =
        SpeechTurnPcmKey(captureEpoch: 1, speechTurnId: 1);
    const SpeechTurnPcmKey commandB =
        SpeechTurnPcmKey(captureEpoch: 1, speechTurnId: 2);

    windows.add(
      commandA,
      Uint8List.fromList(<int>[1, 1]),
      SpeechTurnPcmPhase.body,
    );
    windows.retainOnly(commandB);
    windows.add(
      commandB,
      Uint8List.fromList(<int>[2, 2]),
      SpeechTurnPcmPhase.body,
    );

    expect(windows.snapshot(commandA).bytes, isEmpty);
    expect(windows.snapshot(commandB).bytes, <int>[2, 2]);
  });

  test('technical rollover continues the same speech-turn PCM window', () {
    final SpeechTurnPcmWindows windows = SpeechTurnPcmWindows(
      maxWindowBytes: 8,
      maxWindows: 2,
    );
    const SpeechTurnPcmKey turn =
        SpeechTurnPcmKey(captureEpoch: 3, speechTurnId: 7);

    windows.add(
      turn,
      Uint8List.fromList(<int>[1, 2]),
      SpeechTurnPcmPhase.preRoll,
    );
    windows.add(
      turn,
      Uint8List.fromList(<int>[3, 4]),
      SpeechTurnPcmPhase.body,
    );

    final SpeechTurnPcmSnapshot replay = windows.snapshot(turn);
    expect(replay.preRollBytes, <int>[1, 2]);
    expect(replay.bodyBytes, <int>[3, 4]);
    expect(replay.postRollBytes, isEmpty);
    expect(replay.bytes, <int>[1, 2, 3, 4]);
  });

  test('technical rollover snapshot preserves chronological PCM phases', () {
    final SpeechTurnPcmWindow window = SpeechTurnPcmWindow(maxBytes: 16);
    window.add(
      Uint8List.fromList(<int>[1, 2]),
      SpeechTurnPcmPhase.body,
      decoderGeneration: 2,
    );
    window.add(
      Uint8List.fromList(<int>[3, 4]),
      SpeechTurnPcmPhase.preRoll,
      decoderGeneration: 2,
    );
    window.add(
      Uint8List.fromList(<int>[5, 6]),
      SpeechTurnPcmPhase.body,
      decoderGeneration: 2,
    );

    expect(
        window.snapshot(decoderGeneration: 2).bytes, <int>[1, 2, 3, 4, 5, 6]);
  });

  test('snapshot includes only requested decoder generation', () {
    final SpeechTurnPcmWindow window = SpeechTurnPcmWindow(maxBytes: 16);
    window.add(
      Uint8List.fromList(<int>[1, 2]),
      SpeechTurnPcmPhase.body,
      decoderGeneration: 1,
    );
    window.add(
      Uint8List.fromList(<int>[3, 4]),
      SpeechTurnPcmPhase.body,
      decoderGeneration: 2,
    );

    expect(window.snapshot(decoderGeneration: 2).bytes, <int>[3, 4]);
  });

  test('capture restart clears every speech-turn PCM window', () {
    final SpeechTurnPcmWindows windows = SpeechTurnPcmWindows(
      maxWindowBytes: 8,
      maxWindows: 2,
    );
    const SpeechTurnPcmKey oldCapture =
        SpeechTurnPcmKey(captureEpoch: 1, speechTurnId: 1);
    windows.add(
      oldCapture,
      Uint8List.fromList(<int>[1, 2]),
      SpeechTurnPcmPhase.body,
    );

    windows.clear();

    expect(windows.totalBytes, 0);
    expect(windows.snapshot(oldCapture).bytes, isEmpty);
  });

  test('speech-turn PCM snapshots are immutable', () {
    final SpeechTurnPcmWindow window = SpeechTurnPcmWindow(maxBytes: 8);
    window.add(
      Uint8List.fromList(<int>[1, 2]),
      SpeechTurnPcmPhase.body,
    );
    final SpeechTurnPcmSnapshot first = window.snapshot();

    window.add(
      Uint8List.fromList(<int>[3, 4]),
      SpeechTurnPcmPhase.body,
    );

    expect(first.bytes, <int>[1, 2]);
    expect(window.snapshot().bytes, <int>[1, 2, 3, 4]);
  });
}
