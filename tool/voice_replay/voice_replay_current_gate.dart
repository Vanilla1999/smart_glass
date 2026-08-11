import 'dart:convert';

import 'voice_replay_log_parser.dart';

class VoiceReplayManifest {
  const VoiceReplayManifest({
    required this.matchToleranceMs,
    required this.recordings,
  });

  final int matchToleranceMs;
  final List<VoiceReplayManifestRecording> recordings;
}

class VoiceReplayManifestRecording {
  const VoiceReplayManifestRecording({
    required this.id,
    required this.file,
    required this.sha256,
    required this.byteLength,
    required this.durationMs,
    required this.packetCount,
    required this.utterances,
  });

  final String id;
  final String file;
  final String sha256;
  final int byteLength;
  final int durationMs;
  final int packetCount;
  final List<VoiceReplayManifestUtterance> utterances;
}

class VoiceReplayManifestUtterance {
  const VoiceReplayManifestUtterance({
    required this.id,
    required this.offsetMs,
    required this.phrases,
    required this.screen,
    required this.action,
    required this.validForScreen,
    required this.required,
  });

  final String id;
  final int offsetMs;
  final List<String> phrases;
  final String screen;
  final String? action;
  final bool validForScreen;
  final bool required;
}

enum VoiceReplayCurrentOutcome {
  success,
  asrMiss,
  postAsrDrop,
  invalidForScreen,
}

class VoiceReplayCurrentRow {
  const VoiceReplayCurrentRow({
    required this.expected,
    required this.outcome,
    this.admission,
    this.action,
  });

  final VoiceReplayManifestUtterance expected;
  final VoiceReplayCurrentOutcome outcome;
  final VoiceReplayLogEvent? admission;
  final VoiceReplayLogEvent? action;
}

class VoiceReplayCurrentRecordingResult {
  const VoiceReplayCurrentRecordingResult({
    required this.recording,
    required this.rows,
    required this.falseActions,
    required this.healthFailures,
  });

  final VoiceReplayManifestRecording recording;
  final List<VoiceReplayCurrentRow> rows;
  final List<VoiceReplayLogEvent> falseActions;
  final List<String> healthFailures;
}

class VoiceReplayCurrentGateResult {
  const VoiceReplayCurrentGateResult(this.recordings);

  final List<VoiceReplayCurrentRecordingResult> recordings;

  Iterable<VoiceReplayCurrentRow> get rows =>
      recordings.expand((recording) => recording.rows);

  int get successCount => rows
      .where((row) => row.outcome == VoiceReplayCurrentOutcome.success)
      .length;

  int get falseActionCount => recordings.fold<int>(
      0, (count, recording) => count + recording.falseActions.length);
}

VoiceReplayManifest loadVoiceReplayManifest(String source) {
  final Map<String, Object?> root = jsonDecode(source) as Map<String, Object?>;
  final Set<String> recordingIds = <String>{};
  final Set<String> utteranceIds = <String>{};
  final List<VoiceReplayManifestRecording> recordings =
      <VoiceReplayManifestRecording>[];
  for (final Object? raw in root['recordings']! as List<Object?>) {
    final Map<String, Object?> recording = raw! as Map<String, Object?>;
    final String id = recording['id']! as String;
    if (!recordingIds.add(id)) {
      throw FormatException('Duplicate recording ID: $id');
    }
    final List<VoiceReplayManifestUtterance> utterances =
        <VoiceReplayManifestUtterance>[];
    for (final Object? rawUtterance
        in recording['utterances']! as List<Object?>) {
      final Map<String, Object?> utterance =
          rawUtterance! as Map<String, Object?>;
      final String utteranceId = utterance['id']! as String;
      if (!utteranceIds.add(utteranceId)) {
        throw FormatException('Duplicate utterance ID: $utteranceId');
      }
      final bool validForScreen = utterance['validForScreen'] as bool? ?? true;
      utterances.add(VoiceReplayManifestUtterance(
        id: utteranceId,
        offsetMs: utterance['offsetMs']! as int,
        phrases: (utterance['phrases']! as List<Object?>).cast<String>(),
        screen: utterance['screen']! as String,
        action: utterance['action'] as String?,
        validForScreen: validForScreen,
        required: utterance['required'] as bool? ?? validForScreen,
      ));
    }
    recordings.add(VoiceReplayManifestRecording(
      id: id,
      file: recording['file']! as String,
      sha256: recording['sha256']! as String,
      byteLength: recording['bytes']! as int,
      durationMs: recording['durationMs']! as int,
      packetCount: recording['packets']! as int,
      utterances: List<VoiceReplayManifestUtterance>.unmodifiable(utterances),
    ));
  }
  return VoiceReplayManifest(
    matchToleranceMs: root['matchToleranceMs']! as int,
    recordings: List<VoiceReplayManifestRecording>.unmodifiable(recordings),
  );
}

VoiceReplayCurrentGateResult scoreCurrentVoiceReplay({
  required VoiceReplayManifest manifest,
  required Map<String, Iterable<String>> logs,
}) {
  final List<VoiceReplayCurrentRecordingResult> results =
      <VoiceReplayCurrentRecordingResult>[];
  for (final VoiceReplayManifestRecording recording in manifest.recordings) {
    final Iterable<String>? lines = logs[recording.id];
    if (lines == null) throw StateError('${recording.id}: log is missing');
    final List<VoiceReplayLogEvent> events = parseVoiceReplayLog(lines);
    final List<String> healthFailures =
        _validateRecordingHealth(recording, events);
    results.add(_scoreRecording(
      recording,
      events,
      manifest.matchToleranceMs,
      healthFailures,
    ));
  }
  return VoiceReplayCurrentGateResult(
    List<VoiceReplayCurrentRecordingResult>.unmodifiable(results),
  );
}

void enforceCurrentVoiceReplayGate(
  VoiceReplayCurrentGateResult result, {
  int minimumSuccesses = 38,
}) {
  final List<String> failures = <String>[];
  for (final VoiceReplayCurrentRow row in result.rows) {
    if (row.expected.required &&
        row.outcome != VoiceReplayCurrentOutcome.success) {
      failures.add('${row.expected.id}=${row.outcome.name}');
    }
  }
  for (final VoiceReplayCurrentRecordingResult recording in result.recordings) {
    failures.addAll(recording.healthFailures);
  }
  if (result.successCount < minimumSuccesses) {
    failures.add('success=${result.successCount}/$minimumSuccesses');
  }
  if (result.falseActionCount != 0) {
    failures.add('falseActions=${result.falseActionCount}');
  }
  if (failures.isNotEmpty) {
    throw StateError('Voice replay gate failed: ${failures.join(', ')}');
  }
}

List<String> _validateRecordingHealth(
  VoiceReplayManifestRecording recording,
  List<VoiceReplayLogEvent> events,
) {
  final List<String> failures = <String>[];
  final List<VoiceReplayLogEvent> identities =
      events.where((event) => event.kind == 'recording').toList();
  if (identities.length != 1) {
    failures.add('${recording.id}: expected one recording identity');
  } else {
    final VoiceReplayLogEvent identity = identities.single;
    if (identity.sha256 != recording.sha256 ||
        identity.byteLength != recording.byteLength ||
        identity.source != recording.file) {
      failures.add('${recording.id}: recording identity mismatch');
    }
  }
  final List<VoiceReplayLogEvent> timeouts = events
      .where((event) =>
          event.kind == 'replayFailure' && event.dropReason == 'timeout')
      .toList();
  if (timeouts.isNotEmpty) {
    failures.add('${recording.id}: terminal replay timeout');
  }
  final List<VoiceReplayLogEvent> summaries =
      events.where((event) => event.kind == 'summary').toList();
  if (summaries.length != 1) {
    failures.add('${recording.id}: expected one continuous summary');
  } else {
    final VoiceReplayLogEvent summary = summaries.single;
    if (summary.packetCount != recording.packetCount ||
        summary.acceptedPackets != recording.packetCount ||
        summary.rejectedPackets != 0) {
      failures.add('${recording.id}: PCM acknowledgement mismatch');
    }
  }
  return failures;
}

VoiceReplayCurrentRecordingResult _scoreRecording(
  VoiceReplayManifestRecording recording,
  List<VoiceReplayLogEvent> events,
  int toleranceMs,
  List<String> healthFailures,
) {
  final List<VoiceReplayLogEvent> admissions = events
      .where((event) =>
          event.kind == 'currentAdmission' &&
          (event.parserDecision == 'accepted'))
      .toList();
  final List<VoiceReplayLogEvent> actions = events
      .where((event) =>
          event.kind == 'completedAction' && event.businessAction == true)
      .toList();
  final Set<VoiceReplayLogEvent> usedAdmissions = <VoiceReplayLogEvent>{};
  final Set<VoiceReplayLogEvent> usedActions = <VoiceReplayLogEvent>{};
  final List<VoiceReplayCurrentRow> rows = <VoiceReplayCurrentRow>[];

  for (final VoiceReplayManifestUtterance expected in recording.utterances) {
    final VoiceReplayLogEvent? admission = _nearestAdmission(
      expected,
      admissions.where((event) => !usedAdmissions.contains(event)),
      toleranceMs,
    );
    if (admission != null) usedAdmissions.add(admission);
    final VoiceReplayLogEvent? action = admission == null
        ? null
        : _matchingAction(
            expected,
            admission,
            actions.where((event) => !usedActions.contains(event)),
          );
    if (action != null) usedActions.add(action);
    final VoiceReplayCurrentOutcome outcome;
    if (!expected.validForScreen) {
      outcome = VoiceReplayCurrentOutcome.invalidForScreen;
    } else if (admission == null) {
      outcome = VoiceReplayCurrentOutcome.asrMiss;
    } else if (action == null) {
      outcome = VoiceReplayCurrentOutcome.postAsrDrop;
    } else {
      outcome = VoiceReplayCurrentOutcome.success;
    }
    rows.add(VoiceReplayCurrentRow(
      expected: expected,
      outcome: outcome,
      admission: admission,
      action: action,
    ));
  }

  final int evaluationStart = recording.utterances
          .map((utterance) => utterance.offsetMs)
          .reduce((left, right) => left < right ? left : right) -
      toleranceMs;
  final int evaluationEnd = recording.utterances
          .map((utterance) => utterance.offsetMs)
          .reduce((left, right) => left > right ? left : right) +
      toleranceMs;
  final List<VoiceReplayLogEvent> falseActions = actions
      .where((event) =>
          !usedActions.contains(event) &&
          event.sourceAudioOffsetMs != null &&
          event.sourceAudioOffsetMs! >= evaluationStart &&
          event.sourceAudioOffsetMs! <= evaluationEnd)
      .toList(growable: false);
  return VoiceReplayCurrentRecordingResult(
    recording: recording,
    rows: List<VoiceReplayCurrentRow>.unmodifiable(rows),
    falseActions: List<VoiceReplayLogEvent>.unmodifiable(falseActions),
    healthFailures: List<String>.unmodifiable(healthFailures),
  );
}

VoiceReplayLogEvent? _nearestAdmission(
  VoiceReplayManifestUtterance expected,
  Iterable<VoiceReplayLogEvent> candidates,
  int toleranceMs,
) {
  VoiceReplayLogEvent? nearest;
  var nearestDistance = toleranceMs + 1;
  for (final VoiceReplayLogEvent candidate in candidates) {
    final int? offset = candidate.sourceAudioOffsetMs;
    if (offset == null || candidate.screen != expected.screen) continue;
    final String text = _normalize(candidate.text ?? '');
    final bool semanticMatch = candidate.operation == expected.action ||
        candidate.text == expected.action ||
        expected.phrases.any((phrase) => _normalize(phrase) == text);
    if (!semanticMatch) continue;
    final int distance = (offset - expected.offsetMs).abs();
    if (distance <= toleranceMs && distance < nearestDistance) {
      nearest = candidate;
      nearestDistance = distance;
    }
  }
  return nearest;
}

VoiceReplayLogEvent? _matchingAction(
  VoiceReplayManifestUtterance expected,
  VoiceReplayLogEvent admission,
  Iterable<VoiceReplayLogEvent> candidates,
) {
  for (final VoiceReplayLogEvent action in candidates) {
    final bool sameIdentity = admission.traceId != null
        ? action.traceId == admission.traceId
        : action.utteranceId == admission.utteranceId;
    if (sameIdentity && action.operation == expected.action) return action;
  }
  return null;
}

String _normalize(String value) => value
    .trim()
    .toLowerCase()
    .replaceAll('ё', 'е')
    .replaceAll(RegExp(r'[^а-яa-z0-9]+'), ' ')
    .trim();
