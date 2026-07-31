import 'dart:async';
import 'dart:isolate';

import 'package:smart_glasses/modules/wear/domain/service/voice_command/voice_hint_generator.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/voice_list_matcher.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/voice_utterance_coordinator.dart';

typedef VoiceHintIndexBuilder = Future<VoiceHintSet> Function(
  VoiceDynamicItemsSnapshot snapshot,
  Set<String> reservedPhrases,
  Set<String> excludedWords,
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
  final Map<String, List<Completer<VoiceHintSet>>> _waiters =
      <String, List<Completer<VoiceHintSet>>>{};

  VoiceHintSet? getIfReady({
    required VoiceDynamicItemsSnapshot snapshot,
    String screen = '',
    Set<String> reservedPhrases = const <String>{},
    Set<String> excludedWords = const <String>{},
  }) {
    return _ready[_key(screen, snapshot, reservedPhrases, excludedWords)];
  }

  Future<VoiceHintSet> prepare({
    required VoiceDynamicItemsSnapshot snapshot,
    String screen = '',
    Set<String> reservedPhrases = const <String>{},
    Set<String> excludedWords = const <String>{},
  }) {
    final String key = _key(screen, snapshot, reservedPhrases, excludedWords);
    final VoiceHintSet? ready = _ready[key];
    if (ready != null) return Future<VoiceHintSet>.value(ready);
    final Future<VoiceHintSet>? pending = _pending[key];
    if (pending != null) return pending;

    final Future<VoiceHintSet> future = _builder(
      snapshot,
      Set<String>.unmodifiable(reservedPhrases),
      Set<String>.unmodifiable(excludedWords),
    ).then((VoiceHintSet generated) {
      _ready[key] = generated;
      while (_ready.length > maxEntries) {
        _ready.remove(_ready.keys.first);
      }
      for (final Completer<VoiceHintSet> waiter
          in _waiters.remove(key) ?? const <Completer<VoiceHintSet>>[]) {
        if (!waiter.isCompleted) waiter.complete(generated);
      }
      return generated;
    }, onError: (Object error, StackTrace stackTrace) {
      for (final Completer<VoiceHintSet> waiter
          in _waiters.remove(key) ?? const <Completer<VoiceHintSet>>[]) {
        if (!waiter.isCompleted) waiter.completeError(error, stackTrace);
      }
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
    Set<String> excludedWords = const <String>{},
  }) {
    final String key = _key(screen, snapshot, reservedPhrases, excludedWords);
    final VoiceHintSet? ready = _ready[key];
    if (ready != null) return Future<VoiceHintSet>.value(ready);
    final Future<VoiceHintSet>? pending = _pending[key];
    if (pending != null) return pending;
    final Completer<VoiceHintSet> waiter = Completer<VoiceHintSet>();
    _waiters.putIfAbsent(key, () => <Completer<VoiceHintSet>>[]).add(waiter);
    return waiter.future;
  }

  VoiceHintSet prepareSmallSynchronously({
    required VoiceDynamicItemsSnapshot snapshot,
    String screen = '',
    Set<String> reservedPhrases = const <String>{},
    Set<String> excludedWords = const <String>{},
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
      excludedWords: excludedWords,
    );
    if (ready != null) return ready;
    final VoiceHintSet generated = VoiceHintGenerator.generate(
      snapshot,
      reservedPhrases: reservedPhrases,
      excludedWords: excludedWords,
    );
    store(
      snapshot: snapshot,
      hints: generated,
      screen: screen,
      reservedPhrases: reservedPhrases,
      excludedWords: excludedWords,
    );
    return generated;
  }

  void store({
    required VoiceDynamicItemsSnapshot snapshot,
    required VoiceHintSet hints,
    String screen = '',
    Set<String> reservedPhrases = const <String>{},
    Set<String> excludedWords = const <String>{},
  }) {
    final String key = _key(screen, snapshot, reservedPhrases, excludedWords);
    _ready[key] = hints;
    while (_ready.length > maxEntries) {
      _ready.remove(_ready.keys.first);
    }
  }

  void clear() {
    _ready.clear();
    _pending.clear();
    for (final List<Completer<VoiceHintSet>> waiters in _waiters.values) {
      for (final Completer<VoiceHintSet> waiter in waiters) {
        if (!waiter.isCompleted) {
          waiter.completeError(StateError('Voice hint index cache cleared'));
        }
      }
    }
    _waiters.clear();
  }

  static Future<VoiceHintSet> _buildInIsolate(
    VoiceDynamicItemsSnapshot snapshot,
    Set<String> reservedPhrases,
    Set<String> excludedWords,
  ) {
    return Isolate.run(
      () => VoiceHintGenerator.generate(
        snapshot,
        reservedPhrases: reservedPhrases,
        excludedWords: excludedWords,
      ),
    );
  }

  static String _key(
    String screen,
    VoiceDynamicItemsSnapshot snapshot,
    Set<String> reservedPhrases,
    Set<String> excludedWords,
  ) {
    final List<String> reserved = reservedPhrases
        .map(VoiceListMatcher.normalize)
        .where((String phrase) => phrase.isNotEmpty)
        .toList(growable: false)
      ..sort();
    final List<String> excluded = excludedWords
        .map(VoiceListMatcher.normalize)
        .where((String phrase) => phrase.isNotEmpty)
        .toList(growable: false)
      ..sort();
    return '$screen:${snapshot.revision}:${snapshot.items.length}:'
        '${reserved.join(',')}:${excluded.join(',')}';
  }
}
