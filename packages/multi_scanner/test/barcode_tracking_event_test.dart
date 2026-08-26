import 'package:flutter_test/flutter_test.dart';
import 'package:multi_scanner/multi_scanner.dart';

void main() {
  Map<String, Object> event({String phase = 'candidate'}) => <String, Object>{
    'contractVersion': 1,
    'sequence': 2,
    'candidateId': 3,
    'capturedAtElapsedRealtimeNanos': 4,
    'detectedAtElapsedRealtimeNanos': 5,
    'phase': phase,
    'frameWidth': 1600,
    'frameHeight': 1200,
    'rotationDegrees': 0,
    'mirrored': false,
    'left': 0.2,
    'top': 0.3,
    'right': 0.6,
    'bottom': 0.7,
  };

  test('parses normalized tracking event', () {
    final BarcodeTrackingEvent? value = BarcodeTrackingEvent.tryParse(event());

    expect(value, isNotNull);
    expect(value!.phase, BarcodeTrackingPhase.candidate);
    expect(value.centerX, closeTo(0.4, 0.0001));
    expect(value.centerY, closeTo(0.5, 0.0001));
  });

  test('rejects unknown phase and invalid bounds', () {
    expect(BarcodeTrackingEvent.tryParse(event(phase: 'unknown')), isNull);
    expect(
      BarcodeTrackingEvent.tryParse(<String, Object>{...event(), 'right': 1.2}),
      isNull,
    );
  });
}
