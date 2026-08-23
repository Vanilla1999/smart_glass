import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/domain/auth/model/authenticated_user.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_authority.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_core_slices.dart';

void main() {
  test('session clear publishes a new-epoch replace navigation to main',
      () async {
    final WearRuntimeAuthority authority = WearRuntimeAuthority(
      initialScreen: WearScreenId.settings,
    );
    addTearDown(authority.dispose);

    expect(
      (await authority.authorize(AuthenticatedUser(
        idUser: 1,
        idEmployee: 2,
        name: 'Test user',
      )))
          .accepted,
      isTrue,
    );
    final int authorizedEpoch = authority.state.sessionEpoch;

    final result = await authority.clearSession();

    expect(result.accepted, isTrue);
    expect(authority.state.sessionEpoch, authorizedEpoch + 1);
    expect(authority.payload.navigation.logicalScreen, WearScreenId.main);
    expect(authority.payload.navigation.history, <WearScreenId>[WearScreenId.main]);
    final WearPendingNavigation? pending =
        authority.payload.navigation.pending;
    expect(pending, isNotNull);
    expect(pending!.screen, WearScreenId.main);
    expect(pending.kind, WearPendingNavigationKind.replace);
  });

  test('business phone widgets cannot route around aggregate navigation', () {
    const List<String> paths = <String>[
      'lib/modules/wear/presentation/widgets/wear_screen_scaffold.dart',
      'lib/modules/wear/presentation/screens/main/wear_main_screen.dart',
      'lib/modules/wear/presentation/screens/main/wear_scanner_connect_screen.dart',
      'lib/modules/wear/presentation/screens/home/wear_home_confirm_screen.dart',
      'lib/modules/wear/presentation/screens/help/wear_help_screen.dart',
      'lib/modules/wear/presentation/screens/continue_scan/wear_continue_scan_screen.dart',
      'lib/modules/wear/presentation/screens/settings/wear_settings_screen.dart',
      'lib/modules/wear/presentation/screens/settings/wear_wifi_settings_screen.dart',
      'lib/modules/wear/presentation/screens/settings/wear_printer_settings_screen.dart',
      'lib/modules/wear/presentation/screens/voice/wear_voice_clarification_screen.dart',
    ];

    for (final String path in paths) {
      final String source = File(path).readAsStringSync();
      expect(
        source,
        isNot(contains('context.go(')),
        reason: '$path must request aggregate navigation before phone routing',
      );
      expect(
        source,
        isNot(contains('context.pop(')),
        reason: '$path must request aggregate back before phone routing',
      );
      expect(
        source,
        isNot(contains('context.pushReplacement(')),
        reason: '$path must not replace a business route directly',
      );
    }
  });

  test('home scaffold dispatches home confirmation into the runtime', () {
    final String source = File(
      'lib/modules/wear/presentation/widgets/wear_screen_scaffold.dart',
    ).readAsStringSync();

    expect(
      source,
      contains('.requestNavigation(WearScreenId.homeConfirm)'),
    );
    expect(source, isNot(contains('WearHomeConfirmScreen.route')));
  });

  test('continue touch actions commit focus before aggregate navigation', () {
    final String source = File(
      'lib/modules/wear/presentation/screens/continue_scan/wear_continue_scan_screen.dart',
    ).readAsStringSync();

    expect(source, contains('commitPresentationFocus'));
    expect(source, contains('WearScreenId.scanIdle'));
    expect(source, contains('WearScreenId.menu'));
    expect(source, contains('replaceCurrent: true'));
  });
}
