import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vosk_flutter_service/vosk_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('recognizer task lanes keep stable MethodChannel values', () {
    expect(RecognizerTaskLane.standard.wireName, 'default');
    expect(RecognizerTaskLane.command.wireName, 'command');
    expect(RecognizerTaskLane.freeText.wireName, 'freeText');
  });

  test('recognizer operations carry unique operation IDs', () async {
    const channel = MethodChannel('vosk-operation-id-test');
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (final call) async {
          calls.add(call);
          return call.method == 'recognizer.acceptWaveForm' ? false : null;
        });
    final recognizer = Recognizer(
      id: 7,
      model: Model('/model', channel),
      sampleRate: 16000,
      channel: channel,
    );

    await recognizer.reset();
    await recognizer.acceptWaveformBytes(
      Uint8List(4),
      maximumQueueWait: const Duration(milliseconds: 250),
    );

    final resetArgs = calls[0].arguments as Map;
    final acceptArgs = calls[1].arguments as Map;
    expect(resetArgs['recognizerId'], 7);
    expect(resetArgs['operationId'], isNotEmpty);
    expect(acceptArgs['operationId'], isNot(resetArgs['operationId']));
    expect(acceptArgs['maximumQueueWaitMs'], 250);
  });
}
