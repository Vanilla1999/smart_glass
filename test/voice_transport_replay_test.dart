import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/wear_voice_command.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/wear_voice_control_service.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_typing/audio_stream_service.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_typing/segmented_recognition_result.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_typing/speech_recognition_service.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_typing/speech_segmenter.dart';

import 'support/replay_voice_capture.dart';

void main() {
  test('recorded PCM reaches the production audio and command pipeline',
      () async {
    final ReplayVoiceCapture capture = ReplayVoiceCapture();
    final _PartialRecognizer recognizer = _PartialRecognizer();
    final AudioStreamService audio = AudioStreamService(nativeCapture: capture);
    final SpeechRecognitionService speech = SpeechRecognitionService(
      audioStreamService: audio,
      commandGrammar: const <String>['вверх', '[unk]'],
      speechSegmenter: SpeechSegmenter(calibrationDuration: Duration.zero),
      recognizerFactory: (RecognitionLane lane, List<String> grammar) async {
        return recognizer;
      },
    );
    final WearVoiceControlService control = WearVoiceControlService(
      speechRecognitionService: speech,
    );
    final List<WearVoiceCommand> commands = <WearVoiceCommand>[];
    final StreamSubscription<WearVoiceCommand> subscription =
        control.commandStream.listen(commands.add);

    try {
      await speech.prepare();
      await speech.startListening();

      // Twelve 20 ms voiced packets produce three production 80 ms batches.
      await capture.replay(List<Uint8List>.generate(
        12,
        (_) => _pcmFrame(12000),
      ));
      await speech.waitForProcessing();
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(audio.chunksReceived, 12);
      expect(capture.acknowledgements, everyElement(isTrue));
      expect(recognizer.accepted, hasLength(3));
      expect(commands, <WearVoiceCommand>[WearVoiceCommand.up]);
    } finally {
      await subscription.cancel();
      await control.dispose();
      await speech.dispose();
    }
  });

  test('PCM emitted after stop cannot reach the Dart pipeline', () async {
    final ReplayVoiceCapture capture = ReplayVoiceCapture();
    final AudioStreamService audio = AudioStreamService(nativeCapture: capture);
    final List<Uint8List> received = <Uint8List>[];
    audio.addPcmCallback((Uint8List raw, Uint8List boosted) {
      received.add(boosted);
      return true;
    });

    await audio.start();
    await capture.emit(_pcmFrame(500));
    await audio.stop();

    await expectLater(
      capture.emit(_pcmFrame(500)),
      throwsStateError,
    );
    expect(received, hasLength(1));
    expect(capture.isCapturing, isFalse);
  });

  test('replay reports callback backpressure to the packet source', () async {
    final ReplayVoiceCapture capture = ReplayVoiceCapture();
    final AudioStreamService audio = AudioStreamService(nativeCapture: capture);
    audio.addPcmCallback((Uint8List raw, Uint8List boosted) => false);

    await audio.start();
    try {
      expect(await capture.emit(_pcmFrame(500)), isFalse);
      expect(capture.acknowledgements, <bool>[false]);
    } finally {
      await audio.stop();
    }
  });

  test('WAV replay reader splits PCM16 mono at 20 ms boundaries', () async {
    final Directory directory = await Directory.systemTemp.createTemp('voice');
    final File file = File('${directory.path}/fixture.wav');
    final Uint8List pcm = Uint8List(960);
    await file.writeAsBytes(_mono16kWav(pcm));
    addTearDown(() => directory.delete(recursive: true));

    final List<Uint8List> packets =
        await ReplayVoiceCapture.readMono16kWav(file);

    expect(packets.map((Uint8List packet) => packet.lengthInBytes),
        <int>[640, 320]);
  });
}

Uint8List _pcmFrame(int sample) {
  final Int16List samples = Int16List(320);
  samples.fillRange(0, samples.length, sample);
  return samples.buffer.asUint8List();
}

Uint8List _mono16kWav(Uint8List pcm) {
  final ByteData header = ByteData(44)
    ..setUint32(0, 0x52494646, Endian.big)
    ..setUint32(4, 36 + pcm.lengthInBytes, Endian.little)
    ..setUint32(8, 0x57415645, Endian.big)
    ..setUint32(12, 0x666d7420, Endian.big)
    ..setUint32(16, 16, Endian.little)
    ..setUint16(20, 1, Endian.little)
    ..setUint16(22, 1, Endian.little)
    ..setUint32(24, 16000, Endian.little)
    ..setUint32(28, 32000, Endian.little)
    ..setUint16(32, 2, Endian.little)
    ..setUint16(34, 16, Endian.little)
    ..setUint32(36, 0x64617461, Endian.big)
    ..setUint32(40, pcm.lengthInBytes, Endian.little);
  return Uint8List.fromList(<int>[...header.buffer.asUint8List(), ...pcm]);
}

class _PartialRecognizer implements VoiceRecognizer {
  final List<Uint8List> accepted = <Uint8List>[];

  @override
  Future<bool> acceptWaveformBytes(Uint8List bytes) async {
    accepted.add(Uint8List.fromList(bytes));
    return false;
  }

  @override
  Future<void> dispose() async {}

  @override
  Future<String> getFinalResult() async => jsonEncode(<String, String>{});

  @override
  Future<String> getPartialResult() async =>
      jsonEncode(<String, String>{'partial': 'вверх'});

  @override
  Future<String> getResult() async => jsonEncode(<String, String>{});

  @override
  Future<void> reset() async {}

  @override
  Future<void> setGrammar(List<String> grammar) async {}
}
