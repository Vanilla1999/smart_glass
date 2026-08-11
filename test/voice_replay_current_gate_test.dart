import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tool/voice_replay/voice_replay_current_gate.dart';

void main() {
  test('loads immutable recording metadata and 42 human utterances', () {
    final VoiceReplayManifest manifest = loadVoiceReplayManifest(
      File('artifacts/voice_replay/recording_manifest_2026-08-11.json')
          .readAsStringSync(),
    );

    expect(manifest.recordings, hasLength(3));
    expect(
      manifest.recordings.expand((recording) => recording.utterances),
      hasLength(42),
    );
    expect(
      manifest.recordings.map((recording) => recording.packetCount),
      <int>[3040, 4352, 2848],
    );
    expect(
      manifest.recordings
          .expand((recording) => recording.utterances)
          .where((utterance) => utterance.required),
      hasLength(38),
    );
  });

  test('current run succeeds only with matching completed action', () {
    final VoiceReplayCurrentGateResult result = _score(<String>[
      _recording,
      _event(<String, Object?>{
        'stage': 'command',
        'command': 'back',
        'decision': 'accepted',
        'screen': 'availabilityProduct',
        'utteranceId': 7,
        'traceId': 'trace-7',
        'sourceAudioOffsetMs': 1000,
      }),
      _event(<String, Object?>{
        'stage': 'action',
        'action': 'back',
        'completed': true,
        'screen': 'availabilityProduct',
        'utteranceId': 7,
        'traceId': 'trace-7',
        'sourceAudioOffsetMs': 1000,
      }),
      _summary,
    ]);

    expect(result.successCount, 1);
    expect(result.falseActionCount, 0);
    expect(() => enforceCurrentVoiceReplayGate(result, minimumSuccesses: 1),
        returnsNormally);
  });

  test('dispatcher admission without completed action is a drop', () {
    final VoiceReplayCurrentGateResult result = _score(<String>[
      _recording,
      _event(<String, Object?>{
        'stage': 'command',
        'command': 'back',
        'decision': 'accepted',
        'screen': 'availabilityProduct',
        'utteranceId': 7,
        'traceId': 'trace-7',
        'sourceAudioOffsetMs': 1000,
      }),
      _summary,
    ]);

    expect(result.rows.single.outcome, VoiceReplayCurrentOutcome.postAsrDrop);
    expect(
      () => enforceCurrentVoiceReplayGate(result, minimumSuccesses: 1),
      throwsStateError,
    );
  });

  test('silence cannot pass from PCM acknowledgements alone', () {
    final VoiceReplayCurrentGateResult result =
        _score(<String>[_recording, _summary]);

    expect(result.rows.single.outcome, VoiceReplayCurrentOutcome.asrMiss);
    expect(
      () => enforceCurrentVoiceReplayGate(result, minimumSuccesses: 1),
      throwsStateError,
    );
  });

  test('unmatched completed action is a false action', () {
    final VoiceReplayCurrentGateResult result = _score(<String>[
      _recording,
      _event(<String, Object?>{
        'stage': 'action',
        'action': 'home',
        'completed': true,
        'screen': 'menu',
        'utteranceId': 9,
        'traceId': 'trace-9',
        'sourceAudioOffsetMs': 1100,
      }),
      _summary,
    ]);

    expect(result.falseActionCount, 1);
    expect(
      () => enforceCurrentVoiceReplayGate(result, minimumSuccesses: 0),
      throwsStateError,
    );
  });

  test('wrong screen does not satisfy the annotated utterance', () {
    final VoiceReplayCurrentGateResult result = _score(<String>[
      _recording,
      _event(<String, Object?>{
        'stage': 'command',
        'command': 'back',
        'decision': 'accepted',
        'screen': 'menu',
        'utteranceId': 7,
        'traceId': 'trace-7',
        'sourceAudioOffsetMs': 1000,
      }),
      _summary,
    ]);

    expect(result.rows.single.outcome, VoiceReplayCurrentOutcome.asrMiss);
  });

  test('rejects recording identity and PCM mismatches', () {
    final VoiceReplayCurrentGateResult identity = _score(<String>[
      'VOICE_REPLAY_RECORDING sha256=wrong bytes=100 source=fixture.wav',
      _summary,
    ]);
    final VoiceReplayCurrentGateResult pcm = _score(<String>[
      _recording,
      'VOICE_CONTINUOUS_SUMMARY '
          '${jsonEncode(<String, Object?>{
            'packets': 3,
            'acceptedAcks': 2,
            'rejectedAcks': 1,
          })}',
    ]);
    expect(identity.recordings.single.healthFailures, isNotEmpty);
    expect(pcm.recordings.single.healthFailures, isNotEmpty);
    expect(
      () => enforceCurrentVoiceReplayGate(identity, minimumSuccesses: 0),
      throwsStateError,
    );
  });

  test('raw native timeout fails even after replay was superseded', () {
    final VoiceReplayCurrentGateResult result = _score(<String>[
      _recording,
      '[VOICE_FREE_TEXT_REPLAY_TRACE] stage=decision_rejected '
          'reason=newer_actionable_command utteranceId=6',
      '[VOICE_FREE_TEXT_REPLAY_TRACE] stage=failed operation=accept_wait '
          'utteranceId=6 nativeStage=accept '
          'error=TimeoutException: replay expired',
      _summary,
    ]);

    expect(result.recordings.single.healthFailures, isNotEmpty);
    expect(
      () => enforceCurrentVoiceReplayGate(result, minimumSuccesses: 0),
      throwsStateError,
    );
  });
}

const String _recording =
    'VOICE_REPLAY_RECORDING sha256=abc bytes=100 source=fixture.wav';
const String _summary =
    'VOICE_CONTINUOUS_SUMMARY {"packets":3,"acceptedAcks":3,"rejectedAcks":0}';

String _event(Map<String, Object?> payload) =>
    'VOICE_CONTINUOUS_EVENT ${jsonEncode(payload)}';

VoiceReplayCurrentGateResult _score(List<String> lines) =>
    scoreCurrentVoiceReplay(
      manifest: const VoiceReplayManifest(
        matchToleranceMs: 200,
        recordings: <VoiceReplayManifestRecording>[
          VoiceReplayManifestRecording(
            id: 'fixture',
            file: 'fixture.wav',
            sha256: 'abc',
            byteLength: 100,
            durationMs: 3000,
            packetCount: 3,
            utterances: <VoiceReplayManifestUtterance>[
              VoiceReplayManifestUtterance(
                id: 'back-1',
                offsetMs: 1000,
                phrases: <String>['назад'],
                screen: 'availabilityProduct',
                action: 'back',
                validForScreen: true,
                required: true,
              ),
            ],
          ),
        ],
      ),
      logs: <String, Iterable<String>>{'fixture': lines},
    );
