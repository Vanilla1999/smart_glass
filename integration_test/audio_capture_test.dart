import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_typing/audio_stream_service.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Wear microphone receives non-silent PCM16 audio', (
    WidgetTester tester,
  ) async {
    final AudioStreamService audio = AudioStreamService();
    final Completer<void> receivedAudio = Completer<void>();
    var chunks = 0;

    audio.addDataCallback((Uint8List bytes) {
      chunks++;
      if (_containsNonSilentPcm16(bytes) && !receivedAudio.isCompleted) {
        receivedAudio.complete();
      }
    });

    expect(await audio.requestPermission(), isTrue);
    await audio.start();
    print('[AudioCaptureTest] Speak near the microphone within 12 seconds.');

    try {
      await Future.any<void>(<Future<void>>[
        receivedAudio.future,
        Future<void>.delayed(const Duration(seconds: 12)),
      ]);
      expect(
        receivedAudio.isCompleted,
        isTrue,
        reason: 'Received $chunks PCM chunks, but every PCM16 sample was zero.',
      );
    } finally {
      await audio.dispose();
    }
  });
}

bool _containsNonSilentPcm16(Uint8List bytes) {
  for (var index = 0; index + 1 < bytes.lengthInBytes; index += 2) {
    if (bytes[index] != 0 || bytes[index + 1] != 0) return true;
  }
  return false;
}
