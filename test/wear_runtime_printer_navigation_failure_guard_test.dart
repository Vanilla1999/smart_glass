import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/domain/auth/model/authenticated_user.dart';
import 'package:smart_glasses/modules/wear/domain/price_tag_print/model/available_printer.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_authority.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_printer_effects.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_printer_slice.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_store.dart';

void main() {
  test('late navigation failure cannot write printer error on another screen',
      () async {
    final Completer<void> navigation = Completer<void>();
    final WearRuntimeAuthority authority = WearRuntimeAuthority();
    addTearDown(authority.dispose);
    authority.registerEffectExecutor(
      WearPrinterEffectExecutor(
        loadPrinters: () async => <AvailablePrinter>[
          AvailablePrinter(number: 'white', name: 'White'),
          AvailablePrinter(number: 'yellow', name: 'Yellow'),
        ],
        navigate: (_, {extra, replaceCurrent = false}) => navigation.future,
      ),
    );
    await authority.authorize(
      AuthenticatedUser(idUser: 1, idEmployee: 2, name: 'User'),
    );
    await authority.enterPrinterScreen();
    await Future<void>.delayed(Duration.zero);
    await authority.selectPrinterById('white');
    await authority.selectPrinterById('yellow');
    final int operationId = authority.state.expectedOperationId(
      WearNavigateAfterPrinterSelectionEffect.navigationOperationKind,
    )!;
    await authority.requestNavigation(WearScreenId.menu);

    final WearDispatchResult result = await authority.store.dispatch(
      WearPrinterNavigationFailed(
        sessionEpoch: authority.state.sessionEpoch,
        operationId: operationId,
        message: 'late failure',
      ),
    );

    expect(result.accepted, isFalse);
    expect(result.rejectReason, WearDispatchRejectReason.staleScreen);
    expect(authority.printerTask.error, isNull);
    navigation.complete();
  });
}
