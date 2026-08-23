import 'package:flutter_test/flutter_test.dart';
import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/domain/auth/model/authenticated_user.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_authority.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_store.dart';

void main() {
  AuthenticatedUser user(int id) => AuthenticatedUser(
        idUser: id,
        idEmployee: id + 100,
        name: 'User $id',
      );

  test('authorization starts a new session epoch', () async {
    final WearRuntimeAuthority authority = WearRuntimeAuthority();
    addTearDown(authority.dispose);
    final int anonymousEpoch = authority.state.sessionEpoch;

    final WearDispatchResult result = await authority.authorize(user(1));

    expect(result.accepted, isTrue);
    expect(result.stateChanged, isTrue);
    expect(authority.state.sessionEpoch, anonymousEpoch + 1);
    expect(authority.state.revision, 0);
  });

  test('route callback captured before authorization is stale afterwards',
      () async {
    final WearRuntimeAuthority authority = WearRuntimeAuthority();
    addTearDown(authority.dispose);
    final WearRuntimeNavigationAdapter anonymousAdapter =
        authority.navigationAdapter();

    await authority.authorize(user(1));
    final WearDispatchResult late =
        await anonymousAdapter.observePhoneRoute(WearScreenId.main);

    expect(late.accepted, isFalse);
    expect(late.rejectReason, WearDispatchRejectReason.staleEpoch);
    expect(authority.payload.navigation.actualPhoneScreen, isNull);
  });

  test('session reset never reuses route or request identities', () async {
    final WearRuntimeAuthority authority = WearRuntimeAuthority();
    addTearDown(authority.dispose);
    await authority.authorize(user(1));
    final WearRuntimeNavigationAdapter firstSession =
        authority.navigationAdapter();

    final WearDispatchResult firstObservation =
        await firstSession.observePhoneRoute(WearScreenId.main);
    expect(firstObservation.accepted, isTrue);
    await authority.requestNavigation(WearScreenId.menu);
    final int oldRequestId =
        authority.payload.navigation.pending!.requestId;
    final int oldObservationRevision =
        authority.payload.navigation.routeObservationRevision;

    await authority.clearSession();
    await authority.authorize(user(2));
    await authority.requestNavigation(WearScreenId.printerSelect);
    final int newRequestId =
        authority.payload.navigation.pending!.requestId;
    final WearRuntimeNavigationAdapter secondSession =
        authority.navigationAdapter();
    final WearDispatchResult secondObservation =
        await secondSession.observePhoneRoute(WearScreenId.main);

    expect(newRequestId, greaterThan(oldRequestId));
    expect(
      authority.payload.navigation.routeObservationRevision,
      greaterThan(oldObservationRevision),
    );
    expect(secondObservation.accepted, isTrue);

    final WearDispatchResult lateAcknowledgement = await firstSession.acknowledge(
      requestId: oldRequestId,
      screen: WearScreenId.menu,
    );
    expect(lateAcknowledgement.accepted, isFalse);
    expect(
      lateAcknowledgement.rejectReason,
      WearDispatchRejectReason.staleEpoch,
    );
    expect(
      authority.payload.navigation.pending?.requestId,
      newRequestId,
    );
  });
}
