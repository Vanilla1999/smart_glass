import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('controller production input attribution cannot read legacy screen', () {
    final String source = File(
      'lib/modules/wear/application/wear_flow_controller.dart',
    ).readAsStringSync();

    expect(source, contains('WearScreenId get _logicalScreen'));
    expect(
      source,
      isNot(contains(
        '_commandQueue.add((command: command, expectedScreen: _state.screen))',
      )),
    );
    expect(
      source,
      isNot(contains('runtime.handleCommand(_state.screen, command)')),
    );
    expect(
      source,
      isNot(contains('runtime.handlePhrase(_state.screen, trimmed)')),
    );
    expect(
      source,
      isNot(contains('_invokeScreenPhrase(_state.screen, trimmed)')),
    );
    expect(
      source,
      isNot(contains('_invokeScreenPartialPhrase(_state.screen, trimmed)')),
    );
    expect(
      source,
      contains('final WearScreenId sourceScreen = _logicalScreen;'),
    );
    expect(
      source,
      contains('final WearScreenId screen = _logicalScreen;'),
    );
  });

  test('voice dispatcher attributes events to aggregate navigation', () {
    final String source = File(
      'lib/modules/wear/application/wear_voice_application_dispatcher.dart',
    ).readAsStringSync();

    expect(source, isNot(contains('_flow.state.screen')));
    expect(
      source,
      contains('_flow.authority.payload.navigation.logicalScreen'),
    );
  });

  test('unsupported barcode fallback is bounded to anonymous main', () {
    final String source = File(
      'lib/modules/wear/services/wear_barcode_dispatcher.dart',
    ).readAsStringSync();

    expect(
      source,
      contains(
        'semanticReceipt.rejectReason != WearDispatchRejectReason.unsupported',
      ),
    );
    expect(source, contains('_authority.isAuthorized'));
    expect(source, contains('screen != WearScreenId.main'));
    expect(source, contains('expectedSessionEpoch: sessionEpoch'));
    expect(source, contains('controls.expectedLogicalScreen != screen'));
  });

  test('temporary source-patching workflow is absent from final tree', () {
    expect(
      File('.github/workflows/apply-wear-s11-review-fixes.yml').existsSync(),
      isFalse,
    );
  });
}
