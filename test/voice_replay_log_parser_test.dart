import 'package:flutter_test/flutter_test.dart';

import '../tool/voice_replay/voice_replay_log_parser.dart';

void main() {
  test('parses physical Vosk partial and endpoint result', () {
    final VoiceReplayLogEvent partial = parseVoiceReplayLogLine(
      '08-10 18:01:11.320 I/flutter (14947): '
      '[VOSK][PARTIAL][command] назад at 1786374071320 '
      '(queueDelayMs=0, acceptMs=32, partialMs=20, chunkTotalMs=52)',
    )!;
    final VoiceReplayLogEvent result = parseVoiceReplayLogLine(
      '08-10 18:01:12.300 I/flutter (14947): '
      '[VOSK][ENDPOINT_RESULT][command] назад at 1786374072299 '
      '(queueDelayMs=0, acceptMs=39, resultMs=14, chunkTotalMs=53)',
    )!;

    expect(partial.kind, 'voskPartial');
    expect(partial.text, 'назад');
    expect(partial.timestampMs, 1786374071320);
    expect(result.kind, 'voskFinal');
    expect(result.text, 'назад');
    expect(result.timestampMs, 1786374072299);
  });

  test('parses command identity and source screen', () {
    final VoiceReplayLogEvent event = parseVoiceReplayLogLine(
      '[VOICE_COMMAND] captureEpoch=1 acousticSegmentId=9 '
      'commandUtteranceId=17 routeRevision=8 grammarRevision=9 '
      'screen=voiceClarification kind=endpointResult text="назад" '
      'command=WearVoiceCommand.back',
    )!;

    expect(event.utteranceId, 17);
    expect(event.segmentId, 9);
    expect(event.screen, 'voiceClarification');
    expect(event.text, 'назад');
    expect(event.parserDecision, 'endpointResult');
  });

  test('parses terminal replay rejection', () {
    final VoiceReplayLogEvent event = parseVoiceReplayLogLine(
      '[VOICE_FREE_TEXT_REPLAY_TRACE] stage=decision_rejected '
      'reason=dynamicItemsChanged captureEpoch=1 segmentId=19 '
      'utteranceId=29 sourceScreen=printerSelect routeRevision=15',
    )!;

    expect(event.kind, 'replayDecision');
    expect(event.utteranceId, 29);
    expect(event.segmentId, 19);
    expect(event.screen, 'printerSelect');
    expect(event.parserDecision, 'rejected');
    expect(event.dropReason, 'dynamicItemsChanged');
  });

  test('parses dispatcher admission separately from UI feedback', () {
    final VoiceReplayLogEvent action = parseVoiceReplayLogLine(
      '[WearVoiceApplicationDispatcher] voice command received '
      'command=WearVoiceCommand.back screen=WearScreenId.availabilityProduct '
      'at=1786374372738',
    )!;
    final VoiceReplayLogEvent? feedback = parseVoiceReplayLogLine(
      '[VOICE_FEEDBACK] kind=processing visible=true '
      'status="Распознаю..." screen=availabilityProduct',
    );

    expect(action.kind, 'dispatcherAdmission');
    expect(action.text, 'back');
    expect(action.screen, 'availabilityProduct');
    expect(action.timestampMs, 1786374372738);
    expect(action.businessAction, isFalse);
    expect(feedback, isNull);
  });

  test('keeps empty partial as ASR evidence', () {
    final VoiceReplayLogEvent event = parseVoiceReplayLogLine(
      '[VOSK][PARTIAL][command]  at 1786374079767 '
      '(queueDelayMs=0, acceptMs=65, partialMs=17, chunkTotalMs=82)',
    )!;

    expect(event.text, isEmpty);
  });

  test('parses replay timeout and native scheduler timings', () {
    final VoiceReplayLogEvent timeout = parseVoiceReplayLogLine(
      '[VOICE_FREE_TEXT_REPLAY_TRACE] stage=failed operation=accept_wait '
      'segmentId=3 utteranceId=7 nativeStage=accept '
      'error=TimeoutException: replay expired',
    )!;
    final VoiceReplayLogEvent scheduler = parseVoiceReplayLogLine(
      '[VOSK_SCHEDULER] stage=done seq=42 recognizerId=2 lane=freeText '
      'operation=acceptWaveForm waitMs=75 runMs=410 queueDepth=0',
    )!;

    expect(timeout.kind, 'replayFailure');
    expect(timeout.utteranceId, 7);
    expect(timeout.nativeStage, 'accept');
    expect(timeout.dropReason, 'timeout');
    expect(scheduler.kind, 'nativeScheduler');
    expect(scheduler.sequence, 42);
    expect(scheduler.operation, 'acceptWaveForm');
    expect(scheduler.waitMs, 75);
    expect(scheduler.runMs, 410);
  });

  test('parses current recording, admission, completed action and summary', () {
    final VoiceReplayLogEvent recording = parseVoiceReplayLogLine(
      'VOICE_REPLAY_RECORDING sha256=abc bytes=100 source=fixture.wav',
    )!;
    final VoiceReplayLogEvent admission = parseVoiceReplayLogLine(
      'VOICE_CONTINUOUS_EVENT '
      '{"stage":"command","command":"back","decision":"accepted",'
      '"screen":"menu","utteranceId":4,"traceId":"t4",'
      '"sourceAudioOffsetMs":1200}',
    )!;
    final VoiceReplayLogEvent action = parseVoiceReplayLogLine(
      'VOICE_CONTINUOUS_EVENT '
      '{"stage":"action","action":"back","completed":true,'
      '"screen":"menu","utteranceId":4,"traceId":"t4",'
      '"sourceAudioOffsetMs":1200}',
    )!;
    final VoiceReplayLogEvent summary = parseVoiceReplayLogLine(
      'VOICE_CONTINUOUS_SUMMARY '
      '{"packets":3,"acceptedAcks":3,"rejectedAcks":0}',
    )!;

    expect(recording.sha256, 'abc');
    expect(recording.byteLength, 100);
    expect(admission.kind, 'currentAdmission');
    expect(admission.parserDecision, 'accepted');
    expect(admission.sourceAudioOffsetMs, 1200);
    expect(action.kind, 'completedAction');
    expect(action.operation, 'back');
    expect(action.businessAction, isTrue);
    expect(summary.packetCount, 3);
    expect(summary.rejectedPackets, 0);
  });
}
