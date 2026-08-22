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
import 'package:smart_glasses/modules/wear/config/wear_session.dart';
import 'package:smart_glasses/modules/wear/domain/availability/model/wear_availability_group.dart';
import 'package:smart_glasses/modules/wear/domain/availability/model/wear_availability_product.dart';
import 'package:smart_glasses/modules/wear/domain/availability/repository/wear_availability_repository.dart';
import 'package:smart_glasses/modules/wear/domain/availability/use_case/wear_availability_flow_use_case.dart';
import 'package:smart_glasses/modules/wear/domain/price_tag_print/model/available_printer.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/voice_utterance_coordinator.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/wear_voice_command.dart';
import 'package:smart_glasses/modules/wear/presentation/glasses/wear_glasses_payload.dart';

void main() {
  setUp(() {
    dotenv.testLoad(fileInput: 'WEAR_USE_MOCKS=false');
    WearSession.clearPrinterSelection();
  });

  tearDown(WearSession.clearPrinterSelection);

  group('runtime-owned barcode routing', () {
    test('active UI routes a migrated barcode to runtime exactly once',
        () async {
      final _RecordingRuntime runtime = _RecordingRuntime(
        handledScreens: <WearScreenId>{WearScreenId.availabilityFill},
      );
      final WearFlowController controller = _controller();
      controller.setBackgroundRuntime(runtime);
      addTearDown(controller.dispose);
      controller.setUiLifecycle(WearUiLifecycle.active);
      controller.enterScreen(WearScreenId.availabilityFill);
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
      final WearFlowController controller = _controller();
      controller.setBackgroundRuntime(runtime);
      addTearDown(controller.dispose);
      controller.setUiLifecycle(WearUiLifecycle.active);
      controller.enterScreen(WearScreenId.main);
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
      final WearFlowController controller = _controller();
      controller.setBackgroundRuntime(runtime);
      addTearDown(controller.dispose);
      controller.setUiLifecycle(WearUiLifecycle.active);
      controller.enterScreen(WearScreenId.availabilityProduct);
      const VoiceClarificationArgs args = VoiceClarificationArgs(
        sourceScreen: WearScreenId.availabilityProduct,
        phrase: 'второй',
        sourceListRevision: 7,
        matches: <VoiceDynamicItem>[item],
      );
      controller.enterScreen(WearScreenId.voiceClarification, extra: args);

      expect(await controller.selectVoiceClarificationItem(args, '2'), isTrue);

      expect(runtime.dynamicSelections, <String>['2']);
      expect(controller.state.screen, WearScreenId.availabilityProduct);
    });
  });

  group('availability runtime stabilization', () {
    test('duplicate barcode publishes the duplicate list to glasses', () async {
      final _DuplicateAvailabilityRepository repository =
          _DuplicateAvailabilityRepository();
      final WearAvailabilityRuntime runtime = _availabilityRuntime(
        repository: repository,
      );
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
  });

  test('printer reload invalidates a disappeared white printer', () async {
    var loadCount = 0;
    final WearPrinterRuntime runtime = WearPrinterRuntime(
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
    addTearDown(runtime.dispose);
    await runtime.enterScreen(WearScreenId.printerSelect);
    await runtime.selectPrinter(runtime.state.printers.first);
    await runtime.selectPrinter(runtime.state.visiblePrinters.first);
    expect(WearSession.printerSelectionOrNull, isNotNull);

    await runtime.load();

    expect(runtime.state.whitePrinter, isNull);
    expect(runtime.state.selection, isNull);
    expect(runtime.state.step, WearPrinterRuntimeStep.white);
    expect(WearSession.printerSelectionOrNull, isNull);
  });
}

WearFlowController _controller() {
  return WearFlowController(
    glassesOutput: _FakeGlassesOutput(),
    navigationOutput: _FakeNavigationOutput(),
  );
}

WearAvailabilityRuntime _availabilityRuntime({
  required WearAvailabilityRepository repository,
  WearAvailabilityFillAdd? fillAdd,
  WearAvailabilityFillReset? fillReset,
}) {
  return WearAvailabilityRuntime(
    flowUseCase: WearAvailabilityFlowUseCase(repository),
    navigate: (
      WearScreenId _, {
      Object? extra,
      bool replaceCurrent = false,
    }) async {},
    capturePhoto: () async {},
    printPriceTag: (_) async => 'printer',
    fillAdd: fillAdd,
    fillReset: fillReset,
  );
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

class _DuplicateAvailabilityRepository
    implements WearAvailabilityRepository {
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
    photoControl: false,
    unpackaged: false,
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
