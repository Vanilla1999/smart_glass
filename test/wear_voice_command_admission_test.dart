import 'package:flutter_test/flutter_test.dart';
import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/wear_voice_command.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/wear_voice_command_admission.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/wear_voice_command_event.dart';

void main() {
  test('accepts only the current screen and recognition revisions', () {
    final WearVoiceCommandEvent current = _event();

    expect(_isCurrent(current), isTrue);
    expect(_isCurrent(_event(screen: WearScreenId.help)), isFalse);
    expect(_isCurrent(_event(captureEpoch: 2)), isFalse);
    expect(_isCurrent(_event(routeRevision: 2)), isFalse);
    expect(_isCurrent(_event(grammarRevision: 2)), isFalse);
  });
}

bool _isCurrent(WearVoiceCommandEvent event) => isCurrentWearVoiceCommandEvent(
      event,
      screen: WearScreenId.menu,
      captureEpoch: 1,
      routeRevision: 1,
      grammarRevision: 1,
    );

WearVoiceCommandEvent _event({
  WearScreenId screen = WearScreenId.menu,
  int captureEpoch = 1,
  int routeRevision = 1,
  int grammarRevision = 1,
}) {
  return WearVoiceCommandEvent(
    command: WearVoiceCommand.down,
    traceId: 'trace',
    recognizedAtMillis: 1,
    asrMillis: 1,
    captureEpoch: captureEpoch,
    commandUtteranceId: 1,
    sourceScreen: screen,
    routeRevision: routeRevision,
    grammarRevision: grammarRevision,
  );
}
