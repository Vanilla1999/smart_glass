import 'package:flutter_test/flutter_test.dart';
import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/models/wear_printer.dart';
import 'package:smart_glasses/modules/wear/models/wear_printer_selection.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_authority.dart';

import 'support/wear_runtime_test_helper.dart';

void main() {
  test('scan capability closes as soon as lookup becomes busy', () async {
    final WearRuntimeAuthority authority =
        await createActiveWearRuntimeAuthority(
      initialScreen: WearScreenId.scanIdle,
    );
    addTearDown(authority.dispose);
    await authority.importPrinterSelection(
      const WearPrinterSelection(
        whitePrinter: WearPrinter(id: 'white', name: 'White'),
        yellowPrinter: WearPrinter(id: 'yellow', name: 'Yellow'),
      ),
    );

    expect(selectWearBarcodeCapability(authority.state), isTrue);

    final result = await authority.dispatchSemanticInput(
      kind: WearSemanticInputKind.barcode,
      modality: WearInputModality.barcode,
      expectedScreen: WearScreenId.scanIdle,
      value: 'habr',
    );

    expect(result.accepted, isTrue);
    expect(authority.scanTask.phase, WearScanTaskPhase.lookingUp);
    expect(selectWearBarcodeCapability(authority.state), isFalse);
  });

  test('non-barcode screen is never aggregate-capable', () async {
    final WearRuntimeAuthority authority =
        await createActiveWearRuntimeAuthority(
      initialScreen: WearScreenId.menu,
    );
    addTearDown(authority.dispose);

    expect(selectWearBarcodeCapability(authority.state), isFalse);
  });
}
