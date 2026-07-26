import 'dart:typed_data';

class VoiceStartupWavCapture {
  VoiceStartupWavCapture({
    required this.duration,
    this.sampleRate = 16000,
    this.channels = 1,
  });

  final Duration duration;
  final int sampleRate;
  final int channels;
  final BytesBuilder _pcm = BytesBuilder(copy: false);

  int get maxPcmBytes =>
      (sampleRate * channels * 2 * duration.inMilliseconds) ~/ 1000;
  int get pcmBytes => _pcm.length;
  bool get hasReachedLimit => pcmBytes >= maxPcmBytes;

  void add(Uint8List bytes) {
    final int remaining = maxPcmBytes - pcmBytes;
    if (remaining <= 0) return;
    _pcm.add(bytes.lengthInBytes <= remaining
        ? bytes
        : Uint8List.sublistView(bytes, 0, remaining));
  }

  Uint8List toWavBytes() {
    final Uint8List pcm = _pcm.toBytes();
    final Uint8List wav = Uint8List(44 + pcm.lengthInBytes);
    final ByteData data = ByteData.sublistView(wav);
    wav.setRange(0, 4, 'RIFF'.codeUnits);
    data.setUint32(4, 36 + pcm.lengthInBytes, Endian.little);
    wav.setRange(8, 12, 'WAVE'.codeUnits);
    wav.setRange(12, 16, 'fmt '.codeUnits);
    data.setUint32(16, 16, Endian.little);
    data.setUint16(20, 1, Endian.little);
    data.setUint16(22, channels, Endian.little);
    data.setUint32(24, sampleRate, Endian.little);
    data.setUint32(28, sampleRate * channels * 2, Endian.little);
    data.setUint16(32, channels * 2, Endian.little);
    data.setUint16(34, 16, Endian.little);
    wav.setRange(36, 40, 'data'.codeUnits);
    data.setUint32(40, pcm.lengthInBytes, Endian.little);
    wav.setRange(44, wav.lengthInBytes, pcm);
    return wav;
  }
}
