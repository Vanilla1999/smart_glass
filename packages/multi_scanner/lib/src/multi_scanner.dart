import 'package:flutter/foundation.dart';
import 'package:multi_scanner/src/global_multi_scanner.dart';

enum _PdtMode {
  broadcast,
  last,
  sequential,
}

typedef PdtEventCallback = bool? Function(String payload);
typedef PdtErrorCallback = bool? Function(Exception payload);

abstract class MultiScannerDelegate {
  bool? onScanEvent(String payload);

  bool? onErrorScan(Exception error);
}

abstract class MultiScanner {
  factory MultiScanner.sequential() => _MultiScannerImpl(_PdtMode.sequential);

  factory MultiScanner.broadcaster() => _MultiScannerImpl(_PdtMode.broadcast);

  factory MultiScanner.last() => _MultiScannerImpl(_PdtMode.last);

  void addDelegate(MultiScannerDelegate delegate);

  void receiveBarcode(String barcode);

  void removeDelegate(MultiScannerDelegate delegate);

  void removeAllDelegate();

  MultiScannerSubscription subscribe(PdtEventCallback onEvent,
      [PdtErrorCallback? onError]);

  bool get active;

  void on();

  void off();

}

abstract class MultiScannerSubscription {
  void dispose();
}

class _MultiScannerSubscription implements MultiScannerSubscription {
  _MultiScannerSubscription(this.onDispose);

  final VoidCallback onDispose;

  @override
  void dispose() => onDispose();
}

class _MultiScannerFakeDelegate implements MultiScannerDelegate {
  final Function(Exception) _onError;
  final Function(String) _onEvent;

  _MultiScannerFakeDelegate(this._onEvent, this._onError);

  @override
  bool? onErrorScan(Exception error) => _onError(error);

  @override
  bool? onScanEvent(String payload) => _onEvent(payload);
}

class _MultiScannerImpl implements MultiScanner, GlobalMultiScannerDelegate {
  late final _global = GlobalMultiScanner();

  _MultiScannerImpl(this.mode) {
    _global.registerDelegate(this);
  }

  final _delegates = <MultiScannerDelegate>[];
  final _PdtMode mode;

  @override
  bool active = true;

  @override
  void on() => active = true;

  @override
  void off() => active = false;

  @override
  void addDelegate(MultiScannerDelegate delegate) => _delegates.add(delegate);

  @override
  void removeDelegate(MultiScannerDelegate delegate) => _delegates.remove(delegate);

  @override
  void removeAllDelegate() {
    _delegates.clear();
    _global.unregisterDelegate(this);
  }

  @override
  void onEvent(String payload) {
    if (!active) return;
    if (_delegates.isEmpty) return;

    switch (mode) {
      case _PdtMode.broadcast:
        for (var d in _delegates) {
          d.onScanEvent(payload);
        }
        break;
      case _PdtMode.last:
        _delegates.last.onScanEvent(payload);
        break;
      case _PdtMode.sequential:
        final reversed = _delegates.reversed.iterator;
        bool done = false;
        do {
          done = (reversed.current.onScanEvent(payload) ?? false) && !reversed.moveNext();
        } while (!done);
        break;
    }
  }

  @override
  void onError(Exception error) {
    if (!active) return;
    if (_delegates.isEmpty) return;

    switch (mode) {
      case _PdtMode.broadcast:
        for (var d in _delegates) {
          d.onErrorScan(error);
        }
        break;
      case _PdtMode.last:
        _delegates.last.onErrorScan(error);
        break;
      case _PdtMode.sequential:
        final reversed = _delegates.reversed.iterator;
        bool done = false;
        do {
          done = (reversed.current.onErrorScan(error) ?? false) && !reversed.moveNext();
        } while (!done);
        break;
    }
  }

  @override
  MultiScannerSubscription subscribe(PdtEventCallback onEvent, [PdtErrorCallback? onError]) {
    final delegate = _MultiScannerFakeDelegate(onEvent, onError ?? (_) => false);
    final sub = _MultiScannerSubscription(() => removeDelegate(delegate));
    addDelegate(delegate);
    return sub;
  }

  @override
  void receiveBarcode(String barcode) {
    _global.receiveScanEvent(barcode);
  }
}
