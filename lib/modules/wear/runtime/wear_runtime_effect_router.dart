import 'package:smart_glasses/modules/wear/runtime/wear_runtime_store.dart';

abstract interface class WearEffectExecutor {
  bool handles(WearEffect effect);

  Future<WearIntent?> execute(WearEffect effect);
}

/// Mutable wiring registry, not a state owner.
///
/// Executors can only perform an effect and return a typed intent. They never
/// receive a setter or mutable reference to aggregate state.
class WearRuntimeEffectRouter implements WearEffectHandler {
  final List<WearEffectExecutor> _executors = <WearEffectExecutor>[];

  void register(WearEffectExecutor executor) {
    if (_executors.any((WearEffectExecutor item) => identical(item, executor))) {
      return;
    }
    _executors.add(executor);
  }

  @override
  Future<WearIntent?> handle(WearEffect effect) async {
    WearEffectExecutor? matched;
    for (final WearEffectExecutor executor in _executors) {
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
