import 'dart:io';

import 'voice_replay_current_gate.dart';

void main(List<String> arguments) {
  if (arguments.length != 2) {
    stderr.writeln(
      'Usage: dart run tool/voice_replay/run_voice_replay_gate.dart '
      '<recording-manifest.json> <log-directory>',
    );
    exitCode = 64;
    return;
  }
  final VoiceReplayManifest manifest =
      loadVoiceReplayManifest(File(arguments[0]).readAsStringSync());
  final Directory logs = Directory(arguments[1]);
  final VoiceReplayCurrentGateResult result = scoreCurrentVoiceReplay(
    manifest: manifest,
    logs: <String, Iterable<String>>{
      for (final VoiceReplayManifestRecording recording in manifest.recordings)
        recording.id:
            File('${logs.path}/flutter_${recording.id}.log').readAsLinesSync(),
    },
  );
  for (final VoiceReplayCurrentRecordingResult recording in result.recordings) {
    stdout.writeln('${recording.recording.id}:');
    for (final String failure in recording.healthFailures) {
      stdout.writeln('  health: $failure');
    }
    for (final VoiceReplayCurrentRow row in recording.rows) {
      stdout.writeln('  ${row.expected.id}: ${row.outcome.name}');
    }
  }
  enforceCurrentVoiceReplayGate(result);
  stdout.writeln(
    'PASS success=${result.successCount} falseActions=${result.falseActionCount}',
  );
}
