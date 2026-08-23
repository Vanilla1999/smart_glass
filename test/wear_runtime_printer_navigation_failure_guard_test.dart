import 'dart:async';

import 'package:flutter_dotenv/flutter_dotenv.dart';
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
    dotenv.testLoad(fileInput: 'WEAR_USE_MOCKS=false');
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
    await _flush();
    await authority.selectPrinter(authority.printerTask.visiblePrinters.first);
    await authority.selectPrinter(authority.printerTask.visiblePrinters.last);
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

Future<void> _flush() async {
  for (int index = 0; index < 6; index++) {
    await Future<void>.delayed(Duration.zero);
  }
}
