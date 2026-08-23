import 'dart:async';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_glasses/modules/wear/application/ports/wear_glasses_output.dart';
import 'package:smart_glasses/modules/wear/application/ports/wear_navigation_output.dart';
import 'package:smart_glasses/modules/wear/application/voice_clarification_args.dart';
import 'package:smart_glasses/modules/wear/application/wear_availability_runtime.dart';
import 'package:smart_glasses/modules/wear/application/wear_background_runtime.dart';
import 'package:smart_glasses/modules/wear/application/wear_flow_controller.dart';
import 'package:smart_glasses/modules/wear/application/wear_navigation_entry.dart';
import 'package:smart_glasses/modules/wear/application/wear_printer_runtime.dart';
import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/application/wear_ui_lifecycle.dart';
import 'package:smart_glasses/modules/wear/config/wear_dependencies.dart';
import 'package:smart_glasses/modules/wear/domain/auth/model/authenticated_user.dart';
import 'package:smart_glasses/modules/wear/domain/availability/model/wear_availability_flow_state.dart';
import 'package:smart_glasses/modules/wear/domain/availability/model/wear_availability_group.dart';
import 'package:smart_glasses/modules/wear/domain/availability/model/wear_availability_product.dart';
import 'package:smart_glasses/modules/wear/domain/availability/repository/wear_availability_repository.dart';
import 'package:smart_glasses/modules/wear/domain/availability/use_case/wear_availability_flow_use_case.dart';
import 'package:smart_glasses/modules/wear/domain/price_tag_print/model/available_printer.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/voice_utterance_coordinator.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/wear_voice_command.dart';
import 'package:smart_glasses/modules/wear/presentation/glasses/wear_glasses_payload.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_authority.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_printer_authority.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    dotenv.testLoad(fileInput: 'WEAR_USE_MOCKS=false');
    WearDependencies.I.authority.clearPrinterSelection();
  });

  tearDown(() => WearDependencies.I.authority.clearPrinterSelection());

  group('runtime-owned barcode routing', () {
    test('active UI routes a migrated barcode to runtime exactly once',
        () async {
      final _RecordingRuntime runtime = _RecordingRuntime(
        handledScreens: <WearScreenId>{WearScreenId.availabilityFill},
      );
      final WearRuntimeAuthority authority = await _activeAuthority();
      final WearFlowController controller = _controller(authority);
      controller.setBackgroundRuntime(runtime);
      addTearDown(controller.dispose);
      controller.setUiLifecycle(WearUiLifecycle.active);
      await controller.requestNavigation(WearScreenId.availabilityFill);
      var legacyCalls = 0;
      controller.registerScreenActions(
        WearScreenId.availabilityFill,
        WearScreenActionHandler(onBarcode: (_) {
          legacyCalls++;
        }),
      );

      expect(await controller.handleBarcode(' 4600000000001 '), isTrue);

      expect(runtime.barcodes, <String>[' 4600000000001 ']);
      expect(legacyCalls, 0);
    });

    test('active UI keeps the legacy auth barcode fallback', () async {
      final _RecordingRuntime runtime = _RecordingRuntime(
        handledScreens: <WearScreenId>{WearScreenId.availabilityFill},
      );
      final WearRuntimeAuthority authority = await _activeAuthority();
      final WearFlowController controller = _controller(authority);
      controller.setBackgroundRuntime(runtime);
      addTearDown(controller.dispose);
      controller.setUiLifecycle(WearUiLifecycle.active);
      await controller.requestNavigation(WearScreenId.main);
      String? received;
      controller.registerScreenActions(
        WearScreenId.main,
        WearScreenActionHandler(
          onBarcode: (String barcode) {
            received = barcode;
          },
          barcodeEnabled: () => true,
        ),
      );

      expect(await controller.handleBarcode('badge'), isTrue);

      expect(received, 'badge');
      expect(runtime.barcodes, isEmpty);
    });

    test('active clarification selects an item through its source runtime',
        () async {
      const VoiceDynamicItem item = VoiceDynamicItem(
        id: '2',
        label: 'Второй товар',
      );
      const VoiceDynamicItemsSnapshot items = VoiceDynamicItemsSnapshot(
        revision: 7,
        items: <VoiceDynamicItem>[item],
      );
      final _RecordingRuntime runtime = _RecordingRuntime(
        handledScreens: <WearScreenId>{WearScreenId.availabilityProduct},
        items: items,
      );
      final WearRuntimeAuthority authority = await _activeAuthority();
      final WearFlowController controller = _controller(authority);
      controller.setBackgroundRuntime(runtime);
      addTearDown(controller.dispose);
      controller.setUiLifecycle(WearUiLifecycle.active);
      await controller.requestNavigation(WearScreenId.availabilityProduct);
      const VoiceClarificationArgs args = VoiceClarificationArgs(
        sourceScreen: WearScreenId.availabilityProduct,
        phrase: 'второй',
        sourceListRevision: 7,
        matches: <VoiceDynamicItem>[item],
      );
      await controller.requestNavigation(
        WearScreenId.voiceClarification,
        extra: args,
      );

      expect(await controller.selectVoiceClarificationItem(args, '2'), isTrue);

      expect(runtime.dynamicSelections, <String>['2']);
      expect(controller.state.screen, WearScreenId.availabilityProduct);
    });
  });

  group('availability runtime stabilization', () {
    test('duplicate barcode publishes the duplicate list to glasses', () async {
      final _DuplicateAvailabilityRepository repository =
          _DuplicateAvailabilityRepository();
      final WearRuntimeAuthority authority = WearRuntimeAuthority(
        initialScreen: WearScreenId.availabilityDirectScan,
      );
      final WearAvailabilityRuntime runtime = _availabilityRuntime(
        repository: repository,
        authority: authority,
      );
      addTearDown(authority.dispose);
      addTearDown(runtime.dispose);
      final List<WearBackgroundScreenUpdate> updates =
          <WearBackgroundScreenUpdate>[];
      final StreamSubscription<WearBackgroundScreenUpdate> subscription =
          runtime.updates.listen(updates.add);
      addTearDown(subscription.cancel);
      await runtime.enterScreen(WearScreenId.availabilityDirectScan);

      expect(
        await runtime.handleBarcode(
          WearScreenId.availabilityDirectScan,
          _DuplicateAvailabilityRepository.barcode,
        ),
        isTrue,
      );
      await _flush();

      final WearGlassesPayload payload = updates.last.payload;
      expect(payload.title, 'Дубль ШК');
      expect(payload.phase, WearGlassesPhase.idle);
      expect(payload.items, <String>['Первый товар', 'Второй товар']);
      expect(
        runtime.supportsCommand(
          WearScreenId.availabilityDirectScan,
          WearVoiceCommand.select,
        ),
        isTrue,
      );
      expect(
        await runtime.handleBarcode(
          WearScreenId.availabilityDirectScan,
          '4600000000099',
        ),
        isFalse,
      );
      expect(repository.barcodeCalls, 1);
    });

    test('barcode dedupe resets when the runtime screen changes', () async {
      final _DuplicateAvailabilityRepository repository =
          _DuplicateAvailabilityRepository();
      var fillCalls = 0;
      final WearAvailabilityRuntime runtime = _availabilityRuntime(
        repository: repository,
        fillAdd: (String barcode) async {
          fillCalls++;
          return const <WearAvailabilityProduct>[
            _DuplicateAvailabilityRepository.first,
          ];
        },
      );
      addTearDown(runtime.dispose);
      await runtime.enterScreen(WearScreenId.availabilityDirectScan);
      await runtime.handleBarcode(
        WearScreenId.availabilityDirectScan,
        _DuplicateAvailabilityRepository.barcode,
      );

      await runtime.enterScreen(WearScreenId.availabilityFill);
      expect(
        await runtime.handleBarcode(
          WearScreenId.availabilityFill,
          _DuplicateAvailabilityRepository.barcode,
        ),
        isTrue,
      );

      expect(repository.barcodeCalls, 1);
      expect(fillCalls, 1);
      expect(runtime.state.savedCount, 1);
    });

    test('stale fill result cannot update a newer availability screen',
        () async {
      final Completer<List<WearAvailabilityProduct>> fill =
          Completer<List<WearAvailabilityProduct>>();
      final WearAvailabilityRuntime runtime = _availabilityRuntime(
        repository: _DuplicateAvailabilityRepository(),
        fillAdd: (_) => fill.future,
      );
      addTearDown(runtime.dispose);
      await runtime.enterScreen(WearScreenId.availabilityFill);

      final Future<bool> scan = runtime.handleBarcode(
        WearScreenId.availabilityFill,
        _DuplicateAvailabilityRepository.barcode,
      );
      await Future<void>.delayed(Duration.zero);
      expect(runtime.state.busy, isTrue);

      await runtime.enterScreen(WearScreenId.availabilityGroup);
      fill.complete(const <WearAvailabilityProduct>[
        _DuplicateAvailabilityRepository.first,
      ]);

      expect(await scan, isTrue);
      expect(runtime.state.busy, isFalse);
      expect(runtime.state.savedCount, 0);
      expect(runtime.state.error, isNull);
    });

    test('direct scan does not advertise list commands before duplicates',
        () async {
      final WearAvailabilityRuntime runtime = _availabilityRuntime(
        repository: _DuplicateAvailabilityRepository(),
      );
      addTearDown(runtime.dispose);
      await runtime.enterScreen(WearScreenId.availabilityDirectScan);

      expect(
        runtime.supportsCommand(
          WearScreenId.availabilityDirectScan,
          WearVoiceCommand.select,
        ),
        isFalse,
      );
      expect(
        runtime.supportsCommand(
          WearScreenId.availabilityDirectScan,
          WearVoiceCommand.down,
        ),
        isFalse,
      );
    });

    test('empty lists neither advertise nor consume list commands', () async {
      final WearAvailabilityRuntime runtime = _availabilityRuntime(
        repository: _DuplicateAvailabilityRepository(),
      );
      addTearDown(runtime.dispose);
      await runtime.enterScreen(WearScreenId.availabilityGroup);

      expect(
        runtime.supportsCommand(
          WearScreenId.availabilityGroup,
          WearVoiceCommand.select,
        ),
        isFalse,
      );
      expect(
        await runtime.handleCommand(
          WearScreenId.availabilityGroup,
          WearVoiceCommand.select,
        ),
        isFalse,
      );
    });

    test('fill clear commands are advertised and executed by runtime',
        () async {
      var resetCalls = 0;
      final WearAvailabilityRuntime runtime = _availabilityRuntime(
        repository: _DuplicateAvailabilityRepository(),
        fillReset: () async {
          resetCalls++;
        },
      );
      addTearDown(runtime.dispose);
      await runtime.enterScreen(WearScreenId.availabilityFill);

      expect(
        runtime.supportsCommand(
          WearScreenId.availabilityFill,
          WearVoiceCommand.down,
        ),
        isTrue,
      );
      expect(
        runtime.supportsCommand(
          WearScreenId.availabilityFill,
          WearVoiceCommand.clear,
        ),
        isTrue,
      );
      expect(
        runtime.supportsCommand(
          WearScreenId.availabilityFill,
          WearVoiceCommand.select,
        ),
        isFalse,
      );

      expect(
        await runtime.handleCommand(
          WearScreenId.availabilityFill,
          WearVoiceCommand.down,
        ),
        isTrue,
      );
      expect(resetCalls, 1);
    });

    test('fill reset blocks scanner input until repository reset completes',
        () async {
      final Completer<void> reset = Completer<void>();
      var fillCalls = 0;
      final WearAvailabilityRuntime runtime = _availabilityRuntime(
        repository: _DuplicateAvailabilityRepository(),
        fillAdd: (_) async {
          fillCalls++;
          return const <WearAvailabilityProduct>[
            _DuplicateAvailabilityRepository.first,
          ];
        },
        fillReset: () => reset.future,
      );
      addTearDown(runtime.dispose);
      await runtime.enterScreen(WearScreenId.availabilityFill);
      await runtime.handleBarcode(
        WearScreenId.availabilityFill,
        _DuplicateAvailabilityRepository.barcode,
      );
      expect(runtime.state.savedCount, 1);

      final Future<void> resetting = runtime.resetFill();
      await Future<void>.delayed(Duration.zero);

      expect(runtime.state.busy, isTrue);
      expect(runtime.acceptsBarcode(WearScreenId.availabilityFill), isFalse);
      expect(
        await runtime.handleBarcode(
          WearScreenId.availabilityFill,
          '4600000000099',
        ),
        isFalse,
      );
      expect(fillCalls, 1);

      reset.complete();
      await resetting;

      expect(runtime.state.busy, isFalse);
      expect(runtime.state.savedCount, 0);
      expect(runtime.state.message, 'База сканированной полки очищена');
    });

    test('stale photo error cannot overwrite a newer screen', () async {
      final Completer<void> photo = Completer<void>();
      final WearRuntimeAuthority authority = WearRuntimeAuthority(
        initialScreen: WearScreenId.availabilityCheck,
      );
      final WearAvailabilityRuntime runtime = _availabilityRuntime(
        repository: _DuplicateAvailabilityRepository(),
        capturePhoto: () => photo.future,
        authority: authority,
      );
      addTearDown(authority.dispose);
      addTearDown(runtime.dispose);
      await runtime.enterScreen(
        WearScreenId.availabilityCheck,
        extra: _DuplicateAvailabilityRepository.first,
      );
      await _flush();
      expect(runtime.answerAvailable(true), isTrue);
      await _flush();

      final Future<void> capture = runtime.takePhoto();
      await _flush();
      expect(runtime.state.busy, isTrue);

      await runtime.enterScreen(WearScreenId.availabilityGroup);
      photo.completeError(Exception('stale photo failure'));
      await capture;

      expect(runtime.state.busy, isFalse);
      expect(runtime.state.error, isNull);
    });
  });

  group('printer reload reconciliation', () {
    test('reload invalidates a disappeared white printer', () async {
      var loadCount = 0;
      final WearRuntimeAuthority authority = WearRuntimeAuthority();
      final WearPrinterRuntime runtime = WearPrinterRuntime(
        authority: authority,
        loadPrinters: () async {
          loadCount++;
          if (loadCount == 1) {
            return <AvailablePrinter>[
              AvailablePrinter(number: 'a', name: 'Белый A'),
              AvailablePrinter(number: 'b', name: 'Жёлтый B'),
            ];
          }
          return <AvailablePrinter>[
            AvailablePrinter(number: 'b', name: 'Жёлтый B'),
            AvailablePrinter(number: 'c', name: 'Мобильный C'),
          ];
        },
        navigate: (
          WearScreenId _, {
          Object? extra,
          bool replaceCurrent = false,
        }) async {},
      );
      addTearDown(authority.dispose);
      addTearDown(runtime.dispose);
      await runtime.enterScreen(WearScreenId.printerSelect);
      await _flush();
      await runtime.selectPrinter(runtime.state.printers.first);
      await runtime.selectPrinter(runtime.state.visiblePrinters.first);
      expect(authority.features.printer.selection, isNotNull);

      await authority.requestNavigation(WearScreenId.printerSelect);
      await runtime.load();
      await _flush();

      expect(runtime.state.whitePrinter, isNull);
      expect(runtime.state.selection, isNull);
      expect(runtime.state.step, WearPrinterRuntimeStep.white);
      expect(authority.features.printer.selection, isNull);
    });

    test('reload keeps a valid pair and refreshes printer models', () async {
      var loadCount = 0;
      final WearRuntimeAuthority authority = WearRuntimeAuthority();
      final WearPrinterRuntime runtime = WearPrinterRuntime(
        authority: authority,
        loadPrinters: () async {
          loadCount++;
          return <AvailablePrinter>[
            AvailablePrinter(
              number: 'a',
              name: loadCount == 1 ? 'Белый A' : 'Белый A обновлённый',
            ),
            AvailablePrinter(
              number: 'b',
              name: loadCount == 1 ? 'Жёлтый B' : 'Жёлтый B обновлённый',
            ),
          ];
        },
        navigate: (
          WearScreenId _, {
          Object? extra,
          bool replaceCurrent = false,
        }) async {},
      );
      addTearDown(authority.dispose);
      addTearDown(runtime.dispose);
      await runtime.enterScreen(WearScreenId.printerSelect);
      await _flush();
      await runtime.selectPrinter(runtime.state.printers.first);
      await runtime.selectPrinter(runtime.state.visiblePrinters.first);

      await authority.requestNavigation(WearScreenId.printerSelect);
      await runtime.load();
      await _flush();

      expect(runtime.state.selection?.whitePrinter.name, 'Белый A обновлённый');
      expect(
          runtime.state.selection?.yellowPrinter.name, 'Жёлтый B обновлённый');
      expect(runtime.state.step, WearPrinterRuntimeStep.yellow);
      expect(authority.features.printer.selection?.whitePrinter.name,
          'Белый A обновлённый');
      expect(authority.features.printer.selection?.yellowPrinter.name,
          'Жёлтый B обновлённый');
    });

    test('reload keeps white and requests yellow again when yellow disappears',
        () async {
      var loadCount = 0;
      final WearRuntimeAuthority authority = WearRuntimeAuthority();
      final WearPrinterRuntime runtime = WearPrinterRuntime(
        authority: authority,
        loadPrinters: () async {
          loadCount++;
          if (loadCount == 1) {
            return <AvailablePrinter>[
              AvailablePrinter(number: 'a', name: 'Белый A'),
              AvailablePrinter(number: 'b', name: 'Жёлтый B'),
            ];
          }
          return <AvailablePrinter>[
            AvailablePrinter(number: 'a', name: 'Белый A'),
            AvailablePrinter(number: 'c', name: 'Жёлтый C'),
          ];
        },
        navigate: (
          WearScreenId _, {
          Object? extra,
          bool replaceCurrent = false,
        }) async {},
      );
      addTearDown(authority.dispose);
      addTearDown(runtime.dispose);
      await runtime.enterScreen(WearScreenId.printerSelect);
      await _flush();
      await runtime.selectPrinter(runtime.state.printers.first);
      await runtime.selectPrinter(runtime.state.visiblePrinters.first);

      await authority.requestNavigation(WearScreenId.printerSelect);
      await runtime.load();
      await _flush();

      expect(runtime.state.whitePrinter?.id, 'a');
      expect(runtime.state.selection, isNull);
      expect(runtime.state.step, WearPrinterRuntimeStep.yellow);
      expect(authority.features.printer.selection, isNull);
      expect(runtime.state.visiblePrinters.single.id, 'c');
    });
  });
}

WearFlowController _controller(WearRuntimeAuthority authority) {
  return WearFlowController(
    authority: authority,
    glassesOutput: _FakeGlassesOutput(),
    navigationOutput: _FakeNavigationOutput(),
  );
}

Future<WearRuntimeAuthority> _activeAuthority() async {
  final WearRuntimeAuthority authority = WearRuntimeAuthority(
    initialScreen: WearScreenId.scannerConnect,
  );
  await authority.authorize(
    AuthenticatedUser(idUser: 1, idEmployee: 2, name: 'Test User'),
  );
  await authority.setRuntimeActive(true);
  return authority;
}

WearAvailabilityRuntime _availabilityRuntime({
  required WearAvailabilityRepository repository,
  WearRuntimeAuthority? authority,
  WearAvailabilityFillAdd? fillAdd,
  WearAvailabilityFillReset? fillReset,
  WearAvailabilityPhotoCapture? capturePhoto,
}) {
  return WearAvailabilityRuntime(
    authority: authority,
    flowUseCase: WearAvailabilityFlowUseCase(repository),
    navigate: (
      WearScreenId _, {
      Object? extra,
      bool replaceCurrent = false,
    }) async {},
    capturePhoto: capturePhoto ?? () async {},
    printPriceTag: (_) async => 'printer',
    fillAdd: fillAdd,
    fillReset: fillReset,
  );
}

Future<void> _flush() async {
  for (int index = 0; index < 6; index++) {
    await Future<void>.delayed(Duration.zero);
  }
}

class _FakeGlassesOutput implements WearGlassesOutput {
  @override
  Future<void> send(WearGlassesPayload payload) async {}
}

class _FakeNavigationOutput implements WearNavigationOutput {
  @override
  Future<void> back() async {}

  @override
  Future<void> goTo(WearScreenId screen, {Object? extra}) async {}

  @override
  Future<void> home() async {}

  @override
  Future<void> replace(WearScreenId screen, {Object? extra}) async {}

  @override
  Future<void> synchronize(List<WearNavigationEntry> history) async {}
}

class _RecordingRuntime implements WearBackgroundRuntime {
  _RecordingRuntime({
    required this.handledScreens,
    this.items,
  });

  final Set<WearScreenId> handledScreens;
  final VoiceDynamicItemsSnapshot? items;
  final List<String> barcodes = <String>[];
  final List<String> dynamicSelections = <String>[];
  final StreamController<WearBackgroundScreenUpdate> _updates =
      StreamController<WearBackgroundScreenUpdate>.broadcast();

  @override
  Stream<WearBackgroundScreenUpdate> get updates => _updates.stream;

  @override
  bool acceptsBarcode(WearScreenId screen) => handles(screen);

  @override
  Future<void> dispose() => _updates.close();

  @override
  VoiceDynamicItemsSnapshot dynamicVoiceItemsFor(WearScreenId screen) {
    return items ?? VoiceDynamicItemsSnapshot.empty;
  }

  @override
  Future<void> enterScreen(WearScreenId screen, {Object? extra}) async {}

  @override
  Future<bool> handleBarcode(WearScreenId screen, String barcode) async {
    if (!handles(screen)) return false;
    barcodes.add(barcode);
    return true;
  }

  @override
  Future<bool> handleCommand(
    WearScreenId screen,
    WearVoiceCommand command,
  ) async {
    return false;
  }

  @override
  Future<bool> handleDynamicItem(WearScreenId screen, String itemId) async {
    if (!handles(screen)) return false;
    dynamicSelections.add(itemId);
    return true;
  }

  @override
  Future<bool> handlePhrase(WearScreenId screen, String phrase) async {
    return false;
  }

  @override
  bool handles(WearScreenId screen) => handledScreens.contains(screen);

  @override
  Object? presentationStateFor(WearScreenId screen) => null;

  @override
  Future<void> reset() async {}

  @override
  void restorePresentationState(WearScreenId screen, Object state) {}

  @override
  bool supportsCommand(WearScreenId screen, WearVoiceCommand command) => false;
}

class _DuplicateAvailabilityRepository implements WearAvailabilityRepository {
  static const String barcode = '4600000000010';
  static const WearAvailabilityProduct first = WearAvailabilityProduct(
    id: 1,
    groupId: 1,
    name: 'Первый товар',
    code: barcode,
    barcodes: <String>[barcode],
    priceTagBarcodes: <String>[],
    price: 10,
    rest: 1,
    checkPrice: false,
    photoControl: true,
    unpackaged: true,
    priceTagActual: true,
  );
  static const WearAvailabilityProduct second = WearAvailabilityProduct(
    id: 2,
    groupId: 1,
    name: 'Второй товар',
    code: '4600000000011',
    barcodes: <String>[barcode],
    priceTagBarcodes: <String>[],
    price: 20,
    rest: 2,
    checkPrice: false,
    photoControl: false,
    unpackaged: false,
    priceTagActual: true,
  );

  int barcodeCalls = 0;

  @override
  Future<void> completeProduct(int productId) async {}

  @override
  Future<List<WearAvailabilityProduct>> findProductsByBarcode(
    String barcode,
  ) async {
    barcodeCalls++;
    return const <WearAvailabilityProduct>[first, second];
  }

  @override
  Future<List<WearAvailabilityGroup>> getGroups() async {
    return const <WearAvailabilityGroup>[];
  }

  @override
  Future<List<WearAvailabilityProduct>> getProductsByGroup(int groupId) async {
    return const <WearAvailabilityProduct>[];
  }

  @override
  Future<void> resetCompletedProducts() async {}

  @override
  Future<void> resetScannedProducts() async {}

  @override
  Future<WearAvailabilityProduct> upsertScannedProduct({
    required int articleId,
    required String name,
    required String barcode,
    double? rest,
  }) async {
    return first;
  }
}
