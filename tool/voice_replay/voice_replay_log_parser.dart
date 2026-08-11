import 'dart:convert';

class VoiceReplayLogEvent {
  const VoiceReplayLogEvent({
    required this.kind,
    this.timestampMs,
    this.utteranceId,
    this.segmentId,
    this.screen,
    this.text,
    this.parserDecision,
    this.dropReason,
    this.businessAction,
    this.nativeStage,
    this.operation,
    this.sequence,
    this.waitMs,
    this.runMs,
    this.sourceAudioOffsetMs,
    this.traceId,
    this.sha256,
    this.byteLength,
    this.source,
    this.packetCount,
    this.acceptedPackets,
    this.rejectedPackets,
  });

  final String kind;
  final int? timestampMs;
  final int? utteranceId;
  final int? segmentId;
  final String? screen;
  final String? text;
  final String? parserDecision;
  final String? dropReason;
  final bool? businessAction;
  final String? nativeStage;
  final String? operation;
  final int? sequence;
  final int? waitMs;
  final int? runMs;
  final int? sourceAudioOffsetMs;
  final String? traceId;
  final String? sha256;
  final int? byteLength;
  final String? source;
  final int? packetCount;
  final int? acceptedPackets;
  final int? rejectedPackets;
}

final RegExp _timestampPattern = RegExp(r' at[= ](\d{13})(?:\s|\(|$)');
final RegExp _utterancePattern =
    RegExp(r'(?:commandUtteranceId|utteranceId)=(\d+)');
final RegExp _segmentPattern = RegExp(r'(?:acousticSegmentId|segmentId)=(\d+)');
final RegExp _screenPattern =
    RegExp(r'(?:sourceScreen|screen)=(?:WearScreenId\.)?([A-Za-z]+)');
final RegExp _textPattern = RegExp(r'text="([^"]*)"');

VoiceReplayLogEvent? parseVoiceReplayLogLine(String line) {
  int? integer(RegExp pattern) {
    final String? value = pattern.firstMatch(line)?.group(1);
    return value == null ? null : int.parse(value);
  }

  final int recordingIndex = line.indexOf('VOICE_REPLAY_RECORDING ');
  if (recordingIndex >= 0) {
    final String payload = line.substring(
      recordingIndex + 'VOICE_REPLAY_RECORDING '.length,
    );
    String? field(String name) =>
        RegExp('(?:^| )$name=([^ ]+)').firstMatch(payload)?.group(1);
    return VoiceReplayLogEvent(
      kind: 'recording',
      sha256: field('sha256'),
      byteLength: int.tryParse(field('bytes') ?? ''),
      source: field('source'),
    );
  }

  final int continuousEventIndex = line.indexOf('VOICE_CONTINUOUS_EVENT ');
  if (continuousEventIndex >= 0) {
    final Map<String, Object?> payload = jsonDecode(line.substring(
      continuousEventIndex + 'VOICE_CONTINUOUS_EVENT '.length,
    )) as Map<String, Object?>;
    final String stage = payload['stage']! as String;
    return VoiceReplayLogEvent(
      kind: stage == 'action' ? 'completedAction' : 'currentAdmission',
      utteranceId: payload['utteranceId'] as int?,
      screen: payload['screen'] as String?,
      text: (payload['command'] ?? payload['phrase'] ?? payload['action'])
          as String?,
      parserDecision: payload['decision'] as String?,
      businessAction: payload['completed'] as bool?,
      sourceAudioOffsetMs: payload['sourceAudioOffsetMs'] as int?,
      traceId: payload['traceId'] as String?,
      operation: payload['action'] as String?,
    );
  }

  final int summaryIndex = line.indexOf('VOICE_CONTINUOUS_SUMMARY ');
  if (summaryIndex >= 0) {
    final Map<String, Object?> payload = jsonDecode(line.substring(
      summaryIndex + 'VOICE_CONTINUOUS_SUMMARY '.length,
    )) as Map<String, Object?>;
    return VoiceReplayLogEvent(
      kind: 'summary',
      packetCount: payload['packets'] as int?,
      acceptedPackets: payload['acceptedAcks'] as int?,
      rejectedPackets: payload['rejectedAcks'] as int?,
    );
  }

  if (line.contains('[VOSK][PARTIAL][command]')) {
    final RegExpMatch? match = RegExp(
      r'\[VOSK\]\[PARTIAL\]\[command\] (.*?) at (\d{13})',
    ).firstMatch(line);
    if (match == null) return null;
    return VoiceReplayLogEvent(
      kind: 'voskPartial',
      timestampMs: int.parse(match.group(2)!),
      text: match.group(1),
    );
  }

  if (line.contains('[VOSK][ENDPOINT_RESULT][command]')) {
    final RegExpMatch? match = RegExp(
      r'\[VOSK\]\[ENDPOINT_RESULT\]\[command\] (.*?) at (\d{13})',
    ).firstMatch(line);
    if (match == null) return null;
    return VoiceReplayLogEvent(
      kind: 'voskFinal',
      timestampMs: int.parse(match.group(2)!),
      text: match.group(1),
    );
  }

  if (line.contains('[VOICE_COMMAND]')) {
    final String? commandKind =
        RegExp(r' kind=([A-Za-z]+)').firstMatch(line)?.group(1);
    return VoiceReplayLogEvent(
      kind: 'voiceCommand',
      utteranceId: integer(_utterancePattern),
      segmentId: integer(_segmentPattern),
      screen: _screenPattern.firstMatch(line)?.group(1),
      text: _textPattern.firstMatch(line)?.group(1),
      parserDecision: commandKind,
    );
  }

  if (line.contains('[VOICE_POLICY]')) {
    return VoiceReplayLogEvent(
      kind: 'parserPolicy',
      utteranceId: integer(_utterancePattern),
      screen: _screenPattern.firstMatch(line)?.group(1),
      text: _textPattern.firstMatch(line)?.group(1),
      parserDecision: RegExp(r' decision=([^\s]+)').firstMatch(line)?.group(1),
    );
  }

  if (line.contains('[VOICE_FREE_TEXT_REPLAY_TRACE]') &&
      line.contains('stage=decision_')) {
    return VoiceReplayLogEvent(
      kind: 'replayDecision',
      utteranceId: integer(_utterancePattern),
      segmentId: integer(_segmentPattern),
      screen: _screenPattern.firstMatch(line)?.group(1),
      parserDecision:
          RegExp(r' stage=decision_([^\s]+)').firstMatch(line)?.group(1),
      dropReason: RegExp(r' reason=([^\s]+)').firstMatch(line)?.group(1),
    );
  }

  if (line.contains('[VOICE_FREE_TEXT_REPLAY_TRACE]') &&
      line.contains('stage=failed')) {
    return VoiceReplayLogEvent(
      kind: 'replayFailure',
      utteranceId: integer(_utterancePattern),
      segmentId: integer(_segmentPattern),
      screen: _screenPattern.firstMatch(line)?.group(1),
      nativeStage: RegExp(r' nativeStage=([^\s]+)').firstMatch(line)?.group(1),
      operation: RegExp(r' operation=([^\s]+)').firstMatch(line)?.group(1),
      dropReason: line.contains('TimeoutException') ? 'timeout' : 'failure',
    );
  }

  if (line.contains('[VOSK_SCHEDULER]') &&
      (line.contains('stage=start') || line.contains('stage=done'))) {
    return VoiceReplayLogEvent(
      kind: 'nativeScheduler',
      nativeStage: RegExp(r' stage=([^\s]+)').firstMatch(line)?.group(1),
      operation: RegExp(r' operation=([^\s]+)').firstMatch(line)?.group(1),
      sequence: integer(RegExp(r' seq=(\d+)')),
      waitMs: integer(RegExp(r' waitMs=(\d+)')),
      runMs: integer(RegExp(r' runMs=(\d+)')),
    );
  }

  if (line.contains('[WearVoiceApplicationDispatcher]') &&
      (line.contains(' voice command received ') ||
          line.contains(' voice phrase received '))) {
    final String? phrase =
        RegExp(r' phrase="([^"]*)"').firstMatch(line)?.group(1);
    final String? command = RegExp(
      r' command=WearVoiceCommand\.([A-Za-z]+)',
    ).firstMatch(line)?.group(1);
    return VoiceReplayLogEvent(
      kind: 'dispatcherAdmission',
      timestampMs: integer(_timestampPattern),
      screen: _screenPattern.firstMatch(line)?.group(1),
      text: phrase ?? command,
      businessAction: false,
    );
  }

  return null;
}

List<VoiceReplayLogEvent> parseVoiceReplayLog(Iterable<String> lines) =>
    <VoiceReplayLogEvent>[
      for (final String line in lines)
        if (parseVoiceReplayLogLine(line) case final VoiceReplayLogEvent event)
          event,
    ];
