import 'package:flutter_test/flutter_test.dart';
import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_authority.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_store.dart';

void main() {
  test('logical screen leads while actual phone route lags', () async {
    final WearRuntimeAuthority authority = WearRuntimeAuthority();
    addTearDown(authority.dispose);
    await authority.observePhoneRouteAtEpoch(
      sessionEpoch: authority.state.sessionEpoch,
      screen: WearScreenId.main,
      observationRevision: 1,
    );

    await authority.requestNavigation(WearScreenId.printerSelect);

    final WearNavigationSlice navigation = authority.payload.navigation;
    expect(navigation.logicalScreen, WearScreenId.printerSelect);
    expect(navigation.actualPhoneScreen, WearScreenId.main);
    expect(navigation.pending?.screen, WearScreenId.printerSelect);
    expect(authority.state.legacy.logicalScreen, WearScreenId.printerSelect);
  });

  test('stale route observation cannot roll actual route backwards', () async {
    final WearRuntimeAuthority authority = WearRuntimeAuthority();
    addTearDown(authority.dispose);
    await authority.observePhoneRouteAtEpoch(
      sessionEpoch: authority.state.sessionEpoch,
      screen: WearScreenId.menu,
      observationRevision: 2,
    );

    final WearDispatchResult stale = await authority.observePhoneRouteAtEpoch(
      sessionEpoch: authority.state.sessionEpoch,
      screen: WearScreenId.main,
      observationRevision: 1,
    );

    expect(stale.accepted, isFalse);
    expect(stale.rejectReason, WearDispatchRejectReason.staleOperation);
    expect(authority.payload.navigation.actualPhoneScreen, WearScreenId.menu);
    expect(authority.payload.navigation.routeObservationRevision, 2);
  });

  test('only current navigation request can be acknowledged', () async {
    final WearRuntimeAuthority authority = WearRuntimeAuthority();
    addTearDown(authority.dispose);
    await authority.requestNavigation(WearScreenId.menu);
    final WearPendingNavigation current = authority.payload.navigation.pending!;

    final WearDispatchResult stale =
        await authority.acknowledgeNavigationAtEpoch(
      sessionEpoch: authority.state.sessionEpoch,
      requestId: current.requestId + 1,
      screen: current.screen,
    );
    final WearDispatchResult accepted =
        await authority.acknowledgeNavigationAtEpoch(
      sessionEpoch: authority.state.sessionEpoch,
      requestId: current.requestId,
      screen: current.screen,
    );

    expect(stale.accepted, isFalse);
    expect(stale.rejectReason, WearDispatchRejectReason.staleOperation);
    expect(accepted.accepted, isTrue);
    expect(authority.payload.navigation.pending, isNull);
    expect(authority.payload.navigation.actualPhoneScreen, WearScreenId.menu);
  });

  test('duplicate pending navigation preserves request identity', () async {
    final WearRuntimeAuthority authority = WearRuntimeAuthority();
    addTearDown(authority.dispose);
    await authority.requestNavigation(WearScreenId.menu);
    final int requestId = authority.payload.navigation.pending!.requestId;

    final WearDispatchResult duplicate =
        await authority.requestNavigation(WearScreenId.menu);

    expect(duplicate.accepted, isFalse);
    expect(duplicate.rejectReason, WearDispatchRejectReason.duplicate);
    expect(authority.payload.navigation.pending!.requestId, requestId);
  });

  test('back and home update immutable history deterministically', () async {
    final WearRuntimeAuthority authority = WearRuntimeAuthority();
    addTearDown(authority.dispose);
    await authority.requestNavigation(WearScreenId.menu);
    await authority.acknowledgeNavigationAtEpoch(
      sessionEpoch: authority.state.sessionEpoch,
      requestId: authority.payload.navigation.pending!.requestId,
      screen: WearScreenId.menu,
    );
    await authority.requestNavigation(WearScreenId.printerSelect);
    await authority.acknowledgeNavigationAtEpoch(
      sessionEpoch: authority.state.sessionEpoch,
      requestId: authority.payload.navigation.pending!.requestId,
      screen: WearScreenId.printerSelect,
    );
    await authority.requestNavigation(WearScreenId.scanIdle);

    await authority.back();
    expect(
      authority.payload.navigation.logicalScreen,
      WearScreenId.printerSelect,
    );
    await authority.home();

    expect(authority.payload.navigation.logicalScreen, WearScreenId.menu);
    expect(
      authority.payload.navigation.history,
      <WearScreenId>[WearScreenId.menu],
    );
    expect(
      () => authority.payload.navigation.history.add(WearScreenId.help),
      throwsUnsupportedError,
    );
  });

  test('new navigation supersedes the previous pending request', () async {
    final WearRuntimeAuthority authority = WearRuntimeAuthority();
    addTearDown(authority.dispose);
    await authority.requestNavigation(WearScreenId.printerSelect);
    final int firstRequest = authority.payload.navigation.pending!.requestId;

    await authority.requestNavigation(WearScreenId.scanIdle);

    final WearPendingNavigation latest = authority.payload.navigation.pending!;
    expect(latest.requestId, greaterThan(firstRequest));
    expect(latest.screen, WearScreenId.scanIdle);
    final WearDispatchResult oldAck =
        await authority.acknowledgeNavigationAtEpoch(
      sessionEpoch: authority.state.sessionEpoch,
      requestId: firstRequest,
      screen: WearScreenId.printerSelect,
    );
    expect(oldAck.rejectReason, WearDispatchRejectReason.staleOperation);
  });

  test('terminal rejects route adapter callbacks without changing route',
      () async {
    final WearRuntimeAuthority authority = WearRuntimeAuthority();
    final WearRuntimeNavigationAdapter adapter = authority.navigationAdapter();
    await adapter.observePhoneRoute(WearScreenId.main);
    await authority.terminate();

    final WearDispatchResult late =
        await adapter.observePhoneRoute(WearScreenId.menu);

    expect(late.rejectReason, WearDispatchRejectReason.terminal);
    expect(
      authority.payload.navigation.actualPhoneScreen,
      WearScreenId.main,
    );
  });
}
