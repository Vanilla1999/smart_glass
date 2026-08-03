import 'dart:async';

import 'package:smart_glasses/modules/wear/domain/service/voice_command/voice_hint_generator.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/voice_hint_index_cache.dart';
import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/voice_action_catalog.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/voice_utterance_coordinator.dart';
import 'package:smart_glasses/modules/wear/presentation/glasses/wear_glasses_payload.dart';

class WearGlassesVoiceHints {
  const WearGlassesVoiceHints._();

  static VoiceHintIndexCache _indexCache = VoiceHintIndexCache();
  static VoiceActionCatalog _actionCatalog = VoiceActionCatalog();

  static void configureActionCatalog(VoiceActionCatalog actionCatalog) {
    _actionCatalog = actionCatalog;
  }

  static void configureVoiceHintIndexCache(VoiceHintIndexCache indexCache) {
    _indexCache = indexCache;
  }

  static List<WearGlassesVoiceHint> forVisibleItems({
    required WearScreenId screen,
    required VoiceDynamicItemsSnapshot snapshot,
    required List<String> visibleItemIds,
    void Function()? onPrepared,
  }) {
    final List<String> reservedPhrases =
        _actionCatalog.phrasesFor(screen).toList()..sort();
    final Set<String> reserved = reservedPhrases.toSet();
    VoiceHintSet? ready = _indexCache.getIfReady(
      snapshot: snapshot,
      screen: screen.name,
      reservedPhrases: reserved,
    );
    if (ready == null &&
        snapshot.items.length <= VoiceHintIndexCache.synchronousItemLimit) {
      ready = _indexCache.prepareSmallSynchronously(
        snapshot: snapshot,
        screen: screen.name,
        reservedPhrases: reserved,
      );
    }
    if (ready == null) {
      final Stopwatch stopwatch = Stopwatch()..start();
      unawaited(
        _indexCache
            .whenReady(
          snapshot: snapshot,
          screen: screen.name,
          reservedPhrases: reserved,
        )
            .then((VoiceHintSet generated) {
          stopwatch.stop();
          print(
            '[VOICE_DYNAMIC_PERF] phase=glasses_hint_index_ready '
            'screen=${screen.name} items=${snapshot.items.length} '
            'durationMs=${stopwatch.elapsedMilliseconds} '
            'hints=${generated.hintsByItemId.length} '
            'issues=${generated.issues.length}',
          );
          onPrepared?.call();
        }).catchError((Object error, StackTrace stackTrace) {
          print(
            '[VOICE_HINT_INDEX] glasses prepare failed: $error\n$stackTrace',
          );
        }),
      );
      return visibleItemIds
          .map((String itemId) => WearGlassesVoiceHint(
                itemId: itemId,
                phrase: '',
                start: 0,
                end: 0,
              ))
          .toList(growable: false);
    }
    final VoiceHintSet hintSet = ready;
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
