import 'dart:math' as math;
import 'dart:typed_data';

class SpeechSegment {
  const SpeechSegment({
    required this.captureEpoch,
    required this.segmentId,
    required this.lastChunkId,
    required this.isEndpoint,
    required this.started,
  });

  final int captureEpoch;
  final int segmentId;
  final int lastChunkId;
  final bool isEndpoint;
  final bool started;
}

/// Assigns one identity to every PCM chunk sent to both recognizer lanes.
class SpeechSegmenter {
  SpeechSegmenter({
    this.sampleRate = 16000,
    this.endpointSilence = const Duration(milliseconds: 500),
    this.maxSegmentDuration = const Duration(seconds: 8),
    this.speechOnRms = 0.001,
    this.speechOffRms = 0.0007,
    this.initialNoiseFloorRms = 0.0002,
  });

  final int sampleRate;
  final Duration endpointSilence;
  final Duration maxSegmentDuration;
  double speechOnRms;
  double speechOffRms;
  final double initialNoiseFloorRms;
  int _epoch = 0;
  int _nextSegmentId = 0;
  int _nextChunkId = 0;
  int? _activeSegmentId;
  int _silentSamples = 0;
  int _segmentSamples = 0;
  double _noiseFloorRms = 0.0002;

  void configure({
    required double speechOnRms,
    required double speechOffRms,
  }) {
    this.speechOnRms = speechOnRms;
    this.speechOffRms = speechOffRms;
  }

  void begin(int captureEpoch) {
    _epoch = captureEpoch;
    _nextSegmentId = 0;
    _nextChunkId = 0;
    _activeSegmentId = null;
    _silentSamples = 0;
    _segmentSamples = 0;
    _noiseFloorRms = initialNoiseFloorRms;
  }

  SpeechSegment? add(Uint8List bytes, int captureEpoch) {
    if (captureEpoch != _epoch) return null;
    final int chunkId = ++_nextChunkId;
    final int sampleCount = bytes.lengthInBytes ~/ 2;
    final double rms = _rms(bytes);
    final bool speaking = _isSpeaking(rms);
    if (!speaking) {
      _noiseFloorRms = _noiseFloorRms * 0.95 + rms * 0.05;
      final int? segmentId = _activeSegmentId;
      if (segmentId == null) return null;
      _silentSamples += sampleCount;
      _segmentSamples += sampleCount;
      final bool endpoint =
          _silentSamples >= _durationToSamples(endpointSilence) ||
              _segmentSamples >= _durationToSamples(maxSegmentDuration);
      if (endpoint) {
        _activeSegmentId = null;
        _silentSamples = 0;
        _segmentSamples = 0;
      }
      return SpeechSegment(
        captureEpoch: _epoch,
        segmentId: segmentId,
        lastChunkId: chunkId,
        isEndpoint: endpoint,
        started: false,
      );
    }

    _silentSamples = 0;
    final bool started = _activeSegmentId == null;
    final int segmentId = _activeSegmentId ??= ++_nextSegmentId;
    _segmentSamples += sampleCount;
    final bool endpoint =
        _segmentSamples >= _durationToSamples(maxSegmentDuration);
    if (endpoint) {
      _activeSegmentId = null;
      _segmentSamples = 0;
    }
    return SpeechSegment(
      captureEpoch: _epoch,
      segmentId: segmentId,
      lastChunkId: chunkId,
      isEndpoint: endpoint,
      started: started,
    );
  }

  void end(int captureEpoch) {
    if (captureEpoch == _epoch) {
      _activeSegmentId = null;
      _silentSamples = 0;
      _segmentSamples = 0;
    }
  }

  bool _isSpeaking(double rms) {
    final double adaptiveOn = (_noiseFloorRms * 3).clamp(speechOnRms, 1.0);
    final double adaptiveOff = (_noiseFloorRms * 2).clamp(speechOffRms, 1.0);
    return _activeSegmentId == null ? rms >= adaptiveOn : rms >= adaptiveOff;
  }

  int _durationToSamples(Duration duration) =>
      (duration.inMicroseconds * sampleRate / Duration.microsecondsPerSecond)
          .round();

  double _rms(Uint8List bytes) {
    if (bytes.lengthInBytes < 2) return 0;
    final ByteData pcm = ByteData.sublistView(bytes);
    double sumSquares = 0;
    final int sampleCount = bytes.lengthInBytes ~/ 2;
    for (int offset = 0; offset + 1 < bytes.lengthInBytes; offset += 2) {
      final double sample = pcm.getInt16(offset, Endian.little) / 32768.0;
      sumSquares += sample * sample;
    }
    return math.sqrt(sumSquares / sampleCount);
  }
}
