import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tool/voice_replay/voice_replay_benchmark.dart';

void main() {
  late VoiceReplayBenchmark benchmark;

  setUpAll(() {
    benchmark = loadVoiceReplayBenchmark(
      File('artifacts/voice_replay/ground_truth_events_2026-08-11.json')
          .readAsStringSync(),
    );
  });

  test('scores all corrected ground-truth utterances', () {
    expect(
      benchmark.rows.where((VoiceReplayBenchmarkRow row) =>
          row.classification != 'falsePositive'),
      hasLength(42),
    );
    expect(benchmark.totals, <String, int>{
      'success': 35,
      'postAsrDrop': 4,
      'asrMiss': 1,
      'invalidForScreen': 2,
      'falsePositive': 2,
    });
  });

  test('preserves corrected recording counts', () {
    expect(
      benchmark.rows.where((row) => row.recordingId == '1786374027358'),
      hasLength(12),
    );
    expect(
      benchmark.rows.where((row) => row.recordingId == '1786374143173'),
      hasLength(14),
    );
    expect(
      benchmark.rows.where((row) => row.recordingId == '1786374322845'),
      hasLength(18),
    );
  });

  test('requires business action for every success', () {
    expect(
      benchmark.rows.where(
          (row) => row.classification == 'success' && !row.businessAction),
      isEmpty,
    );
  });

  test('keeps known false positives outside ground truth', () {
    final List<VoiceReplayBenchmarkRow> falsePositives = benchmark.rows
        .where((row) => row.classification == 'falsePositive')
        .toList();
    expect(falsePositives, hasLength(2));
    expect(
        falsePositives.map((row) => row.expectedPhrase), everyElement(isNull));
    expect(
        falsePositives.map((row) => row.businessAction), everyElement(isFalse));
  });

  test('rejects a continuous log with a terminal replay timeout', () {
    expect(
      () => validateVoiceReplayBenchmarkLogs(
        benchmark,
        <String, Iterable<String>>{
          '1786374027358': <String>[
            '[VOICE_FREE_TEXT_REPLAY_TRACE] stage=failed '
                'operation=accept_wait utteranceId=22 nativeStage=accept '
                'error=TimeoutException: replay expired',
          ],
        },
      ),
      throwsA(isA<StateError>()),
    );
  });
}
