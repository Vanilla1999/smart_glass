import 'package:smart_glasses/modules/wear/application/runtime/wear_runtime_contract.dart';
import 'package:smart_glasses/modules/wear/application/wear_flow_state.dart';
import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/domain/auth/model/authenticated_user.dart';

class WearRuntimeSessionState {
  const WearRuntimeSessionState({
    required this.authorized,
    this.identity,
  });

  const WearRuntimeSessionState.anonymous()
      : authorized = false,
        identity = null;

  final bool authorized;
  final AuthenticatedUser? identity;

  WearRuntimeSessionState copyWith({
    bool? authorized,
    AuthenticatedUser? identity,
    bool clearIdentity = false,
  }) {
    return WearRuntimeSessionState(
      authorized: authorized ?? this.authorized,
      identity: clearIdentity ? null : identity ?? this.identity,
    );
  }
}

class WearRuntimeLifecycleState {
  const WearRuntimeLifecycleState({
    required this.runtimeActive,
    required this.phoneUiActive,
  });

  const WearRuntimeLifecycleState.initial()
      : runtimeActive = true,
        phoneUiActive = false;

  final bool runtimeActive;
  final bool phoneUiActive;

  WearRuntimeLifecycleState copyWith({
    bool? runtimeActive,
    bool? phoneUiActive,
  }) {
    return WearRuntimeLifecycleState(
      runtimeActive: runtimeActive ?? this.runtimeActive,
      phoneUiActive: phoneUiActive ?? this.phoneUiActive,
    );
  }
}

class WearPhoneNavigationState {
  const WearPhoneNavigationState({
    required this.observationRevision,
    this.actualScreen,
  }) : assert(observationRevision >= 0);

  const WearPhoneNavigationState.initial()
      : observationRevision = 0,
        actualScreen = null;

  final int observationRevision;
  final WearScreenId? actualScreen;

  WearPhoneNavigationState copyWith({
    int? observationRevision,
    WearScreenId? actualScreen,
    bool clearActualScreen = false,
  }) {
    return WearPhoneNavigationState(
      observationRevision: observationRevision ?? this.observationRevision,
      actualScreen:
          clearActualScreen ? null : actualScreen ?? this.actualScreen,
    );
  }
}

final class WearFlowStateReplaced extends WearInternalIntent {
  const WearFlowStateReplaced(this.flow);

  final WearFlowState flow;
}

final class WearSessionAuthorizedIntent extends WearInternalIntent {
  const WearSessionAuthorizedIntent({this.identity});

  final AuthenticatedUser? identity;
}

final class WearSessionClearedIntent extends WearInternalIntent {
  const WearSessionClearedIntent();
}

final class WearRuntimeActiveChangedIntent extends WearInternalIntent {
  const WearRuntimeActiveChangedIntent(this.active);

  final bool active;
}

final class WearPhoneUiActiveChangedIntent extends WearInternalIntent {
  const WearPhoneUiActiveChangedIntent(this.active);

  final bool active;
}

final class WearPhoneRouteObservedIntent extends WearInternalIntent {
  const WearPhoneRouteObservedIntent({
    required this.screen,
    required this.observationRevision,
  });

  final WearScreenId screen;
  final int observationRevision;
}
