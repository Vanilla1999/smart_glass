import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/domain/auth/model/authenticated_user.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_authority.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_store.dart';

void main() {
  AuthenticatedUser user({
    int idUser = 1,
    int idEmployee = 2,
    String name = 'Сотрудник',
  }) {
    return AuthenticatedUser(
      idUser: idUser,
      idEmployee: idEmployee,
      name: name,
    );
  }

  test('authorization owns identity and emits once', () async {
    final WearRuntimeAuthority authority = WearRuntimeAuthority();
    addTearDown(authority.dispose);
    final List<AuthenticatedUser> events = <AuthenticatedUser>[];
    final StreamSubscription<AuthenticatedUser> subscription =
        authority.authorizedStream.listen(events.add);
    addTearDown(subscription.cancel);
    final AuthenticatedUser firstUser = user();

    final WearDispatchResult first = await authority.authorize(firstUser);
    final int revision = authority.state.revision;
    final WearDispatchResult duplicate = await authority.authorize(firstUser);
    await Future<void>.delayed(Duration.zero);

    expect(first.accepted, isTrue);
    expect(first.stateChanged, isTrue);
    expect(authority.userOrNull?.idUser, 1);
    expect(duplicate.accepted, isTrue);
    expect(duplicate.stateChanged, isFalse);
    expect(authority.state.revision, revision);
    expect(events, hasLength(1));
  });

  test('different identity cannot replace an active session', () async {
    final WearRuntimeAuthority authority = WearRuntimeAuthority();
    addTearDown(authority.dispose);
    await authority.authorize(user());

    final WearDispatchResult result = await authority.authorize(
      user(idUser: 9, idEmployee: 10, name: 'Другой'),
    );

    expect(result.accepted, isFalse);
    expect(result.rejectReason, WearDispatchRejectReason.busy);
    expect(authority.userOrNull?.idUser, 1);
  });

  test('session clear supersedes epoch and resets navigation', () async {
    final WearRuntimeAuthority authority = WearRuntimeAuthority();
    addTearDown(authority.dispose);
    await authority.authorize(user());
    await authority.setPhoneUiActive(true);
    await authority.requestNavigation(WearScreenId.menu);
    final int oldEpoch = authority.state.sessionEpoch;

    final WearDispatchResult result = await authority.clearSession();

    expect(result.stateChanged, isTrue);
    expect(authority.state.sessionEpoch, oldEpoch + 1);
    expect(authority.state.revision, 0);
    expect(authority.isAuthorized, isFalse);
    expect(authority.payload.lifecycle.runtimeActive, isFalse);
    expect(authority.payload.lifecycle.phoneUiActive, isTrue);
    expect(authority.payload.navigation.logicalScreen, WearScreenId.main);
    expect(authority.payload.navigation.pending, isNull);
  });

  test('runtime cannot become active before authorization', () async {
    final WearRuntimeAuthority authority = WearRuntimeAuthority();
    addTearDown(authority.dispose);

    final WearDispatchResult result = await authority.setRuntimeActive(true);

    expect(result.accepted, isFalse);
    expect(result.rejectReason, WearDispatchRejectReason.unsupported);
  });

  test('phone UI pause does not stop authorized runtime', () async {
    final WearRuntimeAuthority authority = WearRuntimeAuthority();
    addTearDown(authority.dispose);
    await authority.authorize(user());
    await authority.setPhoneUiActive(true);

    await authority.setPhoneUiActive(false);

    expect(authority.payload.lifecycle.phoneUiActive, isFalse);
    expect(authority.payload.lifecycle.runtimeActive, isTrue);
  });

  test('terminal lifecycle closes admission and state stream', () async {
    final WearRuntimeAuthority authority = WearRuntimeAuthority();
    await authority.authorize(user());
    final Future<List<WearRuntimeState>> allStates = authority.states.toList();

    final WearDispatchResult terminal = await authority.terminate();
    final List<WearRuntimeState> emitted = await allStates;

    expect(terminal.accepted, isTrue);
    expect(authority.state.terminal, isTrue);
    expect(authority.payload.lifecycle.terminal, isTrue);
    expect(authority.payload.lifecycle.runtimeActive, isFalse);
    expect(authority.isAuthorized, isFalse);
    expect(emitted.last.terminal, isTrue);

    final WearDispatchResult late =
        await authority.requestNavigation(WearScreenId.menu);
    expect(late.rejectReason, WearDispatchRejectReason.terminal);
  });

  test('dispose terminalizes before ordinary callbacks can revive runtime',
      () async {
    final WearRuntimeAuthority authority = WearRuntimeAuthority();
    await authority.authorize(user());

    await authority.dispose();
    final WearDispatchResult auth = await authority.authorize(user());
    final WearDispatchResult runtime = await authority.setRuntimeActive(true);
    final WearDispatchResult phone = await authority.setPhoneUiActive(true);

    expect(authority.state.terminal, isTrue);
    expect(authority.isAuthorized, isFalse);
    expect(auth.rejectReason, WearDispatchRejectReason.terminal);
    expect(runtime.rejectReason, WearDispatchRejectReason.terminal);
    expect(phone.rejectReason, WearDispatchRejectReason.terminal);
  });

  test('unmigrated ownership remains explicit', () {
    final WearRuntimeAuthority authority = WearRuntimeAuthority();
    addTearDown(authority.dispose);

    expect(authority.payload.features, isA<WearLegacyFeaturePayload>());
    expect(authority.payload.controls, isA<WearLegacyControlPayload>());
    expect(
      authority.payload.presentation,
      isA<WearLegacyPresentationPayload>(),
    );
  });
}
