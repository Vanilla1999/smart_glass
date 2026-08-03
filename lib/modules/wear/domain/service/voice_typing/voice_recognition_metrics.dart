class VoiceMetricPercentiles {
  const VoiceMetricPercentiles({
    required this.p50,
    required this.p95,
    required this.p99,
  });

  final int p50;
  final int p95;
  final int p99;
}

class VoiceRecognitionMetricsSnapshot {
  const VoiceRecognitionMetricsSnapshot({
    required this.commandQueueDelay,
    required this.freeTextQueueDelay,
    required this.freeTextAudioLag,
    required this.freeTextQueueWaitAfterEndpoint,
    required this.freeTextFinalization,
    required this.endpointToFreeTextFinal,
    required this.endpointToDecision,
    required this.speechToPhrase,
    required this.liveFreeTextRtf,
    required this.replayFallbackCount,
    required this.replayFallbackReasons,
    required this.conflictCount,
    required this.staleResultCount,
    required this.freeTextDroppedFrames,
    required this.replayAcceptLatency,
    required this.slowReplayAcceptCount,
  });

  final VoiceMetricPercentiles commandQueueDelay;
  final VoiceMetricPercentiles freeTextQueueDelay;
  final VoiceMetricPercentiles freeTextAudioLag;
  final VoiceMetricPercentiles freeTextQueueWaitAfterEndpoint;
  final VoiceMetricPercentiles freeTextFinalization;
  final VoiceMetricPercentiles endpointToFreeTextFinal;
  final VoiceMetricPercentiles endpointToDecision;
  final VoiceMetricPercentiles speechToPhrase;
  final double liveFreeTextRtf;
  final int replayFallbackCount;
  final Map<String, int> replayFallbackReasons;
  final int conflictCount;
  final int staleResultCount;
  final int freeTextDroppedFrames;
  final VoiceMetricPercentiles replayAcceptLatency;
  final int slowReplayAcceptCount;
}

class VoiceRecognitionMetrics {
  final List<int> _commandQueueDelay = <int>[];
  final List<int> _freeTextQueueDelay = <int>[];
  final List<int> _freeTextAudioLag = <int>[];
  final List<int> _freeTextQueueWaitAfterEndpoint = <int>[];
  final List<int> _freeTextFinalization = <int>[];
  final List<int> _endpointToFreeTextFinal = <int>[];
  final List<int> _endpointToDecision = <int>[];
  final List<int> _speechToPhrase = <int>[];
  final Map<String, int> _fallbackReasons = <String, int>{};
  int _freeTextRecognizerMs = 0;
  int _freeTextAudioMs = 0;
  int _fallbacks = 0;
  int _conflicts = 0;
  int _stale = 0;
  int _dropped = 0;
  final List<int> _replayAcceptLatency = <int>[];
  int _slowReplayAccepts = 0;

  void recordCommandQueueDelay(int milliseconds) =>
      _record(_commandQueueDelay, milliseconds);

  void recordFreeTextChunk({
    required int queueDelayMs,
    required int audioLagMs,
    required int recognizerMs,
    required int audioMs,
  }) {
    _record(_freeTextQueueDelay, queueDelayMs);
    _record(_freeTextAudioLag, audioLagMs);
    _freeTextRecognizerMs += recognizerMs;
    _freeTextAudioMs += audioMs;
  }

  void recordFallback(String reason) {
    _fallbacks++;
    _fallbackReasons.update(reason, (int count) => count + 1,
        ifAbsent: () => 1);
  }

  void recordLiveFinalization({
    required int queueWaitAfterEndpointMs,
    required int finalizationMs,
    required int endpointToFreeTextFinalMs,
  }) {
    _record(_freeTextQueueWaitAfterEndpoint, queueWaitAfterEndpointMs);
    _record(_freeTextFinalization, finalizationMs);
    _record(_endpointToFreeTextFinal, endpointToFreeTextFinalMs);
  }

  void recordDecision({
    required int endpointToDecisionMs,
    int? speechToPhraseMs,
  }) {
    _record(_endpointToDecision, endpointToDecisionMs);
    if (speechToPhraseMs != null) {
      _record(_speechToPhrase, speechToPhraseMs);
    }
  }

  void recordConflict() => _conflicts++;
  void recordStale() => _stale++;
  void recordDroppedFrame() => _dropped++;

  void recordReplayAcceptLatency(int milliseconds) {
    _record(_replayAcceptLatency, milliseconds);
    if (milliseconds >= 150) _slowReplayAccepts++;
  }

  VoiceRecognitionMetricsSnapshot snapshot() => VoiceRecognitionMetricsSnapshot(
        commandQueueDelay: _percentiles(_commandQueueDelay),
        freeTextQueueDelay: _percentiles(_freeTextQueueDelay),
        freeTextAudioLag: _percentiles(_freeTextAudioLag),
        freeTextQueueWaitAfterEndpoint:
            _percentiles(_freeTextQueueWaitAfterEndpoint),
        freeTextFinalization: _percentiles(_freeTextFinalization),
        endpointToFreeTextFinal: _percentiles(_endpointToFreeTextFinal),
        endpointToDecision: _percentiles(_endpointToDecision),
        speechToPhrase: _percentiles(_speechToPhrase),
        liveFreeTextRtf: _freeTextAudioMs == 0
            ? 0
            : _freeTextRecognizerMs / _freeTextAudioMs,
        replayFallbackCount: _fallbacks,
        replayFallbackReasons: Map<String, int>.unmodifiable(_fallbackReasons),
        conflictCount: _conflicts,
        staleResultCount: _stale,
        freeTextDroppedFrames: _dropped,
        replayAcceptLatency: _percentiles(_replayAcceptLatency),
        slowReplayAcceptCount: _slowReplayAccepts,
      );

  void _record(List<int> values, int value) {
    values.add(value);
    if (values.length > 2048) values.removeAt(0);
  }

  VoiceMetricPercentiles _percentiles(List<int> source) {
    if (source.isEmpty) {
      return const VoiceMetricPercentiles(p50: 0, p95: 0, p99: 0);
    }
    final List<int> sorted = List<int>.of(source)..sort();
    int at(int percentile) {
      final int index = ((sorted.length - 1) * percentile / 100).ceil();
      return sorted[index.clamp(0, sorted.length - 1)];
    }

    return VoiceMetricPercentiles(p50: at(50), p95: at(95), p99: at(99));
  }
}
