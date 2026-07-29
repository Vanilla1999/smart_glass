import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:patrol/patrol.dart';
import 'package:smart_glasses/core/voice/native_voice_capture.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_typing/audio_stream_service.dart';

void main() {
  patrolTest('UAC4 streams sustained PCM and restarts without reboot', ($) async {
    final AudioStreamService audio = AudioStreamService();
    final List<NativeVoiceStateEvent> failures = <NativeVoiceStateEvent>[];
    var cycle = 0;
    var chunks = 0;
    Completer<void> streaming = Completer<void>();

    final StreamSubscription<NativeVoiceStateEvent> states =
        NativeVoiceCapture.instance.stateEvents.listen((event) {
      if (event.state == NativeVoiceCaptureState.streaming &&
          !streaming.isCompleted) {
        streaming.complete();
      }
      if (event.state == NativeVoiceCaptureState.error ||
          event.state == NativeVoiceCaptureState.terminalAbandoned ||
          event.state == NativeVoiceCaptureState.unsupportedFirmware) {
        failures.add(event);
      }
    });

    void onPcm(Uint8List bytes) {
      expect(bytes.lengthInBytes, greaterThanOrEqualTo(2));
      expect(bytes.lengthInBytes.isEven, isTrue);
      chunks++;
    }

    expect(await audio.requestPermission(), isTrue);
    try {
      for (cycle = 1; cycle <= 2; cycle++) {
        chunks = 0;
        streaming = Completer<void>();
        audio.addDataCallback(onPcm);

        await audio.start();
        await streaming.future.timeout(
          const Duration(seconds: 5),
          onTimeout: () => throw TestFailure(
            'Capture cycle $cycle did not reach streaming state.',
          ),
        );
        await Future<void>.delayed(const Duration(seconds: 8));
        final Map<String, Object?> diagnostics =
            await NativeVoiceCapture.instance.getDiagnostics();
        print('Capture cycle $cycle native diagnostics: $diagnostics');

        expect(
          failures,
          isEmpty,
          reason: 'Capture cycle $cycle emitted native error states: '
              '${failures.map((event) => event.errorCode).toList()}',
        );
        expect(
          chunks,
          greaterThanOrEqualTo(20),
          reason: 'Capture cycle $cycle was not continuous for eight seconds.',
        );
        final List<Object?> inputChannels =
            (diagnostics['inputChannels'] as List<Object?>?) ?? <Object?>[];
        final bool hasRawInput = inputChannels.whereType<Map>().any(
              (channel) => (channel['peak'] as num?)?.toDouble() != 0.0,
            );
        expect(
          hasRawInput,
          isTrue,
          reason: 'Capture cycle $cycle received exact-zero raw UAC4 input. '
              'Native diagnostics: $diagnostics',
        );

        await audio.stop();
        expect(NativeVoiceCapture.instance.isCapturing, isFalse);
      }
    } finally {
      await audio.dispose();
      await states.cancel();
    }
  });
}
