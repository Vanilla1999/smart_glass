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

  test('authorization advances the epoch before controls become current',
      () async {
    final WearRuntimeAuthority authority = WearRuntimeAuthority();
    addTearDown(authority.dispose);
    final int anonymousEpoch = authority.state.sessionEpoch;

    final WearDispatchResult result = await authority.authorize(user(1));

    expect(result.accepted, isTrue);
    expect(authority.state.sessionEpoch, anonymousEpoch + 1);
    expect(authority.state.revision, 0);
  });

  test('pre-auth route adapter cannot mutate the authorized epoch', () async {
    final WearRuntimeAuthority authority = WearRuntimeAuthority();
    addTearDown(authority.dispose);
    final WearRuntimeNavigationAdapter oldAdapter = authority.navigationAdapter();

    await authority.authorize(user(1));
    final WearDispatchResult result =
        await oldAdapter.observePhoneRoute(WearScreenId.main);

    expect(result.accepted, isFalse);
    expect(result.rejectReason, WearDispatchRejectReason.staleEpoch);
  });

  test('old-session acknowledgement cannot collide after reset', () async {
    final WearRuntimeAuthority authority = WearRuntimeAuthority();
    addTearDown(authority.dispose);
    await authority.authorize(user(1));
    final WearRuntimeNavigationAdapter firstSession =
        authority.navigationAdapter();
    await authority.requestNavigation(WearScreenId.menu);
    final int oldRequestId = authority.payload.navigation.pending!.requestId;
    final int oldObservationRevision =
        authority.payload.navigation.routeObservationRevision;

    await authority.clearSession();
    await authority.authorize(user(2));
    await authority.requestNavigation(WearScreenId.printerSelect);
    final int newRequestId = authority.payload.navigation.pending!.requestId;
    final WearRuntimeNavigationAdapter secondSession =
        authority.navigationAdapter();
    final WearDispatchResult newObservation =
        await secondSession.observePhoneRoute(WearScreenId.main);

    expect(newRequestId, greaterThan(oldRequestId));
    expect(newObservation.accepted, isTrue);
    expect(
      authority.payload.navigation.routeObservationRevision,
      greaterThan(oldObservationRevision),
    );

    final WearDispatchResult late = await firstSession.acknowledge(
      requestId: oldRequestId,
      screen: WearScreenId.menu,
    );
    expect(late.accepted, isFalse);
    expect(late.rejectReason, WearDispatchRejectReason.staleEpoch);
    expect(authority.payload.navigation.pending?.requestId, newRequestId);
  });
}
