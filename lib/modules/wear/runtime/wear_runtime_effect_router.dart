import 'dart:collection';

import 'package:smart_glasses/modules/wear/runtime/wear_runtime_store.dart';

abstract interface class WearEffectExecutor {
  String get registrationKey;

  bool handles(WearEffect effect);

  Future<WearIntent?> execute(WearEffect effect);
}

class WearRuntimeEffectRouter implements WearEffectHandler {
  final Map<String, WearEffectExecutor> _executors =
      <String, WearEffectExecutor>{};

  UnmodifiableMapView<String, WearEffectExecutor> get executors =>
      UnmodifiableMapView<String, WearEffectExecutor>(_executors);

  void register(WearEffectExecutor executor) {
    final String key = _validatedKey(executor);
    final WearEffectExecutor? existing = _executors[key];
    if (identical(existing, executor)) return;
    if (existing != null) {
      throw StateError('Effect executor key $key is already registered');
    }
    _executors[key] = executor;
  }

  void unregister(WearEffectExecutor executor) {
    final String key = _validatedKey(executor);
    if (identical(_executors[key], executor)) {
      _executors.remove(key);
    }
  }

  String _validatedKey(WearEffectExecutor executor) {
    final String key = executor.registrationKey.trim();
    if (key.isEmpty || key != executor.registrationKey) {
      throw ArgumentError.value(
        executor.registrationKey,
        'registrationKey',
        'Effect executor key must be non-empty and normalized',
      );
    }
    return key;
  }

  @override
  Future<WearIntent?> handle(WearEffect effect) async {
    WearEffectExecutor? matched;
    for (final WearEffectExecutor executor in _executors.values) {
      if (!executor.handles(effect)) continue;
      if (matched != null) {
        throw StateError(
          'Effect ${effect.runtimeType} has more than one executor',
        );
      }
      matched = executor;
    }
    if (matched == null) {
      throw StateError('No executor registered for ${effect.runtimeType}');
    }
    return matched.execute(effect);
  }
}
