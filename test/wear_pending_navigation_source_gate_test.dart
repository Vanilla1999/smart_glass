import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('controller delivers and acknowledges aggregate pending navigation', () {
    final String source = File(
      'lib/modules/wear/application/wear_flow_controller.dart',
    ).readAsStringSync();

    expect(
      source,
      contains(
        'final WearPendingNavigation? pending =\n        _authority.payload.navigation.pending;',
      ),
    );
    expect(
      source,
      contains('final WearNavigationRequest? legacyRequest = _state.pendingNavigation;'),
    );
    expect(
      source,
      contains('navigation acknowledged request=\$pending'),
    );
    expect(
      source,
      isNot(contains(
        'final WearNavigationRequest? request = _state.pendingNavigation;\n    if (request == null || _uiLifecycle',
      )),
    );
  });

  test('logout caller flushes aggregate replace-to-main request', () {
    final String source = File(
      'lib/modules/wear/presentation/screens/settings/wear_settings_screen.dart',
    ).readAsStringSync();

    expect(source, contains('authority.clearSession()'));
    expect(source, contains('_flow.flushPendingNavigation()'));
  });
}
