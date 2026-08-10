import 'dart:async';
import 'dart:collection';

import 'package:multi_scanner/multi_scanner.dart';
import 'package:smart_glasses/modules/wear/application/wear_flow_controller.dart';

typedef WearBarcodeHandler = Future<bool> Function(String payload);
typedef WearBarcodeClock = DateTime Function();

class WearBarcodeSerialQueue {
  WearBarcodeSerialQueue({
    required WearBarcodeHandler handleBarcode,
    this.maxPending = 32,
    this.duplicateWindow = const Duration(milliseconds: 300),
    WearBarcodeClock? clock,
  })  : assert(maxPending > 0),
        _handleBarcode = handleBarcode,
        _clock = clock ?? DateTime.now;

  final WearBarcodeHandler _handleBarcode;
  final WearBarcodeClock _clock;
  final int maxPending;
  final Duration duplicateWindow;
  final Queue<String> _pending = Queue<String>();

  bool _draining = false;
  int _generation = 0;
  String? _lastAcceptedPayload;
  DateTime? _lastAcceptedAt;

  int get pendingCount => _pending.length;

  bool add(String payload) {
    final String value = payload.trim();
    if (value.isEmpty || _pending.length >= maxPending) return false;
    final DateTime now = _clock();
    final DateTime? lastAcceptedAt = _lastAcceptedAt;
    if (_lastAcceptedPayload == value &&
        lastAcceptedAt != null &&
        now.difference(lastAcceptedAt) < duplicateWindow) {
      return false;
    }
    _lastAcceptedPayload = value;
    _lastAcceptedAt = now;
    _pending.addLast(value);
    _ensureDrain();
    return true;
  }

  void reset() {
    _generation += 1;
    _pending.clear();
    _lastAcceptedPayload = null;
    _lastAcceptedAt = null;
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
      final String payload = _pending.removeFirst();
      try {
        final bool consumed = await _handleBarcode(payload);
        if (!consumed) {
          print('[WearBarcodeDispatcher] barcode not consumed: $payload');
        }
      } catch (error, stackTrace) {
        print('[WearBarcodeDispatcher] barcode error=$error\n$stackTrace');
      }
    }
  }
}

class WearBarcodeDispatcher implements MultiScannerDelegate {
  WearBarcodeDispatcher({
    required WearFlowController flowController,
    MultiScanner? scanner,
  })  : _scanner = scanner ?? MultiScanner.last(),
        _queue = WearBarcodeSerialQueue(
          handleBarcode: flowController.handleBarcode,
        );

  final MultiScanner _scanner;
  final WearBarcodeSerialQueue _queue;
  bool _started = false;

  void start() {
    if (_started) return;
    _scanner.addDelegate(this);
    _started = true;
  }

  void stop() {
    if (!_started) return;
    _scanner.removeDelegate(this);
    _started = false;
    _queue.reset();
  }

  @override
  bool? onScanEvent(String payload) {
    if (!_started) return false;
    final bool accepted = _queue.add(payload);
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
}
