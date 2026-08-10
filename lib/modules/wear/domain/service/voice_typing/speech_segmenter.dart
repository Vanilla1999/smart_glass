import 'dart:math' as math;
import 'dart:typed_data';

class SpeechSegment {
  const SpeechSegment({
    required this.captureEpoch,
    required this.segmentId,
    this.speechTurnId = 0,
    required this.lastChunkId,
    required this.isEndpoint,
    required this.started,
    this.endpointReason,
  });

  final int captureEpoch;
  final int segmentId;
  final int speechTurnId;
  final int lastChunkId;
  final bool isEndpoint;
  final bool started;
  final AcousticEndpointReason? endpointReason;
}

enum AcousticEndpointReason { silence, maxDuration, captureStop }

enum VadState {
  calibrating,
  idle,
  candidateSpeech,
  speaking,
  candidateSilence,
  continuationAfterMaxDuration,
}

class VadFrameDecision {
  const VadFrameDecision({
    this.segment,
    required this.retainFrame,
    this.resetRetainedFrames = false,
  });

  final SpeechSegment? segment;

  /// Retain this frame while no segment is emitted. Emitted frames are
  /// consumed directly and must not also be retained by the consumer.
  final bool retainFrame;

  /// Discard frames retained for a candidate that has just been rejected.
  final bool resetRetainedFrames;
}

class SpeechSegmentDiagnostics {
  const SpeechSegmentDiagnostics({
    required this.rms,
    required this.noiseFloorRms,
    required this.adaptiveOnRms,
    required this.adaptiveOffRms,
    required this.speaking,
    this.localBackgroundRms = 0,
    this.snr = 0,
    this.rise = 0,
    this.calibrationP10Rms = 0,
    this.calibrationP50Rms = 0,
    this.calibrationP90Rms = 0,
  });

  final double rms;
  final double noiseFloorRms;
  final double adaptiveOnRms;
  final double adaptiveOffRms;
  final bool speaking;
  final double localBackgroundRms;
  final double snr;
  final double rise;
  final double calibrationP10Rms;
  final double calibrationP50Rms;
  final double calibrationP90Rms;
}

class SpeechSegmenter {
  SpeechSegmenter({
    this.sampleRate = 16000,
    this.endpointSilence = const Duration(milliseconds: 500),
    this.maxSegmentDuration = const Duration(seconds: 4),
    this.maxDurationContinuation = const Duration(milliseconds: 200),
    this.restartConfirmation = const Duration(milliseconds: 40),
    this.onsetConfirmation = Duration.zero,
    this.calibrationDuration = const Duration(milliseconds: 750),
    this.speechOnRms = 0.001,
    this.speechOffRms = 0.0007,
    this.initialNoiseFloorRms = 0.0002,
    this.minimumOnsetSnr = 2.5,
    this.minimumOnsetRise = 1.6,
    this.backgroundAdaptation = 0.02,
  });

  final int sampleRate;
  final Duration endpointSilence;
  final Duration maxSegmentDuration;
  final Duration maxDurationContinuation;
  final Duration restartConfirmation;
  final Duration onsetConfirmation;
  final Duration calibrationDuration;
  double speechOnRms;
  double speechOffRms;
  final double initialNoiseFloorRms;
  final double minimumOnsetSnr;
  final double minimumOnsetRise;
  final double backgroundAdaptation;

  VadState _state = VadState.calibrating;
  int _epoch = 0;
  int _nextSegmentId = 0;
  int _nextSpeechTurnId = 0;
  int _nextChunkId = 0;
  int? _activeSegmentId;
  int? _activeSpeechTurnId;
  int? _continuationSpeechTurnId;
  int? _continuationSegmentId;
  bool _requiresRestartConfirmation = false;
  int _candidateSamples = 0;
  int _silentSamples = 0;
  int _segmentSamples = 0;
  int _calibrationSamples = 0;
  bool _isCalibrated = false;
  final List<double> _calibrationRms = <double>[];
  double _noiseFloorRms = 0.0002;
  double _localBackgroundRms = 0.0002;
  double _previousRms = 0;
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
  VadState get state => _state;

  void configure({required double speechOnRms, required double speechOffRms}) {
    this.speechOnRms = speechOnRms;
    this.speechOffRms = speechOffRms;
  }

  void begin(int captureEpoch) {
    _epoch = captureEpoch;
    _nextSegmentId = 0;
    _nextSpeechTurnId = 0;
    _nextChunkId = 0;
    _activeSegmentId = null;
    _activeSpeechTurnId = null;
    _continuationSpeechTurnId = null;
    _continuationSegmentId = null;
    _requiresRestartConfirmation = false;
    _candidateSamples = 0;
    _silentSamples = 0;
    _segmentSamples = 0;
    _calibrationSamples = 0;
    _calibrationRms.clear();
    _isCalibrated = calibrationDuration == Duration.zero;
    _state = _isCalibrated ? VadState.idle : VadState.calibrating;
    _noiseFloorRms = initialNoiseFloorRms;
    _localBackgroundRms = initialNoiseFloorRms;
    _previousRms = 0;
    _calibrationP10Rms = 0;
    _calibrationP50Rms = 0;
    _calibrationP90Rms = 0;
    _updateDiagnostics(rms: 0, speaking: false, snr: 0, rise: 0);
  }

  /// Compatibility API for direct callers. Streaming consumers should use
  /// [decide] so candidate retention is unambiguous.
  SpeechSegment? add(Uint8List bytes, int captureEpoch) =>
      decide(bytes, captureEpoch).segment;

  VadFrameDecision decide(Uint8List bytes, int captureEpoch) {
    if (captureEpoch != _epoch) {
      return const VadFrameDecision(retainFrame: false);
    }
    final int chunkId = ++_nextChunkId;
    final int sampleCount = bytes.lengthInBytes ~/ 2;
    final double rms = _rms(bytes);
    if (!_isCalibrated) {
      _calibrate(rms, sampleCount);
      _previousRms = rms;
      _updateDiagnostics(rms: rms, speaking: false, snr: 0, rise: 0);
      return const VadFrameDecision(retainFrame: false);
    }

    final double adaptiveOn = math.max(speechOnRms, _noiseFloorRms * 2.5);
    final double adaptiveOff = math.max(speechOffRms, _noiseFloorRms * 1.5);
    final double baseline = math.max(_localBackgroundRms, _zeroRms);
    final double snr = rms / baseline;
    final double rise = rms / math.max(_previousRms, baseline);
    final bool foregroundDelta = rms - baseline >= speechOnRms;
    final bool onset = rms >= adaptiveOn &&
        (snr >= minimumOnsetSnr || rise >= minimumOnsetRise || foregroundDelta);
    final bool voice = rms >= adaptiveOff;
    _updateDiagnostics(
      rms: rms,
      speaking:
          _state == VadState.speaking || _state == VadState.candidateSilence
              ? voice
              : onset,
      snr: snr,
      rise: rise,
    );
    _previousRms = rms;

    switch (_state) {
      case VadState.calibrating:
        throw StateError('calibrated VAD cannot remain calibrating');
      case VadState.idle:
        if (!onset) {
          _adaptBackground(rms, adaptiveOn);
          return const VadFrameDecision(retainFrame: true);
        }
        _state = VadState.candidateSpeech;
        _candidateSamples = sampleCount;
        return _confirmCandidate(chunkId, sampleCount);
      case VadState.candidateSpeech:
        if (!voice) {
          _state = VadState.idle;
          _candidateSamples = 0;
          _adaptBackground(rms, adaptiveOn);
          return const VadFrameDecision(
            retainFrame: false,
            resetRetainedFrames: true,
          );
        }
        _candidateSamples += sampleCount;
        return _confirmCandidate(chunkId, sampleCount);
      case VadState.speaking:
      case VadState.candidateSilence:
        return _duringSpeech(rms, voice, sampleCount, chunkId);
      case VadState.continuationAfterMaxDuration:
        if (onset && rise >= minimumOnsetRise) {
          _state = VadState.candidateSpeech;
          _candidateSamples = sampleCount;
          return _confirmCandidate(chunkId, sampleCount);
        }
        if (!voice) {
          _silentSamples += sampleCount;
          if (_silentSamples >= _durationToSamples(maxDurationContinuation)) {
            final int segmentId = _continuationSegmentId!;
            final int speechTurnId = _continuationSpeechTurnId!;
            _continuationSpeechTurnId = null;
            _continuationSegmentId = null;
            _requiresRestartConfirmation = true;
            _silentSamples = 0;
            _state = VadState.idle;
            return VadFrameDecision(
              segment: SpeechSegment(
                captureEpoch: _epoch,
                segmentId: segmentId,
                speechTurnId: speechTurnId,
                lastChunkId: chunkId,
                isEndpoint: true,
                started: false,
                endpointReason: AcousticEndpointReason.silence,
              ),
              retainFrame: false,
            );
          }
        } else {
          _silentSamples = 0;
        }
        return VadFrameDecision(
          segment: SpeechSegment(
            captureEpoch: _epoch,
            segmentId: _continuationSegmentId!,
            speechTurnId: _continuationSpeechTurnId!,
            lastChunkId: chunkId,
            isEndpoint: false,
            started: false,
          ),
          retainFrame: false,
        );
    }
  }

  VadFrameDecision _confirmCandidate(
    int chunkId,
    int sampleCount, {
    bool reset = false,
  }) {
    final Duration confirmation =
        _continuationSpeechTurnId != null || _requiresRestartConfirmation
            ? restartConfirmation
            : onsetConfirmation;
    if (_candidateSamples < _durationToSamples(confirmation)) {
      return VadFrameDecision(
        retainFrame: true,
        resetRetainedFrames: reset,
      );
    }
    _state = VadState.speaking;
    _candidateSamples = 0;
    _silentSamples = 0;
    _segmentSamples = sampleCount;
    final int segmentId = _activeSegmentId = ++_nextSegmentId;
    final int speechTurnId =
        _activeSpeechTurnId = _continuationSpeechTurnId ?? ++_nextSpeechTurnId;
    _continuationSpeechTurnId = null;
    _continuationSegmentId = null;
    _requiresRestartConfirmation = false;
    return VadFrameDecision(
      segment: SpeechSegment(
        captureEpoch: _epoch,
        segmentId: segmentId,
        speechTurnId: speechTurnId,
        lastChunkId: chunkId,
        isEndpoint: false,
        started: true,
      ),
      retainFrame: false,
    );
  }

  VadFrameDecision _duringSpeech(
    double rms,
    bool voice,
    int sampleCount,
    int chunkId,
  ) {
    final int segmentId = _activeSegmentId!;
    final int speechTurnId = _activeSpeechTurnId!;
    _segmentSamples += sampleCount;
    if (voice) {
      _state = VadState.speaking;
      _silentSamples = 0;
    } else {
      _state = VadState.candidateSilence;
      _silentSamples += sampleCount;
    }
    final bool hardRollover =
        _segmentSamples >= _durationToSamples(maxSegmentDuration);
    final bool silence = _silentSamples >= _durationToSamples(endpointSilence);
    final AcousticEndpointReason? reason = hardRollover
        ? AcousticEndpointReason.maxDuration
        : silence
            ? AcousticEndpointReason.silence
            : null;
    if (reason != null) {
      _activeSegmentId = null;
      _activeSpeechTurnId = null;
      _candidateSamples = 0;
      _silentSamples = 0;
      _segmentSamples = 0;
      if (reason == AcousticEndpointReason.maxDuration) {
        _continuationSpeechTurnId = speechTurnId;
        _continuationSegmentId = segmentId;
        _state = VadState.continuationAfterMaxDuration;
      } else {
        _continuationSpeechTurnId = null;
        _continuationSegmentId = null;
        _requiresRestartConfirmation = true;
        _state = VadState.idle;
      }
    }
    return VadFrameDecision(
      segment: SpeechSegment(
        captureEpoch: _epoch,
        segmentId: segmentId,
        speechTurnId: speechTurnId,
        lastChunkId: chunkId,
        isEndpoint: reason != null,
        started: false,
        endpointReason: reason,
      ),
      retainFrame: false,
    );
  }

  void end(int captureEpoch) {
    if (captureEpoch != _epoch) return;
    _activeSegmentId = null;
    _activeSpeechTurnId = null;
    _continuationSpeechTurnId = null;
    _continuationSegmentId = null;
    _requiresRestartConfirmation = false;
    _state = _isCalibrated ? VadState.idle : VadState.calibrating;
    _candidateSamples = 0;
    _silentSamples = 0;
    _segmentSamples = 0;
  }

  int _durationToSamples(Duration duration) =>
      (duration.inMicroseconds * sampleRate / Duration.microsecondsPerSecond)
          .round();

  static const double _zeroRms = 0.0000001;

  void _adaptBackground(double rms, double adaptiveOn) {
    if (rms <= _zeroRms || rms >= adaptiveOn) return;
    _localBackgroundRms = _localBackgroundRms * (1 - backgroundAdaptation) +
        rms * backgroundAdaptation;
    _noiseFloorRms = math.min(_localBackgroundRms, adaptiveOn * 0.5);
  }

  void _calibrate(double rms, int sampleCount) {
    if (rms <= _zeroRms) return;

    _calibrationSamples += sampleCount;
    _calibrationRms.add(rms);
    if (_calibrationSamples < _durationToSamples(calibrationDuration)) return;
    final List<double> sorted = List<double>.of(_calibrationRms)..sort();
    _calibrationP10Rms = _percentile(sorted, 0.1);
    _calibrationP50Rms = _percentile(sorted, 0.5);
    _calibrationP90Rms = _percentile(sorted, 0.9);
    final double p20 = _percentile(sorted, 0.2);
    _noiseFloorRms = math.max(initialNoiseFloorRms, p20);
    _localBackgroundRms = _noiseFloorRms;
    _isCalibrated = true;
    _state = VadState.idle;
    _calibrationRms.clear();
  }

  void _updateDiagnostics({
    required double rms,
    required bool speaking,
    required double snr,
    required double rise,
  }) {
    _lastDiagnostics = SpeechSegmentDiagnostics(
      rms: rms,
      noiseFloorRms: _noiseFloorRms,
      adaptiveOnRms: math.max(speechOnRms, _noiseFloorRms * 2.5),
      adaptiveOffRms: math.max(speechOffRms, _noiseFloorRms * 1.5),
      speaking: speaking,
      localBackgroundRms: _localBackgroundRms,
      snr: snr,
      rise: rise,
      calibrationP10Rms: _calibrationP10Rms,
      calibrationP50Rms: _calibrationP50Rms,
      calibrationP90Rms: _calibrationP90Rms,
    );
  }

  double _percentile(List<double> sorted, double percentile) =>
      sorted[((sorted.length - 1) * percentile).floor()];

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
