import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_glasses/modules/wear/application/voice_clarification_args.dart';
import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/application/wear_status_state.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/voice_utterance_coordinator.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/status/wear_status_args.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_authority.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_presentation_slice.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_presentation_scheduler.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_projection.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_store.dart';

void main() {
  test('focus update preserves aggregate status presentation fields', () {
    final WearStatusScreenArgs args = _statusArgs();
    final WearRuntimePresentationSlice presentation =
        WearRuntimePresentationSlice(
      focusedIndices: const <WearScreenId, int>{WearScreenId.menu: 2},
      statusArgs: args,
      statusCompletion: const WearStatusCompletion.goTo(WearScreenId.menu),
      statusOperationId: 7,
      statusDeadline: DateTime.utc(2026, 8, 24),
    );

    final WearRuntimePresentationSlice next =
        presentation.withFocus(WearScreenId.menu, 3);

    expect(next.focusFor(WearScreenId.menu), 3);
    expect(next.statusArgs, same(args));
    expect(next.statusOperationId, 7);
  });

  test('generic status commits before elapsed navigation', () async {
    final WearRuntimeAuthority authority = WearRuntimeAuthority(
      initialScreen: WearScreenId.help,
    );
    addTearDown(authority.dispose);
    final int operationId = authority.allocateOperationId();

    final WearDispatchResult shown = await authority.store.dispatch(
      WearGenericStatusShown(
        sessionEpoch: authority.state.sessionEpoch,
        operationId: operationId,
        expectedScreen: WearScreenId.help,
        args: _statusArgs(),
        completion: const WearStatusCompletion.goTo(WearScreenId.menu),
        deadline: DateTime.now().add(const Duration(seconds: 1)),
      ),
    );

    expect(shown.accepted, isTrue);
    expect(authority.payload.navigation.logicalScreen, WearScreenId.status);
    final WearRuntimePresentationSlice committed =
        WearRuntimePresentationSlice.from(authority.payload.presentation);
    expect(committed.statusArgs?.title, 'Готово');
    expect(committed.statusOperationId, operationId);
    expect(
      authority.state.expectedOperationId(wearGenericStatusOperationKind),
      operationId,
    );

    final WearDispatchResult elapsed = await authority.store.dispatch(
      WearGenericStatusElapsed(
        sessionEpoch: authority.state.sessionEpoch,
        operationId: operationId,
      ),
    );

    expect(elapsed.accepted, isTrue);
    expect(authority.payload.navigation.logicalScreen, WearScreenId.menu);
    expect(
      WearRuntimePresentationSlice.from(authority.payload.presentation)
          .statusArgs,
      isNull,
    );
  });

  test('scheduler notifies owner after accepted elapsed dispatch', () async {
    final WearRuntimeAuthority authority = WearRuntimeAuthority(
      initialScreen: WearScreenId.help,
    );
    var callbacks = 0;
    final WearRuntimePresentationScheduler scheduler =
        WearRuntimePresentationScheduler(
      authority,
      onElapsedAccepted: () => callbacks++,
    );
    addTearDown(scheduler.dispose);
    addTearDown(authority.dispose);

    await authority.store.dispatch(WearGenericStatusShown(
      sessionEpoch: authority.state.sessionEpoch,
      operationId: authority.allocateOperationId(),
      expectedScreen: WearScreenId.help,
      args: _statusArgs(),
      completion: const WearStatusCompletion.goTo(WearScreenId.menu),
      deadline: DateTime.now(),
    ));
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(callbacks, 1);
    expect(authority.payload.navigation.logicalScreen, WearScreenId.menu);
  });

  test('stale generic status elapsed cannot navigate a new epoch', () async {
    final WearRuntimeAuthority authority = WearRuntimeAuthority(
      initialScreen: WearScreenId.help,
    );
    addTearDown(authority.dispose);
    final int epoch = authority.state.sessionEpoch;
    final int operationId = authority.allocateOperationId();

    await authority.store.dispatch(WearGenericStatusShown(
      sessionEpoch: epoch,
      operationId: operationId,
      expectedScreen: WearScreenId.help,
      args: _statusArgs(),
      completion: const WearStatusCompletion.goTo(WearScreenId.menu),
      deadline: DateTime.now().add(const Duration(seconds: 1)),
    ));
    await authority.store.dispatch(WearAdvanceSessionEpoch(
      legacy: WearLegacyRuntimeSnapshot(
        logicalScreen: WearScreenId.status,
        sourceRevision: authority.state.legacy.sourceRevision + 1,
      ),
      payload: authority.state.payload,
    ));

    final WearDispatchResult stale = await authority.store.dispatch(
      WearGenericStatusElapsed(
        sessionEpoch: epoch,
        operationId: operationId,
      ),
    );

    expect(stale.accepted, isFalse);
    expect(stale.rejectReason, WearDispatchRejectReason.staleEpoch);
  });

  test('superseded generic status cannot navigate', () async {
    final WearRuntimeAuthority authority = WearRuntimeAuthority(
      initialScreen: WearScreenId.help,
    );
    addTearDown(authority.dispose);
    final int epoch = authority.state.sessionEpoch;
    final int first = authority.allocateOperationId();
    final int second = authority.allocateOperationId();

    await authority.store.dispatch(WearGenericStatusShown(
      sessionEpoch: epoch,
      operationId: first,
      expectedScreen: WearScreenId.help,
      args: _statusArgs(),
      completion: const WearStatusCompletion.goTo(WearScreenId.menu),
      deadline: DateTime.now().add(const Duration(seconds: 1)),
    ));
    await authority.store.dispatch(WearGenericStatusShown(
      sessionEpoch: epoch,
      operationId: second,
      expectedScreen: WearScreenId.status,
      args: _statusArgs(),
      completion: const WearStatusCompletion.goTo(WearScreenId.settings),
      deadline: DateTime.now().add(const Duration(seconds: 2)),
    ));

    final WearDispatchResult stale = await authority.store.dispatch(
      WearGenericStatusElapsed(sessionEpoch: epoch, operationId: first),
    );

    expect(stale.accepted, isFalse);
    expect(stale.rejectReason, WearDispatchRejectReason.staleOperation);
    expect(authority.payload.navigation.logicalScreen, WearScreenId.status);
    expect(
      WearRuntimePresentationSlice.from(authority.payload.presentation)
          .statusOperationId,
      second,
    );
  });

  test('passive status clears superseded scheduling metadata', () async {
    final WearRuntimeAuthority authority = WearRuntimeAuthority(
      initialScreen: WearScreenId.help,
    );
    addTearDown(authority.dispose);
    final int epoch = authority.state.sessionEpoch;
    final int scheduled = authority.allocateOperationId();

    await authority.store.dispatch(WearGenericStatusShown(
      sessionEpoch: epoch,
      operationId: scheduled,
      expectedScreen: WearScreenId.help,
      args: _statusArgs(),
      completion: const WearStatusCompletion.goTo(WearScreenId.menu),
      deadline: DateTime.now().add(const Duration(seconds: 1)),
    ));
    await authority.store.dispatch(WearGenericStatusShown(
      sessionEpoch: epoch,
      operationId: authority.allocateOperationId(),
      expectedScreen: WearScreenId.status,
      args: _statusArgs(),
      completion: const WearStatusCompletion.stay(),
      deadline: null,
    ));

    final WearRuntimePresentationSlice presentation =
        WearRuntimePresentationSlice.from(authority.payload.presentation);
    expect(presentation.statusOperationId, isNull);
    expect(presentation.statusDeadline, isNull);
    expect(
      authority.state.expectedOperationId(wearGenericStatusOperationKind),
      isNull,
    );
  });

  test('aggregate back clears generic status and its operation', () async {
    final WearRuntimeAuthority authority = WearRuntimeAuthority(
      initialScreen: WearScreenId.help,
    );
    addTearDown(authority.dispose);
    final int operationId = authority.allocateOperationId();
    await authority.store.dispatch(WearGenericStatusShown(
      sessionEpoch: authority.state.sessionEpoch,
      operationId: operationId,
      expectedScreen: WearScreenId.help,
      args: _statusArgs(),
      completion: const WearStatusCompletion.goTo(WearScreenId.menu),
      deadline: DateTime.now().add(const Duration(seconds: 1)),
    ));

    expect((await authority.back()).accepted, isTrue);

    expect(authority.payload.navigation.logicalScreen, WearScreenId.help);
    expect(
      WearRuntimePresentationSlice.from(authority.payload.presentation)
          .statusArgs,
      isNull,
    );
    expect(
      authority.state.expectedOperationId(wearGenericStatusOperationKind),
      isNull,
    );
  });

  test('clarification phone and glasses project committed aggregate', () async {
    final WearRuntimeAuthority authority = WearRuntimeAuthority(
      initialScreen: WearScreenId.menu,
    );
    addTearDown(authority.dispose);
    final VoiceClarificationArgs args = VoiceClarificationArgs(
      sourceScreen: WearScreenId.menu,
      phrase: 'товар',
      matches: const <VoiceDynamicItem>[
        VoiceDynamicItem(id: '1', label: 'Товар один'),
        VoiceDynamicItem(id: '2', label: 'Товар два'),
      ],
      sourceListRevision: 7,
    );

    await authority.store.dispatch(WearVoiceClarificationContextChanged(
      sessionEpoch: authority.state.sessionEpoch,
      expectedScreen: WearScreenId.menu,
      args: args,
    ));
    await authority.requestNavigation(WearScreenId.voiceClarification);
    await authority.store.dispatch(WearVoiceClarificationFocusChanged(
      sessionEpoch: authority.state.sessionEpoch,
      index: 1,
    ));

    final WearPhoneProjection phone =
        WearRuntimeProjection.projectPhone(authority.state);
    final WearGlassesEnvelope glasses =
        WearRuntimeProjection.projectGlasses(authority.state);
    expect(phone.items, <String>['Товар один', 'Товар два']);
    expect(phone.focusedIndex, 1);
    expect(glasses.payload.items, phone.items);
    expect(glasses.payload.selectedIndex, phone.focusedIndex);
  });

  test('production presentation paths dispatch aggregate intents', () {
    final String facade = File(
      'lib/modules/wear/application/wear_aggregate_presentation_flow_controller.dart',
    ).readAsStringSync();
    final String controller = File(
      'lib/modules/wear/application/wear_flow_controller.dart',
    ).readAsStringSync();
    final String projection = File(
      'lib/modules/wear/runtime/wear_runtime_projection.dart',
    ).readAsStringSync();

    expect(facade, contains('WearGenericStatusShown'));
    expect(facade, contains('WearRuntimePresentationScheduler'));
    expect(facade, contains('WearVoiceClarificationContextChanged'));
    expect(controller, contains('WearVoiceClarificationContextChanged'));
    expect(projection, contains('WearRuntimePresentationSlice.from'));
    expect(projection, contains('_voiceClarification'));
    expect(projection, contains('_genericStatus'));
  });
}

WearStatusScreenArgs _statusArgs() {
  return const WearStatusScreenArgs(
    kind: WearStatusKind.success,
    title: 'Готово',
    message: 'Операция завершена',
    details: 'Принтер 1',
    autoAction: WearStatusAutoAction.none,
  );
}
