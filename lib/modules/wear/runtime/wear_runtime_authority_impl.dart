import 'dart:async';

import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/domain/auth/model/authenticated_user.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_availability_review_reducer.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_availability_slice.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_control_slices.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_control_validation_reducer.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_core_slices.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_effect_router.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_feature_epoch_reducer.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_navigation_epoch_reducer.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_printer_composite_reducer.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_printer_slice.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_scan_review_reducers.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_scan_slice.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_store.dart';

class WearRuntimeAuthority {
  factory WearRuntimeAuthority({
    WearScreenId initialScreen = WearScreenId.main,
  }) {
    final WearRuntimeEffectRouter effectRouter = WearRuntimeEffectRouter();
    return WearRuntimeAuthority._(
      initialScreen: initialScreen,
      effectRouter: effectRouter,
    );
  }

  WearRuntimeAuthority._({
    required WearScreenId initialScreen,
    required WearRuntimeEffectRouter effectRouter,
  })  : _effectRouter = effectRouter,
        _store = WearRuntimeStore(
          initialState: WearRuntimeState.initial(
            legacy: WearLegacyRuntimeSnapshot(
              logicalScreen: initialScreen,
              sourceRevision: 0,
            ),
            payload: WearAggregatePayload(
              session: const WearSessionSlice.anonymous(),
              lifecycle: const WearLifecycleSlice.initial(),
              navigation: WearNavigationSlice.initial(screen: initialScreen),
              features: WearRuntimeFeaturePayload(
                printer: WearPrinterTaskSlice.initial(),
                scan: WearScanTaskSlice.initial(),
                availability: WearAvailabilityTaskSlice.initial(),
              ),
              controls: const WearRuntimeControlPayload.initial(),
              presentation: const WearLegacyPresentationPayload(),
            ),
          ),
          reducer: WearAggregateReducer(
            sliceReducers: const <WearSliceReducer>[
              WearControlInputValidationReducer(),
              WearRuntimeFeatureEpochReducer(),
              WearSessionNavigationEpochReducer(),
              WearControlSliceReducer(),
              WearReviewedPrinterSliceReducer(),
              WearReviewedScanSliceReducer(),
              WearReviewedAvailabilitySliceReducer(),
              WearCoreSliceReducer(),
            ],
          ),
          effectHandler: effectRouter,
        );

  final WearRuntimeStore _store;
  final WearRuntimeEffectRouter _effectRouter;
  final WearOperationIdGenerator _operationIds = WearOperationIdGenerator();
  final StreamController<AuthenticatedUser> _authorized =
      StreamController<AuthenticatedUser>.broadcast();
  final StreamController<void> _cleared = StreamController<void>.broadcast();

  Future<void>? _disposeFuture;

  WearRuntimeStore get store => _store;

  WearRuntimeState get state => _store.state;

  WearAggregatePayload get payload =>
      _store.state.payloadAs<WearAggregatePayload>();

  WearRuntimeControlPayload get controls =>
      payload.controls as WearRuntimeControlPayload;

  WearRuntimeFeaturePayload get features =>
      payload.features as WearRuntimeFeaturePayload;

  Stream<WearRuntimeState> get states => _store.states;

  Stream<AuthenticatedUser> get authorizedStream => _authorized.stream;

  Stream<void> get clearedStream => _cleared.stream;

  bool get isAuthorized => payload.session.isAuthorized;

  AuthenticatedUser? get userOrNull => payload.session.user;

  int allocateOperationId() => _operationIds.next();

  WearRuntimeNavigationAdapter navigationAdapter() {
    return WearRuntimeNavigationAdapter(this);
  }

  void registerEffectExecutor(WearEffectExecutor executor) {
    _effectRouter.register(executor);
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

  Future<WearDispatchResult> observePhoneRouteAtEpoch({
    required int sessionEpoch,
    required WearScreenId screen,
    required int observationRevision,
  }) {
    return _store.dispatch(
      WearEpochBoundPhoneRouteObserved(
        sessionEpoch: sessionEpoch,
        screen: screen,
        observationRevision: observationRevision,
      ),
    );
  }

  Future<WearDispatchResult> acknowledgeNavigationAtEpoch({
    required int sessionEpoch,
    required int requestId,
    required WearScreenId screen,
  }) {
    return _store.dispatch(
      WearEpochBoundNavigationAcknowledged(
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
