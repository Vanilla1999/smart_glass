import 'package:flutter_test/flutter_test.dart';
import 'package:smart_glasses/modules/wear/services/voice_state.dart';

void main() {
  test('only ready state accepts voice commands', () {
    for (final VoicePhase phase in VoicePhase.values) {
      final VoiceState state = VoiceState(
        phase: phase,
        captureEpoch: 1,
        attempt: 0,
        reason: 'test',
        lastTransitionAt: 1,
      );

      expect(state.acceptsCommands, phase == VoicePhase.ready);
    }
  });
}
