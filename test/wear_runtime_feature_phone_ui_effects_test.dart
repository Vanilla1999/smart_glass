import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/domain/price_tag_print/model/barcode_product_info.dart';
import 'package:smart_glasses/modules/wear/models/wear_printer.dart';
import 'package:smart_glasses/modules/wear/models/wear_printer_selection.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_authority.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_phone_feature_projection.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_scan_slice.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_store.dart';

void main() {
  group('aggregate scan phone projection', () {
    test('projection is a pure immutable read of committed scan state',
        () async {
      final WearRuntimeAuthority authority = WearRuntimeAuthority(
        initialScreen: WearScreenId.scanIdle,
      );
      addTearDown(authority.dispose);

      final int revision = authority.state.revision;
      final WearScanPhoneProjection first =
          WearScanPhoneProjection.fromState(authority.state);
      final WearScanPhoneProjection second =
          WearScanPhoneProjection.fromState(authority.state);

      expect(first.version, authority.state.version);
      expect(first.logicalScreen, WearScreenId.scanIdle);
      expect(first.phase, WearScanTaskPhase.waiting);
      expect(first.products, isEmpty);
      expect(second.version, first.version);
      expect(authority.state.revision, revision);
      expect(() => first.products.add(_product(99)), throwsUnsupportedError);
    });
  });

  group('manual barcode UI effect', () {
    test('availability screen admits one bounded manual input effect',
        () async {
      final WearRuntimeAuthority authority = WearRuntimeAuthority(
        initialScreen: WearScreenId.availabilityFill,
      );
      addTearDown(authority.dispose);

      final WearDispatchResult first = await authority.dispatchSemanticInput(
        kind: WearSemanticInputKind.requestUiEffect,
        modality: WearInputModality.touch,
        expectedScreen: WearScreenId.availabilityFill,
        uiEffectKind: WearUiEffectKind.manualBarcodeInput,
      );
      final WearDispatchResult duplicate =
          await authority.dispatchSemanticInput(
        kind: WearSemanticInputKind.requestUiEffect,
        modality: WearInputModality.touch,
        expectedScreen: WearScreenId.availabilityFill,
        uiEffectKind: WearUiEffectKind.manualBarcodeInput,
      );

      expect(first.accepted, isTrue);
      expect(duplicate.rejectReason, WearDispatchRejectReason.duplicate);
      expect(authority.payload.uiEffects.effects, hasLength(1));
    });

    test('duplicate request remains one bounded pending effect', () async {
      final WearRuntimeAuthority authority = WearRuntimeAuthority(
        initialScreen: WearScreenId.scanIdle,
      );
      addTearDown(authority.dispose);

      final WearDispatchResult first = await _requestManualInput(authority);
      final WearDispatchResult duplicate = await _requestManualInput(authority);

      expect(first.accepted, isTrue);
      expect(duplicate.accepted, isFalse);
      expect(duplicate.rejectReason, WearDispatchRejectReason.duplicate);
      expect(authority.payload.uiEffects.effects, hasLength(1));
    });

    test('inactive phone cannot claim pending effect', () async {
      final WearRuntimeAuthority authority = WearRuntimeAuthority(
        initialScreen: WearScreenId.scanIdle,
      );
      addTearDown(authority.dispose);
      await _requestManualInput(authority);
      final WearUiEffect effect = authority.payload.uiEffects.effects.single;

      final WearDispatchResult claim = await authority.claimUiEffect(effect);

      expect(claim.accepted, isFalse);
      expect(claim.rejectReason, WearDispatchRejectReason.busy);
      expect(
        authority.payload.uiEffects.effects.single.status,
        WearUiEffectStatus.pending,
      );
    });

    test('claimed completion removes effect and starts one scan lookup',
        () async {
      final WearRuntimeAuthority authority = WearRuntimeAuthority(
        initialScreen: WearScreenId.scanIdle,
      );
      addTearDown(authority.dispose);
      await authority.setPhoneUiActive(true);
      await authority.store.dispatch(
        WearPrinterSelectionImported(_selection()),
      );
      await _requestManualInput(authority);
      final WearUiEffect effect = authority.payload.uiEffects.effects.single;
      expect((await authority.claimUiEffect(effect)).accepted, isTrue);

      final WearDispatchResult completed =
          await authority.completeUiEffect(effect, value: ' 4601234567890 ');

      expect(completed.accepted, isTrue);
      expect(completed.scheduledEffectCount, 1);
      expect(authority.payload.uiEffects.effects, isEmpty);
      expect(authority.scanTask.phase, WearScanTaskPhase.lookingUp);
      expect(authority.scanTask.barcode, '4601234567890');
      expect(
        authority.state.expectedOperationId(
          WearLookupBarcodeEffect.operationKind,
        ),
        isNotNull,
      );
    });

    test('cancel and empty completion retire effect without lookup', () async {
      final WearRuntimeAuthority authority = WearRuntimeAuthority(
        initialScreen: WearScreenId.scanIdle,
      );
      addTearDown(authority.dispose);
      await authority.setPhoneUiActive(true);

      await _requestManualInput(authority);
      WearUiEffect effect = authority.payload.uiEffects.effects.single;
      await authority.claimUiEffect(effect);
      expect((await authority.cancelUiEffect(effect)).accepted, isTrue);
      expect(authority.payload.uiEffects.effects, isEmpty);
      expect(authority.scanTask.phase, WearScanTaskPhase.waiting);

      await _requestManualInput(authority);
      effect = authority.payload.uiEffects.effects.single;
      await authority.claimUiEffect(effect);
      expect(
        (await authority.completeUiEffect(effect, value: '   ')).accepted,
        isTrue,
      );
      expect(authority.payload.uiEffects.effects, isEmpty);
      expect(authority.scanTask.phase, WearScanTaskPhase.waiting);
    });

    test('old epoch completion is rejected and cannot start lookup', () async {
      final WearRuntimeAuthority authority = WearRuntimeAuthority(
        initialScreen: WearScreenId.scanIdle,
      );
      addTearDown(authority.dispose);
      await authority.setPhoneUiActive(true);
      await _requestManualInput(authority);
      final WearUiEffect effect = authority.payload.uiEffects.effects.single;
      await authority.claimUiEffect(effect);

      await authority.store.dispatch(WearAdvanceSessionEpoch(
        legacy: WearLegacyRuntimeSnapshot(
          logicalScreen: WearScreenId.scanIdle,
          sourceRevision: authority.state.legacy.sourceRevision + 1,
        ),
        payload: authority.state.payload,
      ));
      final WearDispatchResult stale =
          await authority.completeUiEffect(effect, value: '123');

      expect(stale.accepted, isFalse);
      expect(stale.rejectReason, WearDispatchRejectReason.staleEpoch);
      expect(authority.scanTask.phase, WearScanTaskPhase.waiting);
    });
  });

  test('scan phone screens do not read feature streams or route snapshots', () {
    final String idle = File(
      'lib/modules/wear/presentation/screens/scan/wear_scan_idle_screen.dart',
    ).readAsStringSync();
    final String selection = File(
      'lib/modules/wear/presentation/screens/scan/wear_product_select_screen.dart',
    ).readAsStringSync();
    final String routes = File(
      'lib/modules/wear/navigation/wear_routes.dart',
    ).readAsStringSync();

    for (final String source in <String>[idle, selection]) {
      expect(source, contains('WearScanPhoneProjection.fromState'));
      expect(source, contains('WearDependencies.I.authority'));
      expect(source, isNot(contains('wear_scan_runtime.dart')));
      expect(source, isNot(contains('.stateStream')));
    }
    expect(idle, contains('WearUiEffectKind.manualBarcodeInput'));
    expect(idle, contains('claimUiEffect'));
    expect(idle, contains('completeUiEffect'));
    expect(idle, isNot(contains('wearFlowController.handleBarcode')));
    expect(idle, isNot(contains('_isManualInputOpen')));

    expect(selection, isNot(contains('WearProductSelectArgs')));
    expect(selection, isNot(contains('widget.args')));
    expect(selection, isNot(contains('_focusedIndex = itemIndex')));
    expect(routes, contains('return const WearScanIdleScreen();'));
    expect(routes, contains('return const WearProductSelectScreen();'));
    expect(routes, isNot(contains('state.extra is WearProductSelectArgs')));
    expect(routes, isNot(contains('state.extra is WearPrinterSelection')));
  });

  test('scan status gives aggregate task precedence over route args', () {
    final String source = File(
      'lib/modules/wear/presentation/screens/status/wear_status_screen.dart',
    ).readAsStringSync();

    expect(source, contains('WearScanPhoneProjection.fromState'));
    expect(source, contains('WearRuntimePresentationSlice.from'));
    expect(
        source, contains('final WearStatusScreenArgs? args = aggregateStatus'));
    expect(source, isNot(contains('aggregateStatus ?? widget.args')));
    expect(source, contains('projection.phase == WearScanTaskPhase.status'));
  });
}

Future<WearDispatchResult> _requestManualInput(
  WearRuntimeAuthority authority,
) {
  return authority.dispatchSemanticInput(
    kind: WearSemanticInputKind.requestUiEffect,
    modality: WearInputModality.touch,
    expectedScreen: WearScreenId.scanIdle,
    expectedSessionEpoch: authority.state.sessionEpoch,
    uiEffectKind: WearUiEffectKind.manualBarcodeInput,
  );
}

WearPrinterSelection _selection() {
  return const WearPrinterSelection(
    whitePrinter: WearPrinter(id: 'white', name: 'Белый'),
    yellowPrinter: WearPrinter(id: 'yellow', name: 'Жёлтый'),
  );
}

BarcodeProductInfo _product(int id) {
  return BarcodeProductInfo(id: id, name: 'Товар $id');
}
