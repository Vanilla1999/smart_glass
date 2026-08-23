import 'dart:async';
import 'dart:collection';

import 'package:multi_scanner/multi_scanner.dart';
import 'package:smart_glasses/modules/wear/application/wear_flow_controller.dart';
import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_authority.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_control_adapter.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_semantic_inputs.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_store.dart';

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
    WearRuntimeAuthority? authority,
    WearFlowController? flowController,
    WearBarcodeHandler? unsupportedHandler,
    MultiScanner? scanner,
  })  : assert(
          authority != null || flowController != null,
          'WearRuntimeAuthority is required',
        ),
        _authority = authority ?? flowController!.authority,
        _unsupportedHandler =
            unsupportedHandler ?? flowController?.handleBarcode,
        _scanner = scanner ?? MultiScanner.last();

  final WearRuntimeAuthority _authority;
  final WearBarcodeHandler? _unsupportedHandler;
  final MultiScanner _scanner;
  late final WearBarcodeSerialQueue _queue = WearBarcodeSerialQueue(
    handleBarcode: (String _) async => false,
  );
  bool _started = false;
  int _nextDeliveryId = 0;
  WearRuntimeControlAdapter? _controlAdapter;

  void start() {
    if (_started) return;
    _controlAdapter = WearRuntimeControlAdapter(_authority);
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
    final aggregate = _authority.payload;
    final controls = _authority.controls.scanner;
    if (!_started ||
        _authority.state.terminal ||
        aggregate.lifecycle.terminal ||
        !aggregate.lifecycle.runtimeActive ||
        !controls.barcodeAdmissionEnabled) {
      return false;
    }
    final WearRuntimeControlAdapter? callback = _controlAdapter;
    if (callback == null) return false;

    // Screen and epoch are captured from one committed aggregate snapshot.
    // Queued work cannot be re-attributed to a newer session or route.
    final int sessionEpoch = _authority.state.sessionEpoch;
    final WearScreenId screen = aggregate.navigation.logicalScreen;
    if (callback.sessionEpoch != sessionEpoch ||
        controls.expectedLogicalScreen != screen) {
      return false;
    }

    final int deliveryId = ++_nextDeliveryId;
    final bool accepted = _queue.addWithHandler(
      payload,
      (String value) => _deliverBarcode(
        value,
        callback: callback,
        sessionEpoch: sessionEpoch,
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
    required int sessionEpoch,
    required WearScreenId screen,
    required int deliveryId,
  }) async {
    if (callback.sessionEpoch != sessionEpoch) return false;
    final WearDispatchResult receipt = await callback.acceptBarcodeDelivery(
      deliveryId: deliveryId,
      logicalScreen: screen,
    );
    if (!receipt.accepted || receipt.sessionEpoch != sessionEpoch) return false;

    final WearDispatchResult semanticReceipt =
        await _authority.dispatchSemanticInput(
      kind: WearSemanticInputKind.barcode,
      modality: WearInputModality.barcode,
      expectedScreen: screen,
      expectedSessionEpoch: sessionEpoch,
      value: payload,
    );
    if (semanticReceipt.accepted &&
        semanticReceipt.sessionEpoch == sessionEpoch) {
      return true;
    }

    // Pre-auth/main remains a bounded compatibility handler until auth itself
    // becomes an aggregate effect in MR-S12. No authenticated or non-main path
    // may bypass the aggregate semantic reducer.
    final WearBarcodeHandler? fallback = _unsupportedHandler;
    if (fallback == null ||
        _authority.isAuthorized ||
        screen != WearScreenId.main ||
        semanticReceipt.rejectReason != WearDispatchRejectReason.unsupported ||
        _authority.state.sessionEpoch != sessionEpoch ||
        _authority.payload.navigation.logicalScreen != screen) {
      return false;
    }
    return fallback(payload);
  }
}
