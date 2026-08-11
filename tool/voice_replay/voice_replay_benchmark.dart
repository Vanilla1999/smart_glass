import 'dart:convert';

import 'voice_replay_scorer.dart';
import 'voice_replay_log_parser.dart';

class VoiceReplayBenchmarkRow {
  const VoiceReplayBenchmarkRow({
    required this.id,
    required this.recordingId,
    required this.expectedPhrase,
    required this.expectedScreen,
    required this.voskPartial,
    required this.voskFinal,
    required this.parserDecision,
    required this.businessAction,
    required this.classification,
    this.utteranceId,
    this.dropReason,
  });

  final String id;
  final String recordingId;
  final String? expectedPhrase;
  final String expectedScreen;
  final String voskPartial;
  final String voskFinal;
  final String parserDecision;
  final String? dropReason;
  final bool businessAction;
  final String classification;
  final int? utteranceId;
}

class VoiceReplayBenchmark {
  const VoiceReplayBenchmark(this.rows);

  final List<VoiceReplayBenchmarkRow> rows;

  Map<String, int> get totals {
    final Map<String, int> result = <String, int>{};
    for (final VoiceReplayBenchmarkRow row in rows) {
      result.update(row.classification, (int count) => count + 1,
          ifAbsent: () => 1);
    }
    return result;
  }

  Map<String, Map<String, int>> get totalsByRecording {
    final Map<String, Map<String, int>> result = <String, Map<String, int>>{};
    for (final VoiceReplayBenchmarkRow row in rows) {
      final Map<String, int> counts = result.putIfAbsent(
        row.recordingId,
        () => <String, int>{},
      );
      counts.update(row.classification, (int count) => count + 1,
          ifAbsent: () => 1);
    }
    return result;
  }
}

VoiceReplayBenchmark loadVoiceReplayBenchmark(String source) {
  final Map<String, Object?> root = jsonDecode(source) as Map<String, Object?>;
  final List<VoiceReplayBenchmarkRow> rows = <VoiceReplayBenchmarkRow>[];
  final Set<String> ids = <String>{};

  for (final Object? rawRecording in root['recordings']! as List<Object?>) {
    final Map<String, Object?> recording =
        rawRecording! as Map<String, Object?>;
    final String recordingId = recording['id']! as String;
    final List<Map<String, Object?>> expectedMaps =
        (recording['events']! as List<Object?>).cast<Map<String, Object?>>();
    final List<Map<String, Object?>> falsePositiveMaps =
        (recording['falsePositives']! as List<Object?>)
            .cast<Map<String, Object?>>();

    final List<ExpectedVoiceUtterance> expected = expectedMaps
        .map((Map<String, Object?> event) => ExpectedVoiceUtterance(
              id: event['id']! as String,
              phrase: event['expectedPhrase']! as String,
              screen: event['expectedScreen']! as String,
              validForScreen: event['validForScreen'] as bool? ?? true,
            ))
        .toList();
    final List<VoiceReplayObservation> observations = <VoiceReplayObservation>[
      ...expectedMaps.map(_observationFromMap),
      ...falsePositiveMaps.map(_observationFromMap),
    ];
    final VoiceReplayScore score = scoreVoiceReplay(
      expected: expected,
      observations: observations,
    );

    for (var index = 0; index < score.utterances.length; index++) {
      final Map<String, Object?> event = expectedMaps[index];
      final String classification = score.utterances[index].outcome.name;
      _addRow(
        rows: rows,
        ids: ids,
        recordingId: recordingId,
        event: event,
        classification: classification,
      );
    }
    for (final Map<String, Object?> event in falsePositiveMaps) {
      _addRow(
        rows: rows,
        ids: ids,
        recordingId: recordingId,
        event: event,
        classification: 'falsePositive',
      );
    }
  }

  return VoiceReplayBenchmark(List<VoiceReplayBenchmarkRow>.unmodifiable(rows));
}

VoiceReplayObservation _observationFromMap(Map<String, Object?> event) {
  final String parserDecision = event['parserDecision']! as String;
  return VoiceReplayObservation(
    id: event['id']! as String,
    expectedId: event['expectedPhrase'] == null ? null : event['id']! as String,
    screen: event['expectedScreen']! as String,
    recognizedText: _recognizedText(event),
    voskPartial: event['voskPartial']! as String,
    voskFinal: event['voskFinal']! as String,
    parserAccepted: parserDecision == 'accepted',
    businessAction: event['businessAction']! as bool,
    dropReason: event['dropReason'] as String?,
  );
}

String _recognizedText(Map<String, Object?> event) {
  final String finalText = event['voskFinal']! as String;
  return finalText.isNotEmpty ? finalText : event['voskPartial']! as String;
}

void _addRow({
  required List<VoiceReplayBenchmarkRow> rows,
  required Set<String> ids,
  required String recordingId,
  required Map<String, Object?> event,
  required String classification,
}) {
  final String id = event['id']! as String;
  if (!ids.add(id)) throw FormatException('Duplicate benchmark ID: $id');
  final String declared = event['classification']! as String;
  if (declared != classification) {
    throw FormatException(
      '$id declares $declared but scorer returned $classification',
    );
  }
  rows.add(VoiceReplayBenchmarkRow(
    id: id,
    recordingId: recordingId,
    expectedPhrase: event['expectedPhrase'] as String?,
    expectedScreen: event['expectedScreen']! as String,
    voskPartial: event['voskPartial']! as String,
    voskFinal: event['voskFinal']! as String,
    parserDecision: event['parserDecision']! as String,
    dropReason: event['dropReason'] as String?,
    businessAction: event['businessAction']! as bool,
    classification: classification,
    utteranceId: event['utteranceId'] as int?,
  ));
}

void validateVoiceReplayBenchmarkLogs(
  VoiceReplayBenchmark benchmark,
  Map<String, Iterable<String>> logs,
) {
  for (final MapEntry<String, Iterable<String>> entry in logs.entries) {
    final List<VoiceReplayLogEvent> events = parseVoiceReplayLog(entry.value);
    final List<VoiceReplayLogEvent> terminalTimeouts = events
        .where((event) =>
            event.kind == 'replayFailure' && event.dropReason == 'timeout')
        .toList();
    if (terminalTimeouts.isNotEmpty) {
      final String details = terminalTimeouts
          .map((event) =>
              'utteranceId=${event.utteranceId ?? 0} stage=${event.nativeStage ?? event.operation ?? 'unknown'}')
          .join(', ');
      throw StateError('${entry.key}: terminal replay timeout: $details');
    }
    for (final VoiceReplayBenchmarkRow row
        in benchmark.rows.where((row) => row.recordingId == entry.key)) {
      final int? utteranceId = row.utteranceId;
      if (utteranceId == null) continue;
      final List<VoiceReplayLogEvent> utteranceEvents =
          events.where((event) => event.utteranceId == utteranceId).toList();
      if (utteranceEvents.isEmpty) {
        throw StateError('${row.id}: utteranceId=$utteranceId not found');
      }
      if (row.voskPartial.isNotEmpty &&
          !utteranceEvents.any((event) =>
              event.kind == 'voiceCommand' &&
              event.parserDecision == 'partial' &&
              event.text == row.voskPartial)) {
        throw StateError(
          '${row.id}: partial "${row.voskPartial}" not found for '
          'utteranceId=$utteranceId',
        );
      }
      if (row.voskFinal.isNotEmpty &&
          !utteranceEvents.any((event) =>
              event.kind == 'voiceCommand' &&
              (event.parserDecision == 'endpointResult' ||
                  event.parserDecision == 'streamFinal') &&
              event.text == row.voskFinal)) {
        throw StateError(
          '${row.id}: final "${row.voskFinal}" not found for '
          'utteranceId=$utteranceId',
        );
      }
      if (row.parserDecision == 'rejected' &&
          !utteranceEvents.any((event) =>
              event.kind == 'replayDecision' &&
              event.parserDecision == 'rejected' &&
              event.dropReason == row.dropReason)) {
        throw StateError(
          '${row.id}: rejection "${row.dropReason}" not found for '
          'utteranceId=$utteranceId',
        );
      }
    }
  }
}

String renderVoiceReplayBenchmark(VoiceReplayBenchmark benchmark) {
  final StringBuffer output = StringBuffer()
    ..writeln(
        '| Recording | Expected | Screen | Partial | Final | Decision | Drop | Action | Classification |')
    ..writeln('|---|---|---|---|---|---|---|---:|---|');
  for (final VoiceReplayBenchmarkRow row in benchmark.rows) {
    output.writeln('| ${row.recordingId} | ${row.expectedPhrase ?? '-'} | '
        '${row.expectedScreen} | ${row.voskPartial} | ${row.voskFinal} | '
        '${row.parserDecision} | ${row.dropReason ?? '-'} | '
        '${row.businessAction ? 1 : 0} | ${row.classification} |');
  }
  return output.toString();
}
