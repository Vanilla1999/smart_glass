import 'package:flutter/widgets.dart';
import 'package:multi_scanner/src/platform/multi_scanner_platform_interface.dart';


abstract class GlobalMultiScannerDelegate {
  void onError(Exception error);

  void onEvent(String payload);
}

abstract class GlobalMultiScanner {
  factory GlobalMultiScanner() => _GlobalMultiScannerImpl._instance;

  void registerDelegate(GlobalMultiScannerDelegate delegate);

  void receiveScanEvent(String barcode);

  void unregisterDelegate(GlobalMultiScannerDelegate delegate);
}

class _GlobalMultiScannerImpl with WidgetsBindingObserver implements GlobalMultiScanner {
  static GlobalMultiScanner _make() => _GlobalMultiScannerImpl().._registerScanEvents();
  static final _instance = _make();

  final _delegates = <GlobalMultiScannerDelegate>{};

  @override
  void registerDelegate(GlobalMultiScannerDelegate delegate) => _delegates.add(delegate);

  @override
  void unregisterDelegate(GlobalMultiScannerDelegate delegate) => _delegates.remove(delegate);

  void _registerScanEvents(){
    MultiScannerPlatform.instance.registerListenerScan(_delegates);
  }

  @override
  void receiveScanEvent(String barcode){
    for (var d in _delegates) {
      d.onEvent(barcode);
    }
  }
// void _onError(Exception value) {
//   for (var d in _delegates) {
//     d.onError(value);
//   }
// }

}
