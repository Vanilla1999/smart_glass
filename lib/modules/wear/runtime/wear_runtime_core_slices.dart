import 'dart:collection';

import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/domain/auth/model/authenticated_user.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_store.dart';

abstract interface class WearFeaturePayload {}

class WearLegacyFeaturePayload implements WearFeaturePayload {
  const WearLegacyFeaturePayload();
}

abstract interface class WearControlPayload {
  WearControlPayload toTerminalControls();
}

class WearLegacyControlPayload implements WearControlPayload {
  const WearLegacyControlPayload();

  @override
  WearControlPayload toTerminalControls() => this;
}

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

  WearNavigationSlice acknowledge(WearScreenId screen) {
    return WearNavigationSlice(
      logicalScreen: logicalScreen,
      actualPhoneScreen: screen,
      pending: null,
      history: history,
      routeObservationRevision: routeObservationRevision,
      nextRequestId: nextRequestId,
    );
  }

  WearNavigationSlice clearForSession(WearScreenId screen) {
    return WearNavigationSlice.initial(screen: screen);
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
  const WearAggregatePayload({
    required this.session,
    required this.lifecycle,
    required this.navigation,
    required this.features,
    required this.controls,
    required this.presentation,
  });

  factory WearAggregatePayload.initial({
    WearScreenId initialScreen = WearScreenId.main,
    WearControlPayload controls = const WearLegacyControlPayload(),
  }) {
    return WearAggregatePayload(
      session: const WearSessionSlice.anonymous(),
      lifecycle: const WearLifecycleSlice.initial(),
      navigation: WearNavigationSlice.initial(screen: initialScreen),
      features: const WearLegacyFeaturePayload(),
      controls: controls,
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
    return WearAggregatePayload(
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
      controls: controls.toTerminalControls(),
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
    required this.screen,
    required this.observationRevision,
  });

  final WearScreenId screen;
  final int observationRevision;
}

class WearNavigationAcknowledged extends WearIntent {
  const WearNavigationAcknowledged({
    required this.requestId,
    required this.screen,
  });

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

abstract interface class WearSliceReducer {
  WearReduction? reduceSlice(WearRuntimeState state, WearIntent intent);
}

class WearCoreSliceReducer implements WearSliceReducer {
  const WearCoreSliceReducer();

  @override
  WearReduction? reduceSlice(WearRuntimeState state, WearIntent intent) {
    final WearAggregatePayload payload = state.payloadAs<WearAggregatePayload>();

    if (intent is WearSessionAuthorized) {
      final WearSessionSlice nextSession =
          WearSessionSlice.authorized(intent.user);
      if (payload.session.isAuthorized) {
        if (payload.session.sameIdentityAs(nextSession)) {
          return WearReduction.accept();
        }
        return WearReduction.reject(WearDispatchRejectReason.busy);
      }
      return WearReduction.accept(
        nextState: state.withPayload(
          payload.copyWith(
            session: nextSession,
            lifecycle: payload.lifecycle.copyWith(runtimeActive: true),
          ),
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
      final WearPendingNavigation? pending = payload.navigation.pending;
      if (pending == null ||
          pending.requestId != intent.requestId ||
          pending.screen != intent.screen) {
        return WearReduction.reject(WearDispatchRejectReason.staleOperation);
      }
      return WearReduction.accept(
        nextState: state.withPayload(
          payload.copyWith(
            navigation: payload.navigation.acknowledge(intent.screen),
          ),
        ),
      );
    }

    if (intent is WearBackRequested) {
      final List<WearScreenId> history = payload.navigation.history;
      if (history.length <= 1) {
        return WearReduction.reject(WearDispatchRejectReason.unsupported);
      }
      return reduceSlice(
        state,
        WearLogicalNavigationRequested(
          screen: history[history.length - 2],
          kind: WearPendingNavigationKind.pop,
        ),
      );
    }

    if (intent is WearHomeRequested) {
      return reduceSlice(
        state,
        const WearLogicalNavigationRequested(
          screen: WearScreenId.menu,
          kind: WearPendingNavigationKind.replace,
        ),
      );
    }

    if (intent is WearRuntimeTerminated) {
      return WearReduction.accept(
        nextState: state.beginNextEpoch(
          legacy: WearLegacyRuntimeSnapshot(
            logicalScreen: payload.navigation.logicalScreen,
            sourceRevision: state.legacy.sourceRevision + 1,
          ),
          payload: payload.toTerminalPayload(),
          terminal: true,
        ),
      );
    }

    return null;
  }
}

class WearAggregateReducer implements WearRuntimeReducer {
  WearAggregateReducer({
    Iterable<WearSliceReducer> sliceReducers = const <WearSliceReducer>[
      WearCoreSliceReducer(),
    ],
  }) : _sliceReducers = List<WearSliceReducer>.unmodifiable(sliceReducers);

  final List<WearSliceReducer> _sliceReducers;

  @override
  WearReduction reduce(WearRuntimeState state, WearIntent intent) {
    final WearAggregatePayload payload = state.payloadAs<WearAggregatePayload>();
    if (state.terminal || payload.lifecycle.terminal) {
      return WearReduction.reject(WearDispatchRejectReason.terminal);
    }
    for (final WearSliceReducer reducer in _sliceReducers) {
      final WearReduction? reduction = reducer.reduceSlice(state, intent);
      if (reduction != null) return reduction;
    }
    return const WearRuntimeShellReducer().reduce(state, intent);
  }
}
