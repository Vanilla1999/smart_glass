import 'dart:math' as math;
import 'dart:typed_data';

class SpeechSegment {
  const SpeechSegment({
    required this.captureEpoch,
    required this.segmentId,
    required this.lastChunkId,
    required this.isEndpoint,
    required this.started,
    this.endpointReason,
  });

  final int captureEpoch;
  final int segmentId;
  final int lastChunkId;
  final bool isEndpoint;
  final bool started;
  final AcousticEndpointReason? endpointReason;
}

enum AcousticEndpointReason { silence, maxDuration, captureStop }

class SpeechSegmentDiagnostics {
  const SpeechSegmentDiagnostics({
    required this.rms,
    required this.noiseFloorRms,
    required this.adaptiveOnRms,
    required this.adaptiveOffRms,
    required this.speaking,
    this.calibrationP10Rms = 0,
    this.calibrationP50Rms = 0,
    this.calibrationP90Rms = 0,
  });

  final double rms;
  final double noiseFloorRms;
  final double adaptiveOnRms;
  final double adaptiveOffRms;
  final bool speaking;
  final double calibrationP10Rms;
  final double calibrationP50Rms;
  final double calibrationP90Rms;
}

/// Assigns one identity to every PCM chunk sent to both recognizer lanes.
class SpeechSegmenter {
  SpeechSegmenter({
    this.sampleRate = 16000,
    this.endpointSilence = const Duration(milliseconds: 500),
    this.maxSegmentDuration = const Duration(seconds: 4),
    this.calibrationDuration = const Duration(milliseconds: 750),
    this.speechOnRms = 0.001,
    this.speechOffRms = 0.0007,
    this.initialNoiseFloorRms = 0.0002,
  });

  final int sampleRate;
  final Duration endpointSilence;
  final Duration maxSegmentDuration;
  final Duration calibrationDuration;
  double speechOnRms;
  double speechOffRms;
  final double initialNoiseFloorRms;
  int _epoch = 0;
  int _nextSegmentId = 0;
  int _nextChunkId = 0;
  int? _activeSegmentId;
  int _silentSamples = 0;
  int _segmentSamples = 0;
  int _calibrationSamples = 0;
  bool _isCalibrated = false;
  final List<double> _calibrationRms = <double>[];
  double _noiseFloorRms = 0.0002;
  double _calibrationP10Rms = 0;
  double _calibrationP50Rms = 0;
  double _calibrationP90Rms = 0;
  SpeechSegmentDiagnostics _lastDiagnostics = const SpeechSegmentDiagnostics(
    rms: 0,
    noiseFloorRms: 0.0002,
    adaptiveOnRms: 0.001,
    adaptiveOffRms: 0.0007,
    speaking: false,
  );

  SpeechSegmentDiagnostics get lastDiagnostics => _lastDiagnostics;
  bool get isCalibrated => _isCalibrated;

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
    _calibrationSamples = 0;
    _calibrationRms.clear();
    _isCalibrated = calibrationDuration == Duration.zero;
    _noiseFloorRms = initialNoiseFloorRms;
    _calibrationP10Rms = 0;
    _calibrationP50Rms = 0;
    _calibrationP90Rms = 0;
    _lastDiagnostics = SpeechSegmentDiagnostics(
      rms: 0,
      noiseFloorRms: _noiseFloorRms,
      adaptiveOnRms: speechOnRms,
      adaptiveOffRms: speechOffRms,
      speaking: false,
      calibrationP10Rms: 0,
      calibrationP50Rms: 0,
      calibrationP90Rms: 0,
    );
  }

  SpeechSegment? add(Uint8List bytes, int captureEpoch) {
    if (captureEpoch != _epoch) return null;
    final int chunkId = ++_nextChunkId;
    final int sampleCount = bytes.lengthInBytes ~/ 2;
    final double rms = _rms(bytes);
    if (!_isCalibrated) {
      _calibrate(rms, sampleCount);
      _updateDiagnostics(rms: rms, speaking: false);
      return null;
    }

    double adaptiveOn = (_noiseFloorRms * 2.5).clamp(speechOnRms, 1.0);
    double adaptiveOff = (_noiseFloorRms * 1.5).clamp(speechOffRms, 1.0);
    final bool speaking =
        _activeSegmentId == null ? rms >= adaptiveOn : rms >= adaptiveOff;
    if (!speaking &&
        _activeSegmentId == null &&
        rms > _zeroRms &&
        rms < adaptiveOn) {
      final double adapted = _noiseFloorRms * 0.98 + rms * 0.02;
      _noiseFloorRms = math.min(adapted, adaptiveOn * 0.5);
      adaptiveOn = (_noiseFloorRms * 2.5).clamp(speechOnRms, 1.0);
      adaptiveOff = (_noiseFloorRms * 1.5).clamp(speechOffRms, 1.0);
    }
    _lastDiagnostics = SpeechSegmentDiagnostics(
      rms: rms,
      noiseFloorRms: _noiseFloorRms,
      adaptiveOnRms: adaptiveOn,
      adaptiveOffRms: adaptiveOff,
      speaking: speaking,
      calibrationP10Rms: _calibrationP10Rms,
      calibrationP50Rms: _calibrationP50Rms,
      calibrationP90Rms: _calibrationP90Rms,
    );
    if (!speaking) {
      final int? segmentId = _activeSegmentId;
      if (segmentId == null) return null;
      _silentSamples += sampleCount;
      _segmentSamples += sampleCount;
      final bool endpoint =
          _silentSamples >= _durationToSamples(endpointSilence) ||
              _segmentSamples >= _durationToSamples(maxSegmentDuration);
      final AcousticEndpointReason? endpointReason = endpoint
          ? (_segmentSamples >= _durationToSamples(maxSegmentDuration)
              ? AcousticEndpointReason.maxDuration
              : AcousticEndpointReason.silence)
          : null;
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
        endpointReason: endpointReason,
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
      endpointReason: endpoint ? AcousticEndpointReason.maxDuration : null,
    );
  }

  void end(int captureEpoch) {
    if (captureEpoch == _epoch) {
      _activeSegmentId = null;
      _silentSamples = 0;
      _segmentSamples = 0;
    }
  }

  int _durationToSamples(Duration duration) =>
      (duration.inMicroseconds * sampleRate / Duration.microsecondsPerSecond)
          .round();

  static const double _zeroRms = 0.0000001;

  void _calibrate(double rms, int sampleCount) {
    _calibrationSamples += sampleCount;
    if (rms > _zeroRms) _calibrationRms.add(rms);
    if (_calibrationSamples < _durationToSamples(calibrationDuration)) return;

    final List<double> sorted = List<double>.of(_calibrationRms)..sort();
    _calibrationP10Rms = sorted.isEmpty ? 0 : _percentile(sorted, 0.1);
    _calibrationP50Rms = sorted.isEmpty ? 0 : _percentile(sorted, 0.5);
    _calibrationP90Rms = sorted.isEmpty ? 0 : _percentile(sorted, 0.9);
    final double p20 = sorted.isEmpty ? 0 : _percentile(sorted, 0.2);
    _noiseFloorRms = math.max(initialNoiseFloorRms, p20);
    _isCalibrated = true;
    _calibrationRms.clear();
  }

  void _updateDiagnostics({required double rms, required bool speaking}) {
    _lastDiagnostics = SpeechSegmentDiagnostics(
      rms: rms,
      noiseFloorRms: _noiseFloorRms,
      adaptiveOnRms: (_noiseFloorRms * 2.5).clamp(speechOnRms, 1.0),
      adaptiveOffRms: (_noiseFloorRms * 1.5).clamp(speechOffRms, 1.0),
      speaking: speaking,
      calibrationP10Rms: _calibrationP10Rms,
      calibrationP50Rms: _calibrationP50Rms,
      calibrationP90Rms: _calibrationP90Rms,
    );
  }

  double _percentile(List<double> sorted, double percentile) {
    return sorted[((sorted.length - 1) * percentile).floor()];
  }

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
