import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_glasses/modules/wear/application/wear_aggregate_presentation_flow_controller.dart';
import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/wear_voice_command.dart';
import 'package:smart_glasses/modules/wear/infrastructure/noop_wear_glasses_output.dart';
import 'package:smart_glasses/modules/wear/infrastructure/noop_wear_navigation_output.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_authority.dart';

void main() {
  group('aggregate-owned phone presentation focus', () {
    test('touch commits aggregate before exposing compatibility focus', () async {
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

    test('direct aggregate update is reflected by compatibility view', () async {
      final WearRuntimeAuthority authority = WearRuntimeAuthority(
        initialScreen: WearScreenId.menu,
      );
      final WearAggregatePresentationFlowController controller =
          _controller(authority);
      addTearDown(controller.dispose);

      final result = await authority.dispatchSemanticInput(
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

    test('voice and hardware buttons share committed aggregate focus', () async {
      final WearRuntimeAuthority authority = WearRuntimeAuthority(
        initialScreen: WearScreenId.menu,
      );
      final WearAggregatePresentationFlowController controller =
          _controller(authority);
      addTearDown(controller.dispose);
      await authority.setRuntimeActive(true);

      await controller.handleVoiceCommand(WearVoiceCommand.down);
      expect(_focus(authority, WearScreenId.menu), 1);
      expect(controller.state.menuFocusedIndex, 1);

      await controller.handleControllerCommand(WearVoiceCommand.down);
      expect(_focus(authority, WearScreenId.menu), 2);
      expect(controller.state.menuFocusedIndex, 2);

      await controller.handleVoiceCommand(WearVoiceCommand.select);
      expect(authority.payload.navigation.logicalScreen, WearScreenId.help);
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
