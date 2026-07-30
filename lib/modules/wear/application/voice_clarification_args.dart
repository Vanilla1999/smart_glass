import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/voice_utterance_coordinator.dart';

class VoiceClarificationArgs {
  const VoiceClarificationArgs({
    required this.sourceScreen,
    required this.phrase,
    required this.matches,
    this.previous,
  });

  final WearScreenId sourceScreen;
  final String phrase;
  final List<VoiceDynamicItem> matches;
  final VoiceClarificationArgs? previous;
}
