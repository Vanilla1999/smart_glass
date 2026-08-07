import 'package:flutter_test/flutter_test.dart';
import 'package:vosk_flutter_service/vosk_flutter.dart';

void main() {
  test('recognizer task lanes keep stable MethodChannel values', () {
    expect(RecognizerTaskLane.standard.wireName, 'default');
    expect(RecognizerTaskLane.command.wireName, 'command');
    expect(RecognizerTaskLane.freeText.wireName, 'freeText');
  });
}
