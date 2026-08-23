import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/application/wear_status_state.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/status/wear_status_args.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_authority.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_presentation_slice.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_store.dart';

void main() {
  test('focus update preserves aggregate status presentation fields', () {
    final WearStatusScreenArgs args = _statusArgs();
    final WearRuntimePresentationSlice presentation =
        WearRuntimePresentationSlice(
      focusedIndices: const <WearScreenId, int>{WearScreenId.menu: 2},
      statusArgs: args,
      statusCompletion:
          const WearStatusCompletion.goTo(WearScreenId.menu),
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
