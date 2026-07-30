import 'package:flutter_test/flutter_test.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_typing/voice_recognition_metrics.dart';

void main() {
  test('reports queue/audio percentiles, RTF and counters', () {
    final VoiceRecognitionMetrics metrics = VoiceRecognitionMetrics();
    for (int value = 1; value <= 100; value++) {
      metrics.recordCommandQueueDelay(value);
      metrics.recordFreeTextChunk(
        queueDelayMs: value * 2,
        audioLagMs: value * 3,
        recognizerMs: 10,
        audioMs: 20,
      );
    }
    metrics
      ..recordFallback('live_lane_timeout')
      ..recordLiveFinalization(
        queueWaitAfterEndpointMs: 30,
        finalizationMs: 40,
        endpointToFreeTextFinalMs: 70,
      )
      ..recordDecision(
        endpointToDecisionMs: 75,
        speechToPhraseMs: 1100,
      )
      ..recordConflict()
      ..recordStale()
      ..recordDroppedFrame();

    final VoiceRecognitionMetricsSnapshot result = metrics.snapshot();
    expect(result.commandQueueDelay.p50, 51);
    expect(result.commandQueueDelay.p95, 96);
    expect(result.commandQueueDelay.p99, 100);
    expect(result.freeTextQueueDelay.p95, 192);
    expect(result.freeTextAudioLag.p99, 300);
    expect(result.freeTextQueueWaitAfterEndpoint.p50, 30);
    expect(result.freeTextFinalization.p50, 40);
    expect(result.endpointToFreeTextFinal.p50, 70);
    expect(result.endpointToDecision.p50, 75);
    expect(result.speechToPhrase.p50, 1100);
    expect(result.liveFreeTextRtf, 0.5);
    expect(result.replayFallbackReasons, {'live_lane_timeout': 1});
    expect(result.conflictCount, 1);
    expect(result.staleResultCount, 1);
    expect(result.freeTextDroppedFrames, 1);
  });
}
