import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:multi_scanner/src/bluetooth/battary_state.dart';
import 'package:multi_scanner/src/bluetooth/bt_device.dart';
import 'package:multi_scanner/src/bluetooth/multi_scanner_bluetooth.dart';
import 'package:multi_scanner/src/platform/multi_scanner_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class FakeMultiScannerPlatform extends MultiScannerPlatform
    with MockPlatformInterfaceMixin {
  final initBluetoothCall = Completer<void>();

  @override
  Stream<List<BTDevice>> get streamOnBTFound => const Stream.empty();

  @override
  Stream<List<BTDevice>> get streamOnBTBound => const Stream.empty();

  @override
  Stream<String> get barcodeStream => const Stream.empty();

  @override
  Stream<List<BattaryState>> get battaryStream => const Stream.empty();

  @override
  Stream<BTDevice?> get connectionStateStream => const Stream.empty();

  @override
  Stream<BTDevice?> get isBoundingStream => const Stream.empty();

  @override
  BTDevice? get currentConnectionBT => null;

  @override
  BTDevice? get currentIsBoundingBT => null;

  @override
  Future<void> initBluetooth() => initBluetoothCall.future;
}

void main() {
  test('init waits for platform Bluetooth initialization', () async {
    final platform = FakeMultiScannerPlatform();
    MultiScannerPlatform.instance = platform;
    var completed = false;

    final initialization = MultiScannerBluetooth().init().then((_) {
      completed = true;
    });
    await Future<void>.delayed(Duration.zero);

    expect(completed, isFalse);

    platform.initBluetoothCall.complete();
    await initialization;
    expect(completed, isTrue);
  });
}
