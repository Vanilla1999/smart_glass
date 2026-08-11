import 'dart:io';

import 'voice_replay_benchmark.dart';

void main(List<String> arguments) {
  final String path = arguments.isEmpty
      ? 'artifacts/voice_replay/ground_truth_events_2026-08-11.json'
      : arguments.first;
  final VoiceReplayBenchmark benchmark =
      loadVoiceReplayBenchmark(File(path).readAsStringSync());
  if (arguments.length == 2) {
    final Directory logs = Directory(arguments[1]);
    validateVoiceReplayBenchmarkLogs(benchmark, <String, Iterable<String>>{
      for (final String id in <String>[
        '1786374027358',
        '1786374143173',
        '1786374322845',
      ])
        id: File('${logs.path}/flutter_$id.log').readAsLinesSync(),
    });
  }
  stdout.write(renderVoiceReplayBenchmark(benchmark));
  stdout.writeln('Totals: ${benchmark.totals}');
  stdout.writeln('By recording: ${benchmark.totalsByRecording}');
}
