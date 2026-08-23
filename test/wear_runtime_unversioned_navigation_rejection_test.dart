import 'package:flutter_test/flutter_test.dart';
import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/domain/auth/model/authenticated_user.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_authority.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_store.dart';

void main() {
  test('raw route and acknowledgement intents cannot bypass epoch adapter',
      () async {
    final WearRuntimeAuthority authority = WearRuntimeAuthority();
    addTearDown(authority.dispose);
    await authority.authorize(
      AuthenticatedUser(idUser: 1, idEmployee: 2, name: 'User'),
    );
    await authority.requestNavigation(WearScreenId.menu);
    final int requestId = authority.payload.navigation.pending!.requestId;

    final WearDispatchResult route = await authority.store.dispatch(
      const WearPhoneRouteObserved(
        screen: WearScreenId.menu,
        observationRevision: 1,
      ),
    );
    final WearDispatchResult acknowledgement = await authority.store.dispatch(
      WearNavigationAcknowledged(
        requestId: requestId,
        screen: WearScreenId.menu,
      ),
    );

    expect(route.accepted, isFalse);
    expect(route.rejectReason, WearDispatchRejectReason.unsupported);
    expect(acknowledgement.accepted, isFalse);
    expect(
      acknowledgement.rejectReason,
      WearDispatchRejectReason.unsupported,
    );
    expect(authority.payload.navigation.pending?.requestId, requestId);
  });
}
