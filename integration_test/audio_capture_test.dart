import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_typing/audio_stream_service.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Wear microphone provides PCM chunks without speech requirement',
      (
    WidgetTester tester,
  ) async {
    final AudioStreamService audio = AudioStreamService();
    final Completer<void> receivedAudio = Completer<void>();
    var chunks = 0;

    audio.addDataCallback((Uint8List bytes) {
      if (bytes.lengthInBytes < 2) return;
      chunks++;
      if (chunks >= 3 && !receivedAudio.isCompleted) {
        receivedAudio.complete();
      }
    });

    expect(await audio.requestPermission(), isTrue);
    await audio.start();

    try {
      await Future.any<void>(<Future<void>>[
        receivedAudio.future,
        Future<void>.delayed(const Duration(seconds: 2)),
      ]);
      expect(
        receivedAudio.isCompleted,
        isTrue,
        reason:
            'Recorder did not provide three valid PCM chunks in two seconds.',
      );
    } finally {
      await audio.dispose();
    }
  });
}
