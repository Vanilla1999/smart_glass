import 'dart:isolate';

import 'package:smart_glasses/modules/wear/domain/service/voice_command/voice_hint_generator.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/voice_list_matcher.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/voice_utterance_coordinator.dart';

typedef VoiceHintIndexBuilder = Future<VoiceHintSet> Function(
  VoiceDynamicItemsSnapshot snapshot,
  Set<String> reservedPhrases,
);

class VoiceHintIndexCache {
  static const int synchronousItemLimit = 32;

  VoiceHintIndexCache({
    this.maxEntries = 32,
    VoiceHintIndexBuilder? builder,
  }) : _builder = builder ?? _buildInIsolate;

  final int maxEntries;
  final VoiceHintIndexBuilder _builder;
  final Map<String, VoiceHintSet> _ready = <String, VoiceHintSet>{};
  final Map<String, Future<VoiceHintSet>> _pending =
      <String, Future<VoiceHintSet>>{};

  VoiceHintSet? getIfReady({
    required VoiceDynamicItemsSnapshot snapshot,
    String screen = '',
    Set<String> reservedPhrases = const <String>{},
  }) {
    return _ready[_key(screen, snapshot, reservedPhrases)];
  }

  Future<VoiceHintSet> prepare({
    required VoiceDynamicItemsSnapshot snapshot,
    String screen = '',
    Set<String> reservedPhrases = const <String>{},
  }) {
    final String key = _key(screen, snapshot, reservedPhrases);
    final VoiceHintSet? ready = _ready[key];
    if (ready != null) return Future<VoiceHintSet>.value(ready);
    final Future<VoiceHintSet>? pending = _pending[key];
    if (pending != null) return pending;

    final Future<VoiceHintSet> future = _builder(
      snapshot,
      Set<String>.unmodifiable(reservedPhrases),
    ).then((VoiceHintSet generated) {
      _ready[key] = generated;
      while (_ready.length > maxEntries) {
        _ready.remove(_ready.keys.first);
      }
      return generated;
    }, onError: (Object error, StackTrace stackTrace) {
      Error.throwWithStackTrace(error, stackTrace);
    }).whenComplete(() {
      _pending.remove(key);
    });
    _pending[key] = future;
    return future;
  }

  Future<VoiceHintSet> whenReady({
    required VoiceDynamicItemsSnapshot snapshot,
    String screen = '',
    Set<String> reservedPhrases = const <String>{},
  }) {
    return prepare(
      snapshot: snapshot,
      screen: screen,
      reservedPhrases: reservedPhrases,
    );
  }

  VoiceHintSet prepareSmallSynchronously({
    required VoiceDynamicItemsSnapshot snapshot,
    String screen = '',
    Set<String> reservedPhrases = const <String>{},
  }) {
    if (snapshot.items.length > synchronousItemLimit) {
      throw ArgumentError.value(
        snapshot.items.length,
        'snapshot.items.length',
        'Synchronous hint generation is limited to $synchronousItemLimit items',
      );
    }
    final VoiceHintSet? ready = getIfReady(
      snapshot: snapshot,
      screen: screen,
      reservedPhrases: reservedPhrases,
    );
    if (ready != null) return ready;
    final VoiceHintSet generated = VoiceHintGenerator.generate(
      snapshot,
      reservedPhrases: reservedPhrases,
      excludedWords: snapshot.excludedWords,
    );
    store(
      snapshot: snapshot,
      hints: generated,
      screen: screen,
      reservedPhrases: reservedPhrases,
    );
    return generated;
  }

  void store({
    required VoiceDynamicItemsSnapshot snapshot,
    required VoiceHintSet hints,
    String screen = '',
    Set<String> reservedPhrases = const <String>{},
  }) {
    final String key = _key(screen, snapshot, reservedPhrases);
    _ready[key] = hints;
    while (_ready.length > maxEntries) {
      _ready.remove(_ready.keys.first);
    }
  }

  void clear() {
    _ready.clear();
    _pending.clear();
  }

  static Future<VoiceHintSet> _buildInIsolate(
    VoiceDynamicItemsSnapshot snapshot,
    Set<String> reservedPhrases,
  ) {
    return Isolate.run(
      () => VoiceHintGenerator.generate(
        snapshot,
        reservedPhrases: reservedPhrases,
        excludedWords: snapshot.excludedWords,
      ),
    );
  }

  static String _key(
    String screen,
    VoiceDynamicItemsSnapshot snapshot,
    Set<String> reservedPhrases,
  ) {
    final List<String> reserved = reservedPhrases
        .map(VoiceListMatcher.normalize)
        .where((String phrase) => phrase.isNotEmpty)
        .toList(growable: false)
      ..sort();
    final List<String> excluded = snapshot.excludedWords
        .map(VoiceListMatcher.normalize)
        .where((String phrase) => phrase.isNotEmpty)
        .toList(growable: false)
      ..sort();
    return '$screen:${snapshot.revision}:${snapshot.items.length}:'
        '${reserved.join(',')}:${excluded.join(',')}';
  }
}
