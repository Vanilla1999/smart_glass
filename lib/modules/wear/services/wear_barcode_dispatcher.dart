import 'dart:async';

import 'package:multi_scanner/multi_scanner.dart';
import 'package:smart_glasses/modules/wear/application/wear_flow_controller.dart';

class WearBarcodeDispatcher implements MultiScannerDelegate {
  WearBarcodeDispatcher({
    required WearFlowController flowController,
    MultiScanner? scanner,
  })  : _flowController = flowController,
        _scanner = scanner ?? MultiScanner.last();

  final WearFlowController _flowController;
  final MultiScanner _scanner;
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
  }

  @override
  bool? onScanEvent(String payload) {
    unawaited(
      _flowController.handleBarcode(payload).catchError(
        (Object error, StackTrace stackTrace) {
          print('[WearBarcodeDispatcher] barcode error=$error\n$stackTrace');
          return false;
        },
      ),
    );
    return true;
  }

  @override
  bool? onErrorScan(Exception error) => false;
}
