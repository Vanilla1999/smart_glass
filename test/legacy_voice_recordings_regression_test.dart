import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_glasses/core/voice/native_voice_capture.dart';
import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/wear_voice_command.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/wear_voice_command_admission.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/wear_voice_command_event.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_typing/speech_recognition_service.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_typing/speech_segmenter.dart';

import 'support/replay_voice_capture.dart';

const List<({int startMs, String text})> _muteUtterances =
    <({int startMs, String text})>[
  (startMs: 9840, text: 'вниз'),
  (startMs: 11820, text: 'вниз'),
  (startMs: 12940, text: 'вниз'),
  (startMs: 14320, text: 'вверх'),
  (startMs: 15400, text: 'вверх'),
  (startMs: 16700, text: 'вверх'),
  (startMs: 18000, text: 'печать'),
  (startMs: 19940, text: 'жёлтый'),
  (startMs: 22200, text: 'жёлтый'),
  (startMs: 28360, text: 'назад'),
  (startMs: 29760, text: 'назад'),
  (startMs: 31160, text: 'назад'),
  (startMs: 35900, text: 'доступность'),
  (startMs: 37460, text: 'список'),
  (startMs: 40100, text: 'список'),
  (startMs: 43880, text: 'молочное'),
  (startMs: 46000, text: 'молочное'),
  (startMs: 49820, text: 'коровка'),
  (startMs: 53560, text: 'кореновка'),
  (startMs: 56420, text: 'назад'),
  (startMs: 57820, text: 'назад'),
  (startMs: 59860, text: 'домой'),
  (startMs: 62740, text: 'отмена'),
  (startMs: 64560, text: 'домой'),
  (startMs: 66740, text: 'домой'),
  (startMs: 68080, text: 'назад'),
  (startMs: 72240, text: 'вверх'),
  (startMs: 73700, text: 'вниз'),
];

const List<({int startMs, String text})> _unmuteUtterances =
    <({int startMs, String text})>[
  (startMs: 13840, text: 'вниз'),
  (startMs: 16140, text: 'вниз'),
  (startMs: 17540, text: 'вниз'),
  (startMs: 19320, text: 'вниз'),
  (startMs: 19360, text: 'вверх'),
  (startMs: 21260, text: 'вверх'),
  (startMs: 23260, text: 'вверх'),
  (startMs: 24580, text: 'вверх'),
  (startMs: 26780, text: 'доступность'),
  (startMs: 29660, text: 'список'),
  (startMs: 32100, text: 'список'),
  (startMs: 35040, text: 'список'),
  (startMs: 40060, text: 'список'),
  (startMs: 43080, text: 'вниз'),
  (startMs: 45360, text: 'выбрать'),
  (startMs: 48680, text: 'назад'),
  (startMs: 51480, text: 'назад'),
  (startMs: 55640, text: 'назад'),
  (startMs: 57040, text: 'назад'),
  (startMs: 58640, text: 'в список'),
  (startMs: 63160, text: 'молочная коровка'),
  (startMs: 69060, text: 'коровка'),
  (startMs: 74980, text: 'коровка'),
  (startMs: 76380, text: 'назад'),
  (startMs: 78560, text: 'молочное'),
  (startMs: 83160, text: 'село'),
  (startMs: 85260, text: 'село'),
  (startMs: 87400, text: 'назад'),
];

void main() {
  final String? mutePath = Platform.environment['LEGACY_MUTE_SSP_WAV'];
  final String? unmutePath = Platform.environment['LEGACY_UNMUTE_SSP_WAV'];

  _recordingTest(
    name: 'legacy mute recording preserves transport and VAD timeline',
    path: mutePath,
    missingPathMessage: 'Set LEGACY_MUTE_SSP_WAV to run this fixture.',
    utterances: _muteUtterances,
  );
  _recordingTest(
    name: 'legacy unmute recording preserves transport and VAD timeline',
    path: unmutePath,
    missingPathMessage: 'Set LEGACY_UNMUTE_SSP_WAV to run this fixture.',
    utterances: _unmuteUtterances,
  );

  test('natural endpoints admit all labelled utterances in one speech turn',
      () async {
    for (final List<({int startMs, String text})> labels
        in <List<({int startMs, String text})>>[
      _muteUtterances,
      _unmuteUtterances,
    ]) {
      final WearVoiceEventAdmissionGate gate = WearVoiceEventAdmissionGate();
      var actions = 0;
      for (var index = 0; index < labels.length; index++) {
        final int utteranceId = index + 1;
        final WearVoiceAdmissionDecision decision = await gate.runCommand(
          WearVoiceCommandEvent(
            command: WearVoiceCommand.down,
            traceId: '1:1:$utteranceId',
            recognizedAtMillis: labels[index].startMs,
            asrMillis: 0,
            captureEpoch: 1,
            speechTurnId: 1,
            decoderGeneration: utteranceId,
            commandUtteranceId: utteranceId,
            sourceScreen: WearScreenId.menu,
            routeRevision: 1,
            grammarRevision: 1,
          ),
          context: (
            screen: WearScreenId.menu,
            captureEpoch: 1,
            routeRevision: 1,
            grammarRevision: 1,
            freeTextEpoch: 1,
            listRevision: 1,
          ),
          action: () => actions++,
        );
        expect(decision, WearVoiceAdmissionDecision.accepted);
      }
      expect(actions, labels.length);
    }
  });
}

void _recordingTest({
  required String name,
  required String? path,
  required String missingPathMessage,
  required List<({int startMs, String text})> utterances,
}) {
  test(name, () async {
    final List<Uint8List> packets =
        await ReplayVoiceCapture.readMono16kWav(File(path!));
    final ReplayVoiceCapture capture = ReplayVoiceCapture();
    final PcmFrameAccumulator accumulator =
        PcmFrameAccumulator(frameBytes: 640);
    final SpeechSegmenter segmenter = SpeechSegmenter()..begin(1);
    final Set<int> speechTurnIds = <int>{};
    var frames = 0;
    var starts = 0;
    var silenceEndpoints = 0;
    var maxDurationEndpoints = 0;

    final int leaseId = await capture.start(
      owner: NativeVoiceOwner.wearRecognition,
      onPcm: (NativePcmPacket packet) {
        for (final PcmFramePair frame
            in accumulator.add(packet.bytes, packet.bytes)) {
          frames++;
          final SpeechSegment? segment = segmenter.decide(frame.raw, 1).segment;
          if (segment == null) continue;
          speechTurnIds.add(segment.speechTurnId);
          if (segment.started) starts++;
          if (segment.endpointReason == AcousticEndpointReason.silence) {
            silenceEndpoints++;
          }
          if (segment.endpointReason == AcousticEndpointReason.maxDuration) {
            maxDurationEndpoints++;
          }
        }
        return true;
      },
    );
    try {
      await capture.replay(packets, realTime: false);
    } finally {
      await capture.stop(
        owner: NativeVoiceOwner.wearRecognition,
        leaseId: leaseId,
      );
      await capture.dispose();
    }

    final int pcmBytes = packets.fold<int>(
      0,
      (int total, Uint8List packet) => total + packet.lengthInBytes,
    );
    expect(capture.acknowledgements, everyElement(isTrue));
    expect(
      capture.acknowledgementRecords.map((record) => record.sequence),
      orderedEquals(List<int>.generate(packets.length, (int index) => index)),
    );
    expect(frames, pcmBytes ~/ 640);
    expect(starts, greaterThan(0));
    expect(speechTurnIds, isNotEmpty);
    expect(maxDurationEndpoints, greaterThan(0));
    expect(utterances, hasLength(28));

    // ignore: avoid_print
    print(
      '[LEGACY_VOICE_FIXTURE] path=$path packets=${packets.length} '
      'frames=$frames starts=$starts turns=${speechTurnIds.length} '
      'silenceEndpoints=$silenceEndpoints '
      'maxDurationEndpoints=$maxDurationEndpoints '
      'labelledUtterances=${utterances.length}',
    );
  }, skip: path == null ? missingPathMessage : false);
}
