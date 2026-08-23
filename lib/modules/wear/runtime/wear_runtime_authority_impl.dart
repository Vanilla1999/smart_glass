import 'dart:async';
import 'dart:collection';

import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/domain/auth/model/authenticated_user.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_store.dart';

/// Feature values deliberately remain legacy-owned until MR-S4..MR-S6.
abstract interface class WearFeaturePayload {}

class WearLegacyFeaturePayload implements WearFeaturePayload {
  const WearLegacyFeaturePayload();
}

/// Voice/scanner/connectivity control remains legacy-owned until MR-S3.
abstract interface class WearControlPayload {}

class WearLegacyControlPayload implements WearControlPayload {
  const WearLegacyControlPayload();
}

/// Phone/glasses projection remains legacy-owned until MR-S8.
abstract interface class WearPresentationPayload {}

class WearLegacyPresentationPayload implements WearPresentationPayload {
  const WearLegacyPresentationPayload();
}

class WearSessionSlice {
  const WearSessionSlice.anonymous() : user = null;

  const WearSessionSlice.authorized(AuthenticatedUser value) : user = value;

  final AuthenticatedUser? user;

  bool get isAuthorized => user != null;

  bool sameIdentityAs(WearSessionSlice other) {
    final AuthenticatedUser? left = user;
    final AuthenticatedUser? right = other.user;
    if (left == null || right == null) return left == null && right == null;
    return left.idUser == right.idUser &&
        left.idEmployee == right.idEmployee &&
        left.name == right.name;
  }
}

class WearLifecycleSlice {
  const WearLifecycleSlice({
    required this.runtimeActive,
    required this.phoneUiActive,
    required this.terminal,
  });

  const WearLifecycleSlice.initial()
      : runtimeActive = false,
        phoneUiActive = false,
        terminal = false;

  final bool runtimeActive;
  final bool phoneUiActive;
  final bool terminal;

  WearLifecycleSlice copyWith({
    bool? runtimeActive,
    bool? phoneUiActive,
    bool? terminal,
  }) {
    return WearLifecycleSlice(
      runtimeActive: runtimeActive ?? this.runtimeActive,
      phoneUiActive: phoneUiActive ?? this.phoneUiActive,
      terminal: terminal ?? this.terminal,
    );
  }
}

enum WearPendingNavigationKind { push, replace, pop }

class WearPendingNavigation {
  const WearPendingNavigation({
    required this.requestId,
    required this.screen,
    required this.kind,
  });

  final int requestId;
  final WearScreenId screen;
  final WearPendingNavigationKind kind;
}

class WearNavigationSlice {
  WearNavigationSlice({
    required this.logicalScreen,
    required this.actualPhoneScreen,
    required this.pending,
    required Iterable<WearScreenId> history,
    required this.routeObservationRevision,
    required this.nextRequestId,
  }) : history = UnmodifiableListView<WearScreenId>(
          List<WearScreenId>.of(history),
        );

  factory WearNavigationSlice.initial({
    WearScreenId screen = WearScreenId.main,
  }) {
    return WearNavigationSlice(
      logicalScreen: screen,
      actualPhoneScreen: null,
      pending: null,
      history: <WearScreenId>[screen],
      routeObservationRevision: 0,
      nextRequestId: 0,
    );
  }

  final WearScreenId logicalScreen;
  final WearScreenId? actualPhoneScreen;
  final WearPendingNavigation? pending;
  final UnmodifiableListView<WearScreenId> history;
  final int routeObservationRevision;
  final int nextRequestId;

  WearNavigationSlice request(
    WearScreenId screen, {
    WearPendingNavigationKind kind = WearPendingNavigationKind.push,
  }) {
    final int requestId = nextRequestId + 1;
    final List<WearScreenId> nextHistory = List<WearScreenId>.of(history);
    switch (kind) {
      case WearPendingNavigationKind.push:
        if (nextHistory.isEmpty || nextHistory.last != screen) {
          nextHistory.add(screen);
        }
        break;
      case WearPendingNavigationKind.replace:
        if (screen == WearScreenId.menu) {
          nextHistory
            ..clear()
            ..add(screen);
        } else if (nextHistory.isEmpty) {
          nextHistory.add(screen);
        } else {
          nextHistory[nextHistory.length - 1] = screen;
        }
        break;
      case WearPendingNavigationKind.pop:
        if (nextHistory.length > 1) nextHistory.removeLast();
        if (nextHistory.isEmpty || nextHistory.last != screen) {
          nextHistory.add(screen);
        }
        break;
    }
    return WearNavigationSlice(
      logicalScreen: screen,
      actualPhoneScreen: actualPhoneScreen,
      pending: WearPendingNavigation(
        requestId: requestId,
        screen: screen,
        kind: kind,
      ),
      history: nextHistory,
      routeObservationRevision: routeObservationRevision,
      nextRequestId: requestId,
    );
  }

  WearNavigationSlice observePhoneRoute({
    required WearScreenId screen,
    required int observationRevision,
  }) {
    return WearNavigationSlice(
      logicalScreen: logicalScreen,
      actualPhoneScreen: screen,
      pending: pending,
      history: history,
      routeObservationRevision: observationRevision,
      nextRequestId: nextRequestId,
    );
  }

  WearNavigationSlice acknowledge({
    required WearScreenId screen,
  }) {
    return WearNavigationSlice(
      logicalScreen: logicalScreen,
      actualPhoneScreen: screen,
      pending: null,
      history: history,
      routeObservationRevision: routeObservationRevision,
      nextRequestId: nextRequestId,
    );
  }

  /// Resets the logical stack without reusing observation/request identities.
  ///
  /// Keeping both counters monotonic prevents a late callback from an older
  /// session from colliding with the first route/request of the new session.
  WearNavigationSlice clearForSession(WearScreenId screen) {
    return WearNavigationSlice(
      logicalScreen: screen,
      actualPhoneScreen: null,
      pending: null,
      history: <WearScreenId>[screen],
      routeObservationRevision: routeObservationRevision,
      nextRequestId: nextRequestId,
    );
  }

  WearNavigationSlice terminalized() {
    return WearNavigationSlice(
      logicalScreen: logicalScreen,
      actualPhoneScreen: actualPhoneScreen,
      pending: null,
      history: history,
      routeObservationRevision: routeObservationRevision,
      nextRequestId: nextRequestId,
    );
  }
}

class WearAggregatePayload implements WearRuntimePayload {
  const WearAggregatePayload._({
    required this.session,
    required this.lifecycle,
    required this.navigation,
    required this.features,
    required this.controls,
    required this.presentation,
  });

  factory WearAggregatePayload.initial({
    WearScreenId initialScreen = WearScreenId.main,
  }) {
    return WearAggregatePayload._(
      session: const WearSessionSlice.anonymous(),
      lifecycle: const WearLifecycleSlice.initial(),
      navigation: WearNavigationSlice.initial(screen: initialScreen),
      features: const WearLegacyFeaturePayload(),
      controls: const WearLegacyControlPayload(),
      presentation: const WearLegacyPresentationPayload(),
    );
  }

  final WearSessionSlice session;
  final WearLifecycleSlice lifecycle;
  final WearNavigationSlice navigation;
  final WearFeaturePayload features;
  final WearControlPayload controls;
  final WearPresentationPayload presentation;

  WearAggregatePayload copyWith({
    WearSessionSlice? session,
    WearLifecycleSlice? lifecycle,
    WearNavigationSlice? navigation,
    WearFeaturePayload? features,
    WearControlPayload? controls,
    WearPresentationPayload? presentation,
  }) {
    return WearAggregatePayload._(
      session: session ?? this.session,
      lifecycle: lifecycle ?? this.lifecycle,
      navigation: navigation ?? this.navigation,
      features: features ?? this.features,
      controls: controls ?? this.controls,
      presentation: presentation ?? this.presentation,
    );
  }

  @override
  WearRuntimePayload toTerminalPayload() {
    return copyWith(
      session: const WearSessionSlice.anonymous(),
      lifecycle: const WearLifecycleSlice(
        runtimeActive: false,
        phoneUiActive: false,
        terminal: true,
      ),
      navigation: navigation.terminalized(),
    );
  }
}

class WearSessionAuthorized extends WearIntent {
  const WearSessionAuthorized(this.user);

  final AuthenticatedUser user;
}

class WearSessionCleared extends WearIntent {
  const WearSessionCleared();
}

class WearRuntimeActiveChanged extends WearIntent {
  const WearRuntimeActiveChanged(this.active);

  final bool active;
}

class WearPhoneUiActiveChanged extends WearIntent {
  const WearPhoneUiActiveChanged(this.active);

  final bool active;
}

class WearLogicalNavigationRequested extends WearIntent {
  const WearLogicalNavigationRequested({
    required this.screen,
    this.kind = WearPendingNavigationKind.push,
  });

  final WearScreenId screen;
  final WearPendingNavigationKind kind;
}

class WearPhoneRouteObserved extends WearIntent {
  const WearPhoneRouteObserved({
    required this.sessionEpoch,
    required this.screen,
    required this.observationRevision,
  });

  final int sessionEpoch;
  final WearScreenId screen;
  final int observationRevision;
}

class WearNavigationAcknowledged extends WearIntent {
  const WearNavigationAcknowledged({
    required this.sessionEpoch,
    required this.requestId,
    required this.screen,
  });

  final int sessionEpoch;
  final int requestId;
  final WearScreenId screen;
}

class WearBackRequested extends WearIntent {
  const WearBackRequested();
}

class WearHomeRequested extends WearIntent {
  const WearHomeRequested();
}

class WearRuntimeTerminated extends WearIntent {
  const WearRuntimeTerminated();
}

class WearAggregateReducer implements WearRuntimeReducer {
  const WearAggregateReducer();

  @override
  WearReduction reduce(WearRuntimeState state, WearIntent intent) {
    final WearAggregatePayload payload = state.payloadAs<WearAggregatePayload>();
    if (state.terminal || payload.lifecycle.terminal) {
      return WearReduction.reject(WearDispatchRejectReason.terminal);
    }

    if (intent is WearSessionAuthorized) {
      final WearSessionSlice nextSession =
          WearSessionSlice.authorized(intent.user);
      if (payload.session.isAuthorized) {
        if (payload.session.sameIdentityAs(nextSession)) {
          return WearReduction.accept();
        }
        return WearReduction.reject(WearDispatchRejectReason.busy);
      }
      final WearAggregatePayload nextPayload = payload.copyWith(
        session: nextSession,
        lifecycle: payload.lifecycle.copyWith(runtimeActive: true),
      );
      return WearReduction.accept(
        nextState: state.beginNextEpoch(
          legacy: WearLegacyRuntimeSnapshot(
            logicalScreen: payload.navigation.logicalScreen,
            sourceRevision: state.legacy.sourceRevision + 1,
          ),
          payload: nextPayload,
        ),
      );
    }

    if (intent is WearSessionCleared) {
      if (!payload.session.isAuthorized) return WearReduction.accept();
      final WearAggregatePayload nextPayload = payload.copyWith(
        session: const WearSessionSlice.anonymous(),
        lifecycle: payload.lifecycle.copyWith(runtimeActive: false),
        navigation: payload.navigation.clearForSession(WearScreenId.main),
      );
      return WearReduction.accept(
        nextState: state.beginNextEpoch(
          legacy: WearLegacyRuntimeSnapshot(
            logicalScreen: WearScreenId.main,
            sourceRevision: state.legacy.sourceRevision + 1,
          ),
          payload: nextPayload,
        ),
      );
    }

    if (intent is WearRuntimeActiveChanged) {
      if (payload.lifecycle.runtimeActive == intent.active) {
        return WearReduction.accept();
      }
      if (intent.active && !payload.session.isAuthorized) {
        return WearReduction.reject(WearDispatchRejectReason.unsupported);
      }
      return WearReduction.accept(
        nextState: state.withPayload(
          payload.copyWith(
            lifecycle: payload.lifecycle.copyWith(runtimeActive: intent.active),
          ),
        ),
      );
    }

    if (intent is WearPhoneUiActiveChanged) {
      if (payload.lifecycle.phoneUiActive == intent.active) {
        return WearReduction.accept();
      }
      return WearReduction.accept(
        nextState: state.withPayload(
          payload.copyWith(
            lifecycle: payload.lifecycle.copyWith(phoneUiActive: intent.active),
          ),
        ),
      );
    }

    if (intent is WearLogicalNavigationRequested) {
      final WearPendingNavigation? pending = payload.navigation.pending;
      if (payload.navigation.logicalScreen == intent.screen) {
        if (pending == null) return WearReduction.accept();
        if (pending.screen == intent.screen && pending.kind == intent.kind) {
          return WearReduction.reject(WearDispatchRejectReason.duplicate);
        }
      }
      final WearNavigationSlice navigation = payload.navigation.request(
        intent.screen,
        kind: intent.kind,
      );
      return WearReduction.accept(
        nextState: state
            .withLegacy(
              WearLegacyRuntimeSnapshot(
                logicalScreen: intent.screen,
                sourceRevision: state.legacy.sourceRevision + 1,
              ),
            )
            .withPayload(payload.copyWith(navigation: navigation)),
      );
    }

    if (intent is WearPhoneRouteObserved) {
      if (intent.sessionEpoch != state.sessionEpoch) {
        return WearReduction.reject(WearDispatchRejectReason.staleEpoch);
      }
      if (intent.observationRevision <=
          payload.navigation.routeObservationRevision) {
        return WearReduction.reject(WearDispatchRejectReason.staleOperation);
      }
      return WearReduction.accept(
        nextState: state.withPayload(
          payload.copyWith(
            navigation: payload.navigation.observePhoneRoute(
              screen: intent.screen,
              observationRevision: intent.observationRevision,
            ),
          ),
        ),
      );
    }

    if (intent is WearNavigationAcknowledged) {
      if (intent.sessionEpoch != state.sessionEpoch) {
        return WearReduction.reject(WearDispatchRejectReason.staleEpoch);
      }
      final WearPendingNavigation? pending = payload.navigation.pending;
      if (pending == null ||
          pending.requestId != intent.requestId ||
          pending.screen != intent.screen) {
        return WearReduction.reject(WearDispatchRejectReason.staleOperation);
      }
      return WearReduction.accept(
        nextState: state.withPayload(
          payload.copyWith(
            navigation: payload.navigation.acknowledge(screen: intent.screen),
          ),
        ),
      );
    }

    if (intent is WearBackRequested) {
      final List<WearScreenId> history = payload.navigation.history;
      if (history.length <= 1) {
        return WearReduction.reject(WearDispatchRejectReason.unsupported);
      }
      return reduce(
        state,
        WearLogicalNavigationRequested(
          screen: history[history.length - 2],
          kind: WearPendingNavigationKind.pop,
        ),
      );
    }

    if (intent is WearHomeRequested) {
      return reduce(
        state,
        const WearLogicalNavigationRequested(
          screen: WearScreenId.menu,
          kind: WearPendingNavigationKind.replace,
        ),
      );
    }

    if (intent is WearRuntimeTerminated) {
      final WearAggregatePayload terminalPayload =
          payload.toTerminalPayload() as WearAggregatePayload;
      return WearReduction.accept(
        nextState: state.beginNextEpoch(
          legacy: WearLegacyRuntimeSnapshot(
            logicalScreen: payload.navigation.logicalScreen,
            sourceRevision: state.legacy.sourceRevision + 1,
          ),
          payload: terminalPayload,
          terminal: true,
        ),
      );
    }

    return const WearRuntimeShellReducer().reduce(state, intent);
  }
}

class WearRuntimeAuthority {
  WearRuntimeAuthority({
    WearScreenId initialScreen = WearScreenId.main,
  }) : _store = WearRuntimeStore(
          initialState: WearRuntimeState.initial(
            legacy: WearLegacyRuntimeSnapshot(
              logicalScreen: initialScreen,
              sourceRevision: 0,
            ),
            payload: WearAggregatePayload.initial(
              initialScreen: initialScreen,
            ),
          ),
          reducer: const WearAggregateReducer(),
        );

  final WearRuntimeStore _store;
  final StreamController<AuthenticatedUser> _authorized =
      StreamController<AuthenticatedUser>.broadcast();
  final StreamController<void> _cleared = StreamController<void>.broadcast();

  Future<void>? _disposeFuture;

  WearRuntimeStore get store => _store;

  WearRuntimeState get state => _store.state;

  WearAggregatePayload get payload =>
      _store.state.payloadAs<WearAggregatePayload>();

  Stream<WearRuntimeState> get states => _store.states;

  Stream<AuthenticatedUser> get authorizedStream => _authorized.stream;

  Stream<void> get clearedStream => _cleared.stream;

  bool get isAuthorized => payload.session.isAuthorized;

  AuthenticatedUser? get userOrNull => payload.session.user;

  WearRuntimeNavigationAdapter navigationAdapter() {
    return WearRuntimeNavigationAdapter(this);
  }

  Future<WearDispatchResult> authorize(AuthenticatedUser user) async {
    final bool wasAuthorized = payload.session.isAuthorized;
    final WearDispatchResult result =
        await _store.dispatch(WearSessionAuthorized(user));
    if (result.accepted &&
        result.stateChanged &&
        !wasAuthorized &&
        !_authorized.isClosed) {
      _authorized.add(payload.session.user!);
    }
    return result;
  }

  Future<WearDispatchResult> clearSession() async {
    final bool wasAuthorized = payload.session.isAuthorized;
    final WearDispatchResult result =
        await _store.dispatch(const WearSessionCleared());
    if (result.accepted &&
        result.stateChanged &&
        wasAuthorized &&
        !_cleared.isClosed) {
      _cleared.add(null);
    }
    return result;
  }

  Future<WearDispatchResult> setRuntimeActive(bool active) {
    return _store.dispatch(WearRuntimeActiveChanged(active));
  }

  Future<WearDispatchResult> setPhoneUiActive(bool active) {
    return _store.dispatch(WearPhoneUiActiveChanged(active));
  }

  Future<WearDispatchResult> requestNavigation(
    WearScreenId screen, {
    WearPendingNavigationKind kind = WearPendingNavigationKind.push,
  }) {
    return _store.dispatch(
      WearLogicalNavigationRequested(screen: screen, kind: kind),
    );
  }

  Future<WearDispatchResult> observePhoneRoute({
    required WearScreenId screen,
    required int observationRevision,
  }) {
    return observePhoneRouteAtEpoch(
      sessionEpoch: state.sessionEpoch,
      screen: screen,
      observationRevision: observationRevision,
    );
  }

  Future<WearDispatchResult> observePhoneRouteAtEpoch({
    required int sessionEpoch,
    required WearScreenId screen,
    required int observationRevision,
  }) {
    return _store.dispatch(
      WearPhoneRouteObserved(
        sessionEpoch: sessionEpoch,
        screen: screen,
        observationRevision: observationRevision,
      ),
    );
  }

  Future<WearDispatchResult> acknowledgeNavigation({
    required int requestId,
    required WearScreenId screen,
  }) {
    return acknowledgeNavigationAtEpoch(
      sessionEpoch: state.sessionEpoch,
      requestId: requestId,
      screen: screen,
    );
  }

  Future<WearDispatchResult> acknowledgeNavigationAtEpoch({
    required int sessionEpoch,
    required int requestId,
    required WearScreenId screen,
  }) {
    return _store.dispatch(
      WearNavigationAcknowledged(
        sessionEpoch: sessionEpoch,
        requestId: requestId,
        screen: screen,
      ),
    );
  }

  Future<WearDispatchResult> back() {
    return _store.dispatch(const WearBackRequested());
  }

  Future<WearDispatchResult> home() {
    return _store.dispatch(const WearHomeRequested());
  }

  Future<WearDispatchResult> terminate() async {
    final WearDispatchResult result =
        await _store.dispatch(const WearRuntimeTerminated());
    await _store.dispose();
    await _closeCompatibilityStreams();
    return result;
  }

  Future<void> dispose() {
    final Future<void>? existing = _disposeFuture;
    if (existing != null) return existing;
    final Completer<void> completer = Completer<void>();
    _disposeFuture = completer.future;
    unawaited(
      Future<void>.sync(() async {
        if (!_store.state.terminal) {
          await _store.dispatch(const WearRuntimeTerminated());
        }
        await _store.dispose();
        await _closeCompatibilityStreams();
        completer.complete();
      }).catchError((Object error, StackTrace stackTrace) {
        if (!completer.isCompleted) completer.completeError(error, stackTrace);
      }),
    );
    return completer.future;
  }

  Future<void> _closeCompatibilityStreams() async {
    if (!_authorized.isClosed) await _authorized.close();
    if (!_cleared.isClosed) await _cleared.close();
  }
}

/// Epoch-bound adapter for asynchronous Flutter route callbacks.
///
/// Recreating the adapter after an epoch change is deliberate. A callback held
/// by an older route keeps the old epoch and is rejected even if it arrives
/// after the next session has already created a request with similar data.
class WearRuntimeNavigationAdapter {
  WearRuntimeNavigationAdapter(WearRuntimeAuthority authority)
      : _authority = authority,
        sessionEpoch = authority.state.sessionEpoch,
        _nextObservationRevision =
            authority.payload.navigation.routeObservationRevision;

  final WearRuntimeAuthority _authority;
  final int sessionEpoch;
  int _nextObservationRevision;

  Future<WearDispatchResult> observePhoneRoute(WearScreenId screen) {
    return _authority.observePhoneRouteAtEpoch(
      sessionEpoch: sessionEpoch,
      screen: screen,
      observationRevision: ++_nextObservationRevision,
    );
  }

  Future<WearDispatchResult> acknowledge({
    required int requestId,
    required WearScreenId screen,
  }) {
    return _authority.acknowledgeNavigationAtEpoch(
      sessionEpoch: sessionEpoch,
      requestId: requestId,
      screen: screen,
    );
  }
}
