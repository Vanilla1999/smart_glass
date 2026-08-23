import 'dart:async';
import 'dart:collection';

import 'package:multi_scanner/multi_scanner.dart';
import 'package:smart_glasses/modules/wear/application/wear_flow_controller.dart';
import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_control_adapter.dart';

typedef WearBarcodeHandler = Future<bool> Function(String payload);
class WearBarcodeSerialQueue {
  WearBarcodeSerialQueue({
    required WearBarcodeHandler handleBarcode,
    this.maxPending = 32,
  })  : assert(maxPending > 0),
        _handleBarcode = handleBarcode;

  final WearBarcodeHandler _handleBarcode;
  final int maxPending;
  final Queue<_QueuedBarcode> _pending = Queue<_QueuedBarcode>();

  bool _draining = false;
  int _generation = 0;

  int get pendingCount => _pending.length;

  bool add(String payload) {
    return addWithHandler(payload, _handleBarcode);
  }

  bool addWithHandler(String payload, WearBarcodeHandler handler) {
    final String value = payload.trim();
    if (value.isEmpty || _pending.length >= maxPending) return false;
    _pending.addLast(_QueuedBarcode(value, handler));
    _ensureDrain();
    return true;
  }

  void reset() {
    _generation += 1;
    _pending.clear();
  }

  Future<void> waitUntilIdle() async {
    while (_draining || _pending.isNotEmpty) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  void _ensureDrain() {
    if (_draining || _pending.isEmpty) return;
    _draining = true;
    final int generation = _generation;
    unawaited(
      _drain(generation).whenComplete(() {
        _draining = false;
        if (_pending.isNotEmpty) _ensureDrain();
      }),
    );
  }

  Future<void> _drain(int generation) async {
    while (generation == _generation && _pending.isNotEmpty) {
      final _QueuedBarcode delivery = _pending.removeFirst();
      try {
        final bool consumed = await delivery.handler(delivery.payload);
        if (!consumed) {
          print(
            '[WearBarcodeDispatcher] barcode not consumed: ${delivery.payload}',
          );
        }
      } catch (error, stackTrace) {
        print('[WearBarcodeDispatcher] barcode error=$error\n$stackTrace');
      }
    }
  }
}

class _QueuedBarcode {
  const _QueuedBarcode(this.payload, this.handler);

  final String payload;
  final WearBarcodeHandler handler;
}

class WearBarcodeDispatcher implements MultiScannerDelegate {
  WearBarcodeDispatcher({
    required WearFlowController flowController,
    MultiScanner? scanner,
  })  : _flowController = flowController,
        _scanner = scanner ?? MultiScanner.last();

  final WearFlowController _flowController;
  final MultiScanner _scanner;
  late final WearBarcodeSerialQueue _queue = WearBarcodeSerialQueue(
    handleBarcode: (String _) async => false,
  );
  bool _started = false;
  int _nextDeliveryId = 0;
  WearRuntimeControlAdapter? _controlAdapter;

  void start() {
    if (_started) return;
    _controlAdapter = WearRuntimeControlAdapter(_flowController.authority);
    _scanner.addDelegate(this);
    _started = true;
  }

  void stop() {
    if (!_started) return;
    _scanner.removeDelegate(this);
    _started = false;
    _controlAdapter = null;
    _queue.reset();
  }

  void resetPending() => _queue.reset();

  @override
  bool? onScanEvent(String payload) {
    final controls = _flowController.authority.controls.scanner;
    if (!_started || !controls.barcodeAdmissionEnabled) {
      return false;
    }
    final WearRuntimeControlAdapter? callback = _controlAdapter;
    if (callback == null) return false;
    final WearScreenId screen = _flowController.state.screen;
    final int deliveryId = ++_nextDeliveryId;
    final bool accepted = _queue.addWithHandler(
      payload,
      (String value) => _deliverBarcode(
        value,
        callback: callback,
        screen: screen,
        deliveryId: deliveryId,
      ),
    );
    if (!accepted) {
      print(
        '[WearBarcodeDispatcher] barcode queue rejected payload '
        'pending=${_queue.pendingCount}',
      );
    }
    return accepted;
  }

  @override
  bool? onErrorScan(Exception error) => false;

  Future<bool> _deliverBarcode(
    String payload, {
    required WearRuntimeControlAdapter callback,
    required WearScreenId screen,
    required int deliveryId,
  }) async {
    final receipt = await callback.acceptBarcodeDelivery(
      deliveryId: deliveryId,
      logicalScreen: screen,
    );
    if (!receipt.accepted) return false;
    return _flowController.handleBarcode(payload);
  }
}
