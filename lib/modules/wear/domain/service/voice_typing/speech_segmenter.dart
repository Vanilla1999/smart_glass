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

class SpeechSegmentDiagnostics {
  const SpeechSegmentDiagnostics({
    required this.rms,
    required this.noiseFloorRms,
    required this.adaptiveOnRms,
    required this.adaptiveOffRms,
    required this.speaking,
  });

  final double rms;
  final double noiseFloorRms;
  final double adaptiveOnRms;
  final double adaptiveOffRms;
  final bool speaking;
}

/// Assigns one identity to every PCM chunk sent to both recognizer lanes.
class SpeechSegmenter {
  SpeechSegmenter({
    this.sampleRate = 16000,
    this.endpointSilence = const Duration(milliseconds: 500),
    this.maxSegmentDuration = const Duration(seconds: 8),
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
    _lastDiagnostics = SpeechSegmentDiagnostics(
      rms: 0,
      noiseFloorRms: _noiseFloorRms,
      adaptiveOnRms: speechOnRms,
      adaptiveOffRms: speechOffRms,
      speaking: false,
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
    );
    if (!speaking) {
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

  int _durationToSamples(Duration duration) =>
      (duration.inMicroseconds * sampleRate / Duration.microsecondsPerSecond)
          .round();

  static const double _zeroRms = 0.0000001;

  void _calibrate(double rms, int sampleCount) {
    if (rms <= _zeroRms) return;
    _calibrationRms.add(rms);
    _calibrationSamples += sampleCount;
    if (_calibrationSamples < _durationToSamples(calibrationDuration)) return;

    final List<double> sorted = List<double>.of(_calibrationRms)..sort();
    final int percentileIndex = ((sorted.length - 1) * 0.3).floor();
    _noiseFloorRms = math.max(initialNoiseFloorRms, sorted[percentileIndex]);
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
    );
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
