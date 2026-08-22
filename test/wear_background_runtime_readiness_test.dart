import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_glasses/modules/wear/application/wear_background_runtime.dart';
import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/voice_utterance_coordinator.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/wear_voice_command.dart';
import 'package:smart_glasses/modules/wear/presentation/glasses/wear_glasses_payload.dart';

void main() {
  test('barcode waits until the target runtime screen is ready', () async {
    final _BlockingRuntime child = _BlockingRuntime(
      handledScreens: <WearScreenId>{WearScreenId.availabilityFill},
    )..blockNextEntry();
    final CompositeWearBackgroundRuntime runtime =
        CompositeWearBackgroundRuntime(<WearBackgroundRuntime>[child]);
    addTearDown(runtime.dispose);
    final List<WearBackgroundScreenUpdate> updates =
        <WearBackgroundScreenUpdate>[];
    final StreamSubscription<WearBackgroundScreenUpdate> subscription =
        runtime.updates.listen(updates.add);
    addTearDown(subscription.cancel);

    final Future<void> entry =
        runtime.enterScreen(WearScreenId.availabilityFill);
    await Future<void>.delayed(Duration.zero);

    expect(runtime.acceptsBarcode(WearScreenId.availabilityFill), isFalse);
    var completed = false;
    final Future<bool> barcode = runtime
        .handleBarcode(WearScreenId.availabilityFill, '4600000000001')
        .then((bool value) {
      completed = true;
      return value;
    });
    await Future<void>.delayed(Duration.zero);

    expect(completed, isFalse);
    expect(child.barcodes, isEmpty);

    child.completeBlockedEntry();
    await entry;
    expect(await barcode, isTrue);
    await Future<void>.delayed(Duration.zero);

    expect(runtime.acceptsBarcode(WearScreenId.availabilityFill), isTrue);
    expect(child.barcodes, <String>['4600000000001']);
    expect(updates.length, greaterThanOrEqualTo(2));
  });

  test('a newer non-runtime screen supersedes a pending runtime entry',
      () async {
    final _BlockingRuntime child = _BlockingRuntime(
      handledScreens: <WearScreenId>{WearScreenId.availabilityFill},
    )..blockNextEntry();
    final CompositeWearBackgroundRuntime runtime =
        CompositeWearBackgroundRuntime(<WearBackgroundRuntime>[child]);
    addTearDown(runtime.dispose);

    final Future<void> staleEntry =
        runtime.enterScreen(WearScreenId.availabilityFill);
    await Future<void>.delayed(Duration.zero);
    final Future<bool> staleBarcode =
        runtime.handleBarcode(WearScreenId.availabilityFill, 'stale');
    await Future<void>.delayed(Duration.zero);

    await runtime.enterScreen(WearScreenId.menu);
    child.completeBlockedEntry();
    await staleEntry;

    expect(await staleBarcode, isFalse);
    expect(runtime.acceptsBarcode(WearScreenId.availabilityFill), isFalse);
    expect(child.barcodes, isEmpty);
  });

  test('a non-runtime overlay keeps the ready source list available',
      () async {
    final _BlockingRuntime child = _BlockingRuntime(
      handledScreens: <WearScreenId>{WearScreenId.availabilityProduct},
    );
    final CompositeWearBackgroundRuntime runtime =
        CompositeWearBackgroundRuntime(<WearBackgroundRuntime>[child]);
    addTearDown(runtime.dispose);

    await runtime.enterScreen(WearScreenId.availabilityProduct);
    await runtime.enterScreen(WearScreenId.voiceClarification);

    expect(
      runtime
          .dynamicVoiceItemsFor(WearScreenId.availabilityProduct)
          .items
          .single
          .id,
      'product-1',
    );
    expect(
      await runtime.handleDynamicItem(
        WearScreenId.availabilityProduct,
        'product-1',
      ),
      isTrue,
    );
    expect(child.dynamicSelections, <String>['product-1']);
  });

  test('runtime-owned commands wait but global navigation does not', () async {
    final _BlockingRuntime child = _BlockingRuntime(
      handledScreens: <WearScreenId>{WearScreenId.availabilityProduct},
    )..blockNextEntry();
    final CompositeWearBackgroundRuntime runtime =
        CompositeWearBackgroundRuntime(<WearBackgroundRuntime>[child]);
    addTearDown(runtime.dispose);

    final Future<void> entry =
        runtime.enterScreen(WearScreenId.availabilityProduct);
    await Future<void>.delayed(Duration.zero);
    var selectCompleted = false;
    final Future<bool> select = runtime
        .handleCommand(
          WearScreenId.availabilityProduct,
          WearVoiceCommand.select,
        )
        .then((bool value) {
      selectCompleted = true;
      return value;
    });
    await Future<void>.delayed(Duration.zero);

    expect(selectCompleted, isFalse);
    expect(
      await runtime.handleCommand(
        WearScreenId.availabilityProduct,
        WearVoiceCommand.back,
      ),
      isFalse,
    );

    child.completeBlockedEntry();
    await entry;

    expect(await select, isTrue);
    expect(child.commands, <WearVoiceCommand>[WearVoiceCommand.select]);
  });
}

class _BlockingRuntime implements WearBackgroundRuntime {
  _BlockingRuntime({required this.handledScreens});

  final Set<WearScreenId> handledScreens;
  final StreamController<WearBackgroundScreenUpdate> _updates =
      StreamController<WearBackgroundScreenUpdate>.broadcast();
  final List<String> barcodes = <String>[];
  final List<String> dynamicSelections = <String>[];
  final List<WearVoiceCommand> commands = <WearVoiceCommand>[];

  Completer<void>? _entryBlocker;
  WearScreenId? _enteredScreen;

  void blockNextEntry() {
    if (_entryBlocker != null) {
      throw StateError('An entry is already blocked');
    }
    _entryBlocker = Completer<void>();
  }

  void completeBlockedEntry() {
    final Completer<void>? blocker = _entryBlocker;
    if (blocker == null || blocker.isCompleted) {
      throw StateError('No blocked entry to complete');
    }
    blocker.complete();
  }

  @override
  Stream<WearBackgroundScreenUpdate> get updates => _updates.stream;

  @override
  bool handles(WearScreenId screen) => handledScreens.contains(screen);

  @override
  bool acceptsBarcode(WearScreenId screen) => _enteredScreen == screen;

  @override
  bool supportsCommand(WearScreenId screen, WearVoiceCommand command) {
    return handles(screen) && command == WearVoiceCommand.select;
  }

  @override
  Future<void> enterScreen(WearScreenId screen, {Object? extra}) async {
    if (!handles(screen)) return;
    _updates.add(
      WearBackgroundScreenUpdate(
        screen: screen,
        payload: WearGlassesPayload.scanWaiting(),
      ),
    );
    final Completer<void>? blocker = _entryBlocker;
    if (blocker != null) {
      await blocker.future;
      if (identical(_entryBlocker, blocker)) _entryBlocker = null;
    }
    _enteredScreen = screen;
  }

  @override
  Future<bool> handleCommand(
    WearScreenId screen,
    WearVoiceCommand command,
  ) async {
    if (_enteredScreen != screen || !supportsCommand(screen, command)) {
      return false;
    }
    commands.add(command);
    return true;
  }

  @override
  Future<bool> handlePhrase(WearScreenId screen, String phrase) async {
    return _enteredScreen == screen;
  }

  @override
  Future<bool> handleDynamicItem(WearScreenId screen, String itemId) async {
    if (_enteredScreen != screen || itemId != 'product-1') return false;
    dynamicSelections.add(itemId);
    return true;
  }

  @override
  Future<bool> handleBarcode(WearScreenId screen, String barcode) async {
    if (_enteredScreen != screen) return false;
    barcodes.add(barcode);
    return true;
  }

  @override
  VoiceDynamicItemsSnapshot dynamicVoiceItemsFor(WearScreenId screen) {
    if (_enteredScreen != screen) return VoiceDynamicItemsSnapshot.empty;
    return const VoiceDynamicItemsSnapshot(
      revision: 1,
      items: <VoiceDynamicItem>[
        VoiceDynamicItem(id: 'product-1', label: 'Первый товар'),
      ],
    );
  }

  @override
  void restorePresentationState(WearScreenId screen, Object state) {}

  @override
  Object? presentationStateFor(WearScreenId screen) => null;

  @override
  Future<void> reset() async {
    _enteredScreen = null;
    final Completer<void>? blocker = _entryBlocker;
    if (blocker != null && !blocker.isCompleted) blocker.complete();
    _entryBlocker = null;
  }

  @override
  Future<void> dispose() async {
    await reset();
    await _updates.close();
  }
}
