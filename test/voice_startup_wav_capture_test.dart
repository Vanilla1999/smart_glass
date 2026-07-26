import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_typing/voice_startup_wav_capture.dart';

void main() {
  test('writes a bounded mono PCM16 WAV payload', () {
    final VoiceStartupWavCapture capture = VoiceStartupWavCapture(
      duration: const Duration(milliseconds: 1),
      sampleRate: 1000,
    );

    capture.add(Uint8List.fromList(<int>[1, 0, 2, 0, 3, 0]));

    expect(capture.pcmBytes, 2);
    expect(capture.hasReachedLimit, isTrue);
    final Uint8List wav = capture.toWavBytes();
    final ByteData data = ByteData.sublistView(wav);
    expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
    expect(String.fromCharCodes(wav.sublist(8, 12)), 'WAVE');
    expect(data.getUint32(24, Endian.little), 1000);
    expect(data.getUint32(40, Endian.little), 2);
    expect(wav.sublist(44), <int>[1, 0]);
  });
}
