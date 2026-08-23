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

  test('authorization resets controls and printer task in a new epoch',
      () async {
    final WearRuntimeAuthority authority = WearRuntimeAuthority();
    addTearDown(authority.dispose);
    final int anonymousEpoch = authority.state.sessionEpoch;

    final WearDispatchResult result = await authority.authorize(user(1));

    expect(result.accepted, isTrue);
    expect(authority.state.sessionEpoch, anonymousEpoch + 1);
    expect(authority.controls.voice.acceptsCommands, isFalse);
    expect(authority.printerTask.selection, isNull);
  });

  test('old navigation adapter is stale after a session transition', () async {
    final WearRuntimeAuthority authority = WearRuntimeAuthority();
    addTearDown(authority.dispose);
    final WearRuntimeNavigationAdapter oldAdapter = authority.navigationAdapter();

    await authority.authorize(user(1));
    final WearDispatchResult late =
        await oldAdapter.observePhoneRoute(WearScreenId.main);

    expect(late.accepted, isFalse);
    expect(late.rejectReason, WearDispatchRejectReason.staleEpoch);
  });

  test('session clear preserves navigation identity monotonicity', () async {
    final WearRuntimeAuthority authority = WearRuntimeAuthority();
    addTearDown(authority.dispose);
    await authority.authorize(user(1));
    final WearRuntimeNavigationAdapter firstSession =
        authority.navigationAdapter();
    await authority.requestNavigation(WearScreenId.menu);
    final int oldRequest = authority.payload.navigation.pending!.requestId;

    await authority.clearSession();
    await authority.authorize(user(2));
    await authority.requestNavigation(WearScreenId.printerSelect);
    final int nextRequest = authority.payload.navigation.pending!.requestId;

    expect(nextRequest, greaterThan(oldRequest));
    final WearDispatchResult oldAck = await firstSession.acknowledge(
      requestId: oldRequest,
      screen: WearScreenId.menu,
    );
    expect(oldAck.accepted, isFalse);
    expect(oldAck.rejectReason, WearDispatchRejectReason.staleEpoch);
  });
}
