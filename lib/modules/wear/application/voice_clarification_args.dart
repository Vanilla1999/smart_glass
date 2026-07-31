import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/voice_utterance_coordinator.dart';

class VoiceClarificationArgs {
  const VoiceClarificationArgs({
    required this.sourceScreen,
    required this.phrase,
    required this.matches,
    required this.sourceListRevision,
    this.previous,
    this.spokenPhrases = const <String>[],
    this.excludedWords = const <String>{},
  });

  final WearScreenId sourceScreen;
  final String phrase;
  final List<VoiceDynamicItem> matches;
  final int sourceListRevision;
  final VoiceClarificationArgs? previous;
  final List<String> spokenPhrases;
  final Set<String> excludedWords;
}
