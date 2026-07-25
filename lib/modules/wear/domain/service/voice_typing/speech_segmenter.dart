import 'dart:typed_data';

class SpeechSegment {
  const SpeechSegment({
    required this.captureEpoch,
    required this.segmentId,
    required this.lastChunkId,
    required this.isEndpoint,
  });

  final int captureEpoch;
  final int segmentId;
  final int lastChunkId;
  final bool isEndpoint;
}

/// Assigns one identity to every PCM chunk sent to both recognizer lanes.
class SpeechSegmenter {
  SpeechSegmenter({
    this.endpointSilenceChunks = 8,
    this.silencePeakThreshold = 0.015,
  });

  final int endpointSilenceChunks;
  final double silencePeakThreshold;
  int _epoch = 0;
  int _nextSegmentId = 0;
  int _nextChunkId = 0;
  int? _activeSegmentId;
  int _silentChunks = 0;

  void begin(int captureEpoch) {
    _epoch = captureEpoch;
    _nextSegmentId = 0;
    _nextChunkId = 0;
    _activeSegmentId = null;
    _silentChunks = 0;
  }

  SpeechSegment? add(Uint8List bytes, int captureEpoch) {
    if (captureEpoch != _epoch) return null;
    final int chunkId = ++_nextChunkId;
    if (_isSilent(bytes)) {
      final int? segmentId = _activeSegmentId;
      if (segmentId == null) return null;
      _silentChunks++;
      final bool endpoint = _silentChunks >= endpointSilenceChunks;
      if (endpoint) {
        _activeSegmentId = null;
        _silentChunks = 0;
      }
      return SpeechSegment(
        captureEpoch: _epoch,
        segmentId: segmentId,
        lastChunkId: chunkId,
        isEndpoint: endpoint,
      );
    }

    _silentChunks = 0;
    final int segmentId = _activeSegmentId ??= ++_nextSegmentId;
    return SpeechSegment(
      captureEpoch: _epoch,
      segmentId: segmentId,
      lastChunkId: chunkId,
      isEndpoint: false,
    );
  }

  void end(int captureEpoch) {
    if (captureEpoch == _epoch) {
      _activeSegmentId = null;
      _silentChunks = 0;
    }
  }

  bool _isSilent(Uint8List bytes) {
    if (bytes.lengthInBytes < 2) return true;
    final ByteData pcm = ByteData.sublistView(bytes);
    for (int offset = 0; offset + 1 < bytes.lengthInBytes; offset += 2) {
      final int sample = pcm.getInt16(offset, Endian.little).abs();
      if (sample / 32768.0 > silencePeakThreshold) return false;
    }
    return true;
  }
}
