import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_authority.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_control_adapter.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_store.dart';
import 'package:smart_glasses/modules/wear/services/wear_scanner_runtime_policy.dart';

void main() {
  group('aggregate route observation boundary', () {
    test('phone route observation never changes logical screen', () async {
      final WearRuntimeAuthority authority = WearRuntimeAuthority(
        initialScreen: WearScreenId.menu,
      );
      addTearDown(authority.dispose);
      final WearRuntimeNavigationAdapter adapter =
          authority.navigationAdapter();

      final WearDispatchResult receipt =
          await adapter.observePhoneRoute(WearScreenId.help);

      expect(receipt.accepted, isTrue);
      expect(
        authority.payload.navigation.logicalScreen,
        WearScreenId.menu,
      );
      expect(
        authority.payload.navigation.actualPhoneScreen,
        WearScreenId.help,
      );
    });

    test('old route adapter cannot observe or acknowledge a new epoch',
        () async {
      final WearRuntimeAuthority authority = WearRuntimeAuthority(
        initialScreen: WearScreenId.menu,
      );
      addTearDown(authority.dispose);
      final WearRuntimeNavigationAdapter oldAdapter =
          authority.navigationAdapter();

      final WearDispatchResult advanced =
          await authority.store.dispatch(WearAdvanceSessionEpoch(
        legacy: WearLegacyRuntimeSnapshot(
          logicalScreen: WearScreenId.menu,
          sourceRevision: authority.state.legacy.sourceRevision + 1,
        ),
        payload: authority.state.payload,
      ));
      expect(advanced.accepted, isTrue);

      final WearDispatchResult stale =
          await oldAdapter.observePhoneRoute(WearScreenId.help);
      expect(stale.accepted, isFalse);
      expect(stale.rejectReason, WearDispatchRejectReason.staleEpoch);
      expect(authority.payload.navigation.actualPhoneScreen, isNull);
    });
  });

  group('pre-auth main scanner admission', () {
    test('matching aggregate route prepares and admits badge scanner', () async {
      final WearRuntimeAuthority authority = WearRuntimeAuthority(
        initialScreen: WearScreenId.main,
      );
      addTearDown(authority.dispose);
      final WearRuntimeNavigationAdapter navigation =
          authority.navigationAdapter();
      final WearRuntimeControlAdapter controls =
          WearRuntimeControlAdapter(authority);

      expect((await authority.setRuntimeActive(true)).accepted, isTrue);
      expect((await authority.setPhoneUiActive(true)).accepted, isTrue);
      expect(
        (await navigation.observePhoneRoute(WearScreenId.main)).accepted,
        isTrue,
      );

      final WearScannerRuntimeDecision beforeHardware =
          resolveWearScannerDecisionFromState(
        authority.state,
        currentScreenAcceptsBarcode: true,
      );
      expect(beforeHardware.hardwarePrepared, isTrue);
      expect(beforeHardware.barcodeAdmissionEnabled, isFalse);

      expect((await controls.observeScannerPreparing()).accepted, isTrue);
      expect((await controls.observeScannerPrepared()).accepted, isTrue);
      expect(
        (await controls.evaluateScannerAdmission(
          logicalScreen: WearScreenId.main,
          screenAcceptsBarcode: true,
        ))
            .accepted,
        isTrue,
      );

      expect(authority.controls.scanner.hardwarePrepared, isTrue);
      expect(authority.controls.scanner.barcodeAdmissionEnabled, isTrue);
      expect(
        authority.controls.scanner.expectedLogicalScreen,
        WearScreenId.main,
      );
    });

    test('route drift keeps pre-auth badge admission closed', () async {
      final WearRuntimeAuthority authority = WearRuntimeAuthority(
        initialScreen: WearScreenId.main,
      );
      addTearDown(authority.dispose);
      final WearRuntimeNavigationAdapter navigation =
          authority.navigationAdapter();
      final WearRuntimeControlAdapter controls =
          WearRuntimeControlAdapter(authority);

      await authority.setRuntimeActive(true);
      await authority.setPhoneUiActive(true);
      await navigation.observePhoneRoute(WearScreenId.help);
      await controls.observeScannerPreparing();
      await controls.observeScannerPrepared();
      await controls.evaluateScannerAdmission(
        logicalScreen: WearScreenId.main,
        screenAcceptsBarcode: true,
      );

      expect(authority.controls.scanner.barcodeAdmissionEnabled, isFalse);
      expect(
        resolveWearScannerDecisionFromState(
          authority.state,
          currentScreenAcceptsBarcode: true,
        ).barcodeAdmissionEnabled,
        isFalse,
      );
    });

    test('inactive runtime closes pre-auth preparation and admission', () async {
      final WearRuntimeAuthority authority = WearRuntimeAuthority(
        initialScreen: WearScreenId.main,
      );
      addTearDown(authority.dispose);
      final WearRuntimeNavigationAdapter navigation =
          authority.navigationAdapter();
      final WearRuntimeControlAdapter controls =
          WearRuntimeControlAdapter(authority);

      await authority.setRuntimeActive(true);
      await authority.setPhoneUiActive(true);
      await navigation.observePhoneRoute(WearScreenId.main);
      await controls.observeScannerPreparing();
      await controls.observeScannerPrepared();
      await controls.evaluateScannerAdmission(
        logicalScreen: WearScreenId.main,
        screenAcceptsBarcode: true,
      );
      expect(authority.controls.scanner.barcodeAdmissionEnabled, isTrue);

      await authority.setRuntimeActive(false);
      final WearScannerRuntimeDecision decision =
          resolveWearScannerDecisionFromState(
        authority.state,
        currentScreenAcceptsBarcode: true,
      );
      expect(decision.hardwarePrepared, isFalse);
      expect(decision.barcodeAdmissionEnabled, isFalse);
    });

    test('old scanner adapter cannot admit a barcode after epoch rollover',
        () async {
      final WearRuntimeAuthority authority = WearRuntimeAuthority(
        initialScreen: WearScreenId.main,
      );
      addTearDown(authority.dispose);
      final WearRuntimeControlAdapter oldControls =
          WearRuntimeControlAdapter(authority);

      await authority.store.dispatch(WearAdvanceSessionEpoch(
        legacy: WearLegacyRuntimeSnapshot(
          logicalScreen: WearScreenId.main,
          sourceRevision: authority.state.legacy.sourceRevision + 1,
        ),
        payload: authority.state.payload,
      ));

      final WearDispatchResult stale =
          await oldControls.acceptBarcodeDelivery(
        deliveryId: 1,
        logicalScreen: WearScreenId.main,
      );
      expect(stale.accepted, isFalse);
      expect(stale.rejectReason, WearDispatchRejectReason.staleEpoch);
    });
  });

  test('production presentation cannot start a business screen lifecycle', () {
    final Directory presentation = Directory(
      'lib/modules/wear/presentation',
    );
    final List<File> dartFiles = presentation
        .listSync(recursive: true)
        .whereType<File>()
        .where((File file) => file.path.endsWith('.dart'))
        .toList(growable: false);

    for (final File file in dartFiles) {
      final String source = file.readAsStringSync();
      expect(
        source,
        isNot(contains('.enterScreen(')),
        reason:
            '${file.path} must observe aggregate navigation instead of entering business state',
      );
    }
  });

  test('module orchestration uses aggregate logical and actual navigation', () {
    final String source = File(
      'lib/modules/wear/presentation/widgets/wear_module_app.dart',
    ).readAsStringSync();

    expect(source, isNot(contains('wear_flow_state.dart')));
    expect(source, isNot(contains('_flow.stateStream')));
    expect(source, isNot(contains('flow.state.screen')));
    expect(source, isNot(contains('_flow.state.screen')));
    expect(source, isNot(contains('flow.observeRoute(')));
    expect(source, contains('authority.payload.navigation.logicalScreen'));
    expect(source, contains('navigationAdapter()'));
    expect(source, contains('adapter.observePhoneRoute(screen)'));
    expect(source, contains('payload.navigation.pending'));
    expect(source, contains('StreamBuilder<WearRuntimeState>'));
  });

  test('barcode and voice production wiring capture aggregate screen', () {
    final String dispatcher = File(
      'lib/modules/wear/services/wear_barcode_dispatcher.dart',
    ).readAsStringSync();
    final String dependencies = File(
      'lib/modules/wear/config/wear_dependencies.dart',
    ).readAsStringSync();

    expect(dispatcher, contains('_authority.payload.navigation.logicalScreen'));
    expect(dispatcher, contains('expectedSessionEpoch: sessionEpoch'));
    expect(dispatcher, isNot(contains('_flowController.state.screen')));
    expect(
      dependencies,
      contains('screenProvider: () => authority.payload.navigation.logicalScreen'),
    );
    expect(
      dependencies,
      contains('WearBarcodeDispatcher(\n      authority: authority,'),
    );
  });

  test('help, status and auth widgets do not publish canonical glasses state',
      () {
    const List<String> paths = <String>[
      'lib/modules/wear/presentation/screens/help/wear_help_screen.dart',
      'lib/modules/wear/presentation/screens/status/wear_status_screen.dart',
      'lib/modules/wear/presentation/screens/main/wear_main_screen.dart',
    ];
    for (final String path in paths) {
      final String source = File(path).readAsStringSync();
      expect(
        source,
        isNot(contains('publishScreenPayload')),
        reason: '$path must render from the aggregate projection pipeline',
      );
    }
  });
}
