import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_glasses/modules/wear/application/ports/wear_glasses_output.dart';
import 'package:smart_glasses/modules/wear/application/ports/wear_navigation_output.dart';
import 'package:smart_glasses/modules/wear/application/wear_flow_controller.dart';
import 'package:smart_glasses/modules/wear/application/wear_navigation_entry.dart';
import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/application/wear_ui_lifecycle.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/wear_voice_command_admission.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/wear_voice_command_event.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/wear_voice_control_service.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_typing/audio_stream_service.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_typing/segmented_recognition_result.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_typing/speech_recognition_service.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_typing/speech_segmenter.dart';
import 'package:smart_glasses/modules/wear/presentation/glasses/wear_glasses_payload.dart';

import 'support/replay_voice_capture.dart';

void main() {
  test('replayed PCM performs one ordered production business action',
      () async {
    final List<String> trace = <String>[];
    final ReplayVoiceCapture capture = ReplayVoiceCapture();
    final _EndpointRecognizer recognizer = _EndpointRecognizer(trace);
    final AudioStreamService audio = AudioStreamService(nativeCapture: capture);
    var tracedAdmission = false;
    audio.addPcmCallback((_, __) {
      if (!tracedAdmission) trace.add('pcm_admitted');
      tracedAdmission = true;
      return true;
    });
    final SpeechRecognitionService speech = SpeechRecognitionService(
      audioStreamService: audio,
      commandGrammar: const <String>['доступность', '[unk]'],
      speechSegmenter: SpeechSegmenter(calibrationDuration: Duration.zero),
      recognizerFactory: (RecognitionLane lane, List<String> grammar) async {
        return recognizer;
      },
    );
    final WearVoiceControlService control = WearVoiceControlService(
      speechRecognitionService: speech,
    );
    final _TraceNavigationOutput navigation = _TraceNavigationOutput(trace);
    final WearFlowController flow = WearFlowController(
      glassesOutput: _NoopGlassesOutput(),
      navigationOutput: navigation,
    );
    flow.setUiLifecycle(WearUiLifecycle.active);
    flow.enterScreen(WearScreenId.menu);
    final StreamSubscription<WearVoiceCommandEvent> subscription =
        control.commandEventStream.listen((event) async {
      trace.add('command_emitted');
      if (!isCurrentWearVoiceCommandEvent(
        event,
        screen: flow.state.screen,
        captureEpoch: speech.captureEpoch,
        routeRevision: speech.routeRevision,
        grammarRevision: speech.grammarRevision,
      )) {
        trace.add('command_rejected');
        return;
      }
      trace.add('command_accepted');
      await flow.handleVoiceCommand(event.command);
      trace.add('command_handled');
    });

    try {
      await speech.prepare();
      await speech.startListening();

      // Native capture publishes 1024-byte mono packets, not VAD-sized frames.
      trace.add('replay_started');
      await capture.replay(List<Uint8List>.generate(
        12,
        (_) => _pcmPacket(12000),
      ));
      await speech.waitForProcessing();
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(audio.chunksReceived, 12);
      expect(capture.acknowledgements, everyElement(isTrue));
      expect(recognizer.accepted, hasLength(4));
      expect(navigation.goToCalls,
          <WearScreenId>[WearScreenId.availabilityInteraction]);
      expect(trace, <String>[
        'replay_started',
        'pcm_admitted',
        'recognizer_accepted',
        'endpoint_result',
        'command_emitted',
        'command_accepted',
        'business_action',
        'command_handled',
      ]);
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
      expect(capture.isCapturing, isFalse);
      await expectLater(capture.emit(_pcmFrame(500)), throwsStateError);
    } finally {
      await audio.stop();
    }
  });

  test('WAV replay reader splits PCM16 mono at 20 ms boundaries', () async {
    final Directory directory = await Directory.systemTemp.createTemp('voice');
    final File file = File('${directory.path}/fixture.wav');
    final Uint8List pcm = Uint8List(1984);
    await file.writeAsBytes(_mono16kWav(pcm));
    addTearDown(() => directory.delete(recursive: true));

    final List<Uint8List> packets =
        await ReplayVoiceCapture.readMono16kWav(file);

    expect(packets.map((Uint8List packet) => packet.lengthInBytes),
        <int>[1024, 960]);
  });

  test('WAV replay reader rejects a file without a format chunk', () async {
    final Directory directory = await Directory.systemTemp.createTemp('voice');
    final File file = File('${directory.path}/missing_fmt.wav');
    await file.writeAsBytes(_dataOnlyWav(Uint8List(1024)));
    addTearDown(() => directory.delete(recursive: true));

    await expectLater(
      ReplayVoiceCapture.readMono16kWav(file),
      throwsFormatException,
    );
  });
}

Uint8List _pcmFrame(int sample) {
  final Int16List samples = Int16List(320);
  samples.fillRange(0, samples.length, sample);
  return samples.buffer.asUint8List();
}

Uint8List _pcmPacket(int sample) {
  final Int16List samples = Int16List(512);
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

Uint8List _dataOnlyWav(Uint8List pcm) {
  final ByteData header = ByteData(20)
    ..setUint32(0, 0x52494646, Endian.big)
    ..setUint32(4, 12 + pcm.lengthInBytes, Endian.little)
    ..setUint32(8, 0x57415645, Endian.big)
    ..setUint32(12, 0x64617461, Endian.big)
    ..setUint32(16, pcm.lengthInBytes, Endian.little);
  return Uint8List.fromList(<int>[...header.buffer.asUint8List(), ...pcm]);
}

class _EndpointRecognizer implements VoiceRecognizer {
  _EndpointRecognizer(this.trace);

  final List<String> trace;
  final List<Uint8List> accepted = <Uint8List>[];

  @override
  Future<bool> acceptWaveformBytes(Uint8List bytes) async {
    accepted.add(Uint8List.fromList(bytes));
    if (accepted.length == 1) {
      trace.add('recognizer_accepted');
      return true;
    }
    return false;
  }

  @override
  Future<void> dispose() async {}

  @override
  Future<String> getFinalResult() async => jsonEncode(<String, String>{});

  @override
  Future<String> getPartialResult() async => jsonEncode(<String, String>{});

  @override
  Future<String> getResult() async {
    trace.add('endpoint_result');
    return jsonEncode(<String, String>{'text': 'доступность'});
  }

  @override
  Future<void> reset() async {}

  @override
  Future<void> setGrammar(List<String> grammar) async {}
}

class _TraceNavigationOutput implements WearNavigationOutput {
  _TraceNavigationOutput(this.trace);

  final List<String> trace;
  final List<WearScreenId> goToCalls = <WearScreenId>[];

  @override
  Future<void> goTo(WearScreenId screen, {Object? extra}) async {
    trace.add('business_action');
    goToCalls.add(screen);
  }

  @override
  Future<void> back() async {}

  @override
  Future<void> home() async {}

  @override
  Future<void> replace(WearScreenId screen, {Object? extra}) async {}

  @override
  Future<void> synchronize(List<WearNavigationEntry> history) async {}
}

class _NoopGlassesOutput implements WearGlassesOutput {
  @override
  Future<void> send(WearGlassesPayload payload) async {}
}
