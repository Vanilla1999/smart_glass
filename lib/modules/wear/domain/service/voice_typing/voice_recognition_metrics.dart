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
    required this.liveFreeTextRtf,
    required this.replayFallbackCount,
    required this.replayFallbackReasons,
    required this.conflictCount,
    required this.staleResultCount,
    required this.freeTextDroppedFrames,
  });

  final VoiceMetricPercentiles commandQueueDelay;
  final VoiceMetricPercentiles freeTextQueueDelay;
  final VoiceMetricPercentiles freeTextAudioLag;
  final double liveFreeTextRtf;
  final int replayFallbackCount;
  final Map<String, int> replayFallbackReasons;
  final int conflictCount;
  final int staleResultCount;
  final int freeTextDroppedFrames;
}

class VoiceRecognitionMetrics {
  final List<int> _commandQueueDelay = <int>[];
  final List<int> _freeTextQueueDelay = <int>[];
  final List<int> _freeTextAudioLag = <int>[];
  final Map<String, int> _fallbackReasons = <String, int>{};
  int _freeTextRecognizerMs = 0;
  int _freeTextAudioMs = 0;
  int _fallbacks = 0;
  int _conflicts = 0;
  int _stale = 0;
  int _dropped = 0;

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

  void recordConflict() => _conflicts++;
  void recordStale() => _stale++;
  void recordDroppedFrame() => _dropped++;

  VoiceRecognitionMetricsSnapshot snapshot() => VoiceRecognitionMetricsSnapshot(
        commandQueueDelay: _percentiles(_commandQueueDelay),
        freeTextQueueDelay: _percentiles(_freeTextQueueDelay),
        freeTextAudioLag: _percentiles(_freeTextAudioLag),
        liveFreeTextRtf: _freeTextAudioMs == 0
            ? 0
            : _freeTextRecognizerMs / _freeTextAudioMs,
        replayFallbackCount: _fallbacks,
        replayFallbackReasons: Map<String, int>.unmodifiable(_fallbackReasons),
        conflictCount: _conflicts,
        staleResultCount: _stale,
        freeTextDroppedFrames: _dropped,
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
