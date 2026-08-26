import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_glasses/modules/wear/application/wear_aggregate_presentation_flow_controller.dart';
import 'package:smart_glasses/modules/wear/application/voice_clarification_args.dart';
import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/domain/auth/model/authenticated_user.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/wear_voice_command.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/voice_utterance_coordinator.dart';
import 'package:smart_glasses/modules/wear/infrastructure/noop_wear_glasses_output.dart';
import 'package:smart_glasses/modules/wear/infrastructure/noop_wear_navigation_output.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_authority.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_store.dart';

void main() {
  group('aggregate-owned phone presentation focus', () {
    test('touch commits aggregate before exposing compatibility focus',
        () async {
      final WearRuntimeAuthority authority = WearRuntimeAuthority(
        initialScreen: WearScreenId.menu,
      );
      final WearAggregatePresentationFlowController controller =
          _controller(authority);
      addTearDown(controller.dispose);

      final int before = authority.state.revision;
      expect(
        await controller.commitPresentationFocus(WearScreenId.menu, 2),
        isTrue,
      );

      expect(_focus(authority, WearScreenId.menu), 2);
      expect(controller.state.menuFocusedIndex, 2);
      expect(controller.state.focusedIndex, 2);
      expect(authority.state.revision, greaterThan(before));

      final int committedRevision = authority.state.revision;
      expect(
        await controller.commitPresentationFocus(WearScreenId.menu, 2),
        isTrue,
      );
      expect(authority.state.revision, committedRevision);
    });

    test('direct aggregate update is reflected by compatibility view',
        () async {
      final WearRuntimeAuthority authority = WearRuntimeAuthority(
        initialScreen: WearScreenId.menu,
      );
      final WearAggregatePresentationFlowController controller =
          _controller(authority);
      addTearDown(controller.dispose);

      final WearDispatchResult result = await authority.dispatchSemanticInput(
        kind: WearSemanticInputKind.presentationFocus,
        modality: WearInputModality.button,
        expectedScreen: WearScreenId.menu,
        expectedSessionEpoch: authority.state.sessionEpoch,
        focusIndex: 3,
      );

      expect(result.accepted, isTrue);
      expect(_focus(authority, WearScreenId.menu), 3);
      expect(controller.state.menuFocusedIndex, 3);
    });

    test('stale screen rejects focus and cannot navigate from stale selection',
        () async {
      final WearRuntimeAuthority authority = WearRuntimeAuthority(
        initialScreen: WearScreenId.menu,
      );
      final WearAggregatePresentationFlowController controller =
          _controller(authority);
      addTearDown(controller.dispose);

      await authority.requestNavigation(WearScreenId.help);
      final int revision = authority.state.revision;

      expect(
        await controller.commitPresentationFocus(WearScreenId.menu, 1),
        isFalse,
      );
      expect(authority.state.revision, revision);
      expect(authority.payload.navigation.logicalScreen, WearScreenId.help);
    });

    test('superseding focus prevents stale selection continuation', () async {
      final WearRuntimeAuthority authority = WearRuntimeAuthority(
        initialScreen: WearScreenId.menu,
      );
      final WearAggregatePresentationFlowController controller =
          _controller(authority);
      addTearDown(controller.dispose);

      bool superseded = false;
      final StreamSubscription<WearRuntimeState> subscription =
          authority.states.listen((WearRuntimeState state) {
        if (superseded || _focus(authority, WearScreenId.menu) != 1) return;
        superseded = true;
        unawaited(authority.dispatchSemanticInput(
          kind: WearSemanticInputKind.presentationFocus,
          modality: WearInputModality.button,
          expectedScreen: WearScreenId.menu,
          expectedSessionEpoch: state.sessionEpoch,
          focusIndex: 2,
        ));
      });
      addTearDown(subscription.cancel);

      expect(
        await controller.commitPresentationFocus(WearScreenId.menu, 1),
        isFalse,
      );
      expect(superseded, isTrue);
      expect(_focus(authority, WearScreenId.menu), 2);
      expect(authority.payload.navigation.logicalScreen, WearScreenId.menu);
    });

    test('same-screen epoch rollover rejects completed focus action', () async {
      final WearRuntimeAuthority authority = WearRuntimeAuthority(
        initialScreen: WearScreenId.menu,
      );
      final WearAggregatePresentationFlowController controller =
          _controller(authority);
      addTearDown(controller.dispose);

      bool advancedEpoch = false;
      final StreamSubscription<WearRuntimeState> subscription =
          authority.states.listen((WearRuntimeState state) {
        if (advancedEpoch || _focus(authority, WearScreenId.menu) != 2) return;
        advancedEpoch = true;
        unawaited(authority.store.dispatch(WearAdvanceSessionEpoch(
          legacy: WearLegacyRuntimeSnapshot(
            logicalScreen: WearScreenId.menu,
            sourceRevision: state.legacy.sourceRevision + 1,
          ),
          payload: state.payload,
        )));
      });
      addTearDown(subscription.cancel);

      expect(
        await controller.commitPresentationFocus(WearScreenId.menu, 2),
        isFalse,
      );
      expect(advancedEpoch, isTrue);
      expect(authority.state.sessionEpoch, 1);
      expect(authority.payload.navigation.logicalScreen, WearScreenId.menu);
    });

    test('voice and hardware buttons share committed aggregate focus',
        () async {
      final WearRuntimeAuthority authority = WearRuntimeAuthority(
        initialScreen: WearScreenId.menu,
      );
      final WearAggregatePresentationFlowController controller =
          _controller(authority);
      addTearDown(controller.dispose);
      final WearDispatchResult authorization = await authority.authorize(
        AuthenticatedUser(
          idUser: 1,
          idEmployee: 2,
          name: 'Test user',
        ),
      );
      expect(authorization.accepted, isTrue);
      expect(authority.payload.lifecycle.runtimeActive, isTrue);

      await controller.handleVoiceCommand(WearVoiceCommand.down);
      expect(_focus(authority, WearScreenId.menu), 1);
      expect(controller.state.menuFocusedIndex, 1);

      await controller.handleControllerCommand(WearVoiceCommand.down);
      expect(_focus(authority, WearScreenId.menu), 2);
      expect(controller.state.menuFocusedIndex, 2);

      await controller.handleVoiceCommand(WearVoiceCommand.select);
      expect(authority.payload.navigation.logicalScreen, WearScreenId.help);
    });

    test('inactive-phone clarification commands commit aggregate focus',
        () async {
      final WearRuntimeAuthority authority = WearRuntimeAuthority();
      final WearAggregatePresentationFlowController controller =
          _controller(authority);
      addTearDown(controller.dispose);
      await authority.authorize(
        AuthenticatedUser(idUser: 1, idEmployee: 2, name: 'Test user'),
      );
      const VoiceClarificationArgs args = VoiceClarificationArgs(
        sourceScreen: WearScreenId.availabilityProduct,
        phrase: 'товар',
        sourceListRevision: 1,
        matches: <VoiceDynamicItem>[
          VoiceDynamicItem(id: '1', label: 'Первый'),
          VoiceDynamicItem(id: '2', label: 'Второй'),
        ],
      );
      await controller.requestNavigation(
        WearScreenId.voiceClarification,
        extra: args,
      );

      await controller.handleVoiceCommand(WearVoiceCommand.down);

      expect(_focus(authority, WearScreenId.voiceClarification), 1);
      expect(controller.state.voiceClarificationFocusedIndex, 1);
    });
  });

  test('scoped phone screens cannot read legacy presentation state', () {
    const List<String> paths = <String>[
      'lib/modules/wear/presentation/screens/menu/wear_menu_screen.dart',
      'lib/modules/wear/presentation/screens/home/wear_home_confirm_screen.dart',
      'lib/modules/wear/presentation/screens/continue_scan/wear_continue_scan_screen.dart',
      'lib/modules/wear/presentation/screens/availability/wear_availability_interaction_screen.dart',
    ];

    for (final String path in paths) {
      final String source = File(path).readAsStringSync();
      expect(
        source,
        contains('WearRuntimeProjection.projectPhone'),
        reason: '$path must project phone state from the aggregate snapshot',
      );
      expect(
        source,
        contains('WearDependencies.I.authority'),
        reason: '$path must subscribe to the root runtime authority',
      );
      expect(
        source,
        isNot(contains('wear_flow_state.dart')),
        reason: '$path must not import legacy presentation state',
      );
      expect(
        source,
        isNot(contains('.stateStream')),
        reason: '$path must not subscribe to WearFlowController state',
      );
      expect(
        source,
        isNot(contains('.state.menuFocusedIndex')),
      );
      expect(
        source,
        isNot(contains('.state.homeConfirmFocusedIndex')),
      );
      expect(
        source,
        isNot(contains('.state.continueScanFocusedIndex')),
      );
      expect(
        source,
        isNot(contains('.state.availabilityInteractionFocusedIndex')),
      );
    }

    final String continueSource = File(
      'lib/modules/wear/presentation/screens/continue_scan/wear_continue_scan_screen.dart',
    ).readAsStringSync();
    expect(
      continueSource,
      isNot(contains('setState(() => _selectedButtonIndex = index)')),
      reason: 'continue-scan focus must render only from aggregate projection',
    );

    final String availabilitySource = File(
      'lib/modules/wear/presentation/screens/availability/wear_availability_interaction_screen.dart',
    ).readAsStringSync();
    expect(
      availabilitySource,
      isNot(contains('setState(() => _focusedIndex = itemIndex)')),
      reason: 'availability focus must render only from aggregate projection',
    );
  });

  test('production DI installs aggregate-first presentation facade', () {
    final String source = File(
      'lib/modules/wear/config/wear_dependencies.dart',
    ).readAsStringSync();

    expect(source, contains('WearAggregatePresentationFlowController'));
    expect(
      source,
      isNot(contains('wearFlowController = WearFlowController(')),
    );
  });
}

WearAggregatePresentationFlowController _controller(
  WearRuntimeAuthority authority,
) {
  return WearAggregatePresentationFlowController(
    glassesOutput: NoopWearGlassesOutput(),
    navigationOutput: NoopWearNavigationOutput(),
    authority: authority,
  );
}

int _focus(WearRuntimeAuthority authority, WearScreenId screen) {
  final WearPresentationFocusSlice presentation =
      authority.payload.presentation as WearPresentationFocusSlice;
  return presentation.focusFor(screen) ?? 0;
}
