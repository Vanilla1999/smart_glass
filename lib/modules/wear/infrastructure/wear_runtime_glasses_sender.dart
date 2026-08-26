import 'dart:async';

import 'package:smart_glasses/modules/wear/presentation/glasses/wear_glasses_bridge.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_projection.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_dynamic_voice_items.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_core_slices.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_presentation_slice.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_store.dart';

class WearRuntimeGlassesSender {
  WearRuntimeGlassesSender({
    required WearRuntimeStore store,
    WearGlassesBridge? bridge,
    void Function(Object error, StackTrace stackTrace)? onError,
  })  : _store = store,
        _bridge = bridge ?? wearGlassesBridge,
        _onError = onError;

  final WearRuntimeStore _store;
  final WearGlassesBridge _bridge;
  final void Function(Object, StackTrace)? _onError;
  StreamSubscription<WearRuntimeState>? _subscription;
  Future<void> _queue = Future<void>.value();
  Future<void> _hintRefreshQueue = Future<void>.value();
  WearRuntimeVersion? _acceptedVersion;
  WearGlassesEnvelope? _latest;
  bool _visible = false;
  bool _disposed = false;

  void start() {
    if (_subscription != null || _disposed) return;
    _subscription = _store.states.listen(_accept);
    _accept(_store.state);
  }

  void _accept(WearRuntimeState state) {
    final navigation = state.payloadAs<WearAggregatePayload>().navigation;
    final screen = navigation.logicalScreen;
    final int listRevision =
        selectWearDynamicVoiceItems(state, screen).revision;
    final WearGlassesEnvelope envelope = WearRuntimeProjection.projectGlasses(
      state,
      onVoiceHintsPrepared: () {
        if (_disposed) return;
        final WearRuntimeState current = _store.state;
        final currentNavigation =
            current.payloadAs<WearAggregatePayload>().navigation;
        final currentScreen = currentNavigation.logicalScreen;
        if (current.sessionEpoch != state.sessionEpoch ||
            currentScreen != screen ||
            selectWearDynamicVoiceItems(current, currentScreen).revision !=
                listRevision) {
          return;
        }
        _hintRefreshQueue = _hintRefreshQueue.then((_) async {
          await _store.dispatch(WearVoiceHintsPrepared(
            sessionEpoch: current.sessionEpoch,
            expectedScreen: currentScreen,
          ));
        });
      },
    );
    final WearRuntimeVersion? accepted = _acceptedVersion;
    if (accepted != null && envelope.version.compareTo(accepted) <= 0) return;
    _acceptedVersion = envelope.version;
    _latest = envelope;
    _enqueue(envelope, reconnect: false);
  }

  Future<void> reconnect() {
    final WearRuntimeState state = _store.state;
    final WearGlassesEnvelope envelope =
        WearRuntimeProjection.projectGlasses(state);
    _acceptedVersion = envelope.version;
    _latest = envelope;
    return _enqueue(envelope, reconnect: true);
  }

  Future<void> _enqueue(
    WearGlassesEnvelope envelope, {
    required bool reconnect,
  }) {
    final Future<void> operation = _queue.then((_) async {
      if (_disposed || (!reconnect && !identical(_latest, envelope))) {
        return;
      }
      try {
        if (_visible && !reconnect) {
          await _bridge.updateEnvelope(envelope);
        } else {
          await _bridge.showEnvelope(envelope);
        }
        _visible = true;
      } catch (error, stackTrace) {
        _visible = false;
        _onError?.call(error, stackTrace);
      }
    });
    _queue = operation.catchError((Object error, StackTrace stackTrace) {
      _onError?.call(error, stackTrace);
    });
    return operation;
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _subscription?.cancel();
    await _hintRefreshQueue;
    await _queue;
    try {
      await _bridge.hide();
    } catch (error, stackTrace) {
      _onError?.call(error, stackTrace);
    }
  }
}
