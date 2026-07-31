import 'package:smart_glasses/modules/wear/domain/service/voice_command/voice_hint_generator.dart';
import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/voice_action_catalog.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/voice_utterance_coordinator.dart';
import 'package:smart_glasses/modules/wear/presentation/glasses/wear_glasses_payload.dart';

class WearGlassesVoiceHints {
  const WearGlassesVoiceHints._();

  static final Map<String, VoiceHintSet> _cache = <String, VoiceHintSet>{};
  static VoiceActionCatalog _actionCatalog = VoiceActionCatalog();

  static void configureActionCatalog(VoiceActionCatalog actionCatalog) {
    _actionCatalog = actionCatalog;
    _cache.clear();
  }

  static List<WearGlassesVoiceHint> forVisibleItems({
    required WearScreenId screen,
    required VoiceDynamicItemsSnapshot snapshot,
    required List<String> visibleItemIds,
    Set<String> excludedWords = const <String>{},
  }) {
    final List<String> sortedExcluded = excludedWords.toList()..sort();
    final List<String> reservedPhrases =
        _actionCatalog.phrasesFor(screen).toList()..sort();
    final String cacheKey =
        '${screen.name}:${snapshot.revision}:${sortedExcluded.join(',')}:'
        '${reservedPhrases.join(',')}';
    final VoiceHintSet hintSet = _cache.putIfAbsent(
      cacheKey,
      () {
        final Stopwatch stopwatch = Stopwatch()..start();
        final VoiceHintSet generated = VoiceHintGenerator.generate(
          snapshot,
          reservedPhrases: reservedPhrases.toSet(),
          excludedWords: excludedWords,
        );
        stopwatch.stop();
        print(
          '[VOICE_DYNAMIC_PERF] phase=glasses_hint_index '
          'screen=${screen.name} items=${snapshot.items.length} '
          'durationMs=${stopwatch.elapsedMilliseconds} '
          'hints=${generated.hintsByItemId.length} '
          'issues=${generated.issues.length}',
        );
        return generated;
      },
    );
    while (_cache.length > 32) {
      _cache.remove(_cache.keys.first);
    }
    for (final VoiceHintValidationIssue issue in hintSet.issues) {
      // ignore: avoid_print
      print(
        '[VOICE_HINT_VALIDATION] revision=${hintSet.revision} '
        'itemId=${issue.itemId} reason=${issue.reason}',
      );
    }
    return visibleItemIds.map((String itemId) {
      final VoiceHint? hint = hintSet.hintsByItemId[itemId];
      if (hint == null || hint.ranges.isEmpty) {
        return WearGlassesVoiceHint(
          itemId: itemId,
          phrase: '',
          start: 0,
          end: 0,
        );
      }
      final VoiceHintRange range = hint.ranges.first;
      return WearGlassesVoiceHint(
        itemId: itemId,
        phrase: hint.phrase,
        start: range.start,
        end: range.end,
      );
    }).toList(growable: false);
  }
}
