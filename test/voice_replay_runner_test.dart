import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/wear_voice_command.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_typing/segmented_recognition_result.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_typing/voice_replay_runner.dart';

void main() {
  test('T17 long acoustic activity does not delay two command endpoints', () {
    final VoiceReplayRunner runner = VoiceReplayRunner(
      recognizer: _MarkerRecognizer(<int, ReplayRecognition>{
        1: const ReplayRecognition(
          kind: RecognitionKind.endpointResult,
          text: 'прямое сканирование',
        ),
        2: const ReplayRecognition(
          kind: RecognitionKind.endpointResult,
          text: 'назад',
        ),
      }),
    );

    final VoiceReplayResult result = runner.run(
      packets: _packets(<int>[1, 0, 2, 0, 0, 0]),
      screen: WearScreenId.availabilityInteraction,
    );

    expect(result.commands, <WearVoiceCommand>[
      WearVoiceCommand.openDirectScan,
      WearVoiceCommand.back,
    ]);
    expect(result.lastUtteranceId, 3);
  });

  test('T18 background PCM without recognized command has no action', () {
    final VoiceReplayResult result = VoiceReplayRunner(
      recognizer: _MarkerRecognizer(<int, ReplayRecognition>{}),
    ).run(
      packets: _packets(<int>[0, 0, 0, 0]),
      screen: WearScreenId.menu,
    );

    expect(result.commands, isEmpty);
  });

  test('T19 unknown endpoint requests free-text replay without action', () {
    final VoiceReplayResult result = VoiceReplayRunner(
      recognizer: _MarkerRecognizer(<int, ReplayRecognition>{
        3: const ReplayRecognition(
          kind: RecognitionKind.endpointResult,
          text: '[unk]',
        ),
      }),
    ).run(
      packets: _packets(<int>[3]),
      screen: WearScreenId.productSelect,
    );

    expect(result.commands, isEmpty);
    expect(result.freeTextReplayCount, 1);
  });

  test('T21 pagination command claims utterance and suppresses free text', () {
    final VoiceReplayResult result = VoiceReplayRunner(
      recognizer: _MarkerRecognizer(<int, ReplayRecognition>{
        4: const ReplayRecognition(
          kind: RecognitionKind.endpointResult,
          text: 'прошлая страница',
        ),
      }),
    ).run(
      packets: _packets(<int>[4]),
      screen: WearScreenId.availabilityProduct,
    );

    expect(result.commands, <WearVoiceCommand>[WearVoiceCommand.previousPage]);
    expect(result.freeTextReplayCount, 0);
  });

  test('T22 product phrase selects free-text replay', () {
    final VoiceReplayResult result = VoiceReplayRunner(
      recognizer: _MarkerRecognizer(<int, ReplayRecognition>{
        5: const ReplayRecognition(
          kind: RecognitionKind.endpointResult,
          text: 'молоко без сахара',
        ),
      }),
    ).run(
      packets: _packets(<int>[5]),
      screen: WearScreenId.productSelect,
    );

    expect(result.commands, isEmpty);
    expect(result.freeTextReplayCount, 1);
  });

  test('T20 common background words are not global commands', () {
    final VoiceReplayResult result = VoiceReplayRunner(
      recognizer: _MarkerRecognizer(<int, ReplayRecognition>{
        6: const ReplayRecognition(
          kind: RecognitionKind.endpointResult,
          text: 'есть',
        ),
      }),
    ).run(
      packets: _packets(<int>[6]),
      screen: WearScreenId.menu,
    );

    expect(result.commands, isEmpty);
  });

  test('T23 command and next product phrase have no global cooldown', () {
    final VoiceReplayResult result = VoiceReplayRunner(
      recognizer: _MarkerRecognizer(<int, ReplayRecognition>{
        1: const ReplayRecognition(
          kind: RecognitionKind.endpointResult,
          text: 'вниз',
        ),
        7: const ReplayRecognition(
          kind: RecognitionKind.endpointResult,
          text: 'кефир два процента',
        ),
      }),
    ).run(
      packets: _packets(<int>[1, 7]),
      screen: WearScreenId.productSelect,
    );

    expect(result.commands, <WearVoiceCommand>[WearVoiceCommand.down]);
    expect(result.freeTextReplayCount, 1);
  });
}

class _MarkerRecognizer implements VoiceReplayRecognizer {
  _MarkerRecognizer(this.events);

  final Map<int, ReplayRecognition> events;
  final Set<int> _emitted = <int>{};

  @override
  Iterable<ReplayRecognition> accept(
    Uint8List pcmFrame, {
    required List<String> grammar,
  }) sync* {
    final int marker = pcmFrame.first;
    final ReplayRecognition? event = events[marker];
    if (event != null && _emitted.add(marker)) yield event;
  }
}

Iterable<Uint8List> _packets(List<int> markers) sync* {
  for (final int marker in markers) {
    final Uint8List frame = Uint8List(640)..fillRange(0, 640, marker);
    // Ensure VAD sees non-zero speech even for marker zero.
    frame[1] = 16;
    yield frame;
  }
}
