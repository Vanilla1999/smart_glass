import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:multi_scanner/multi_scanner.dart';
import 'package:smart_glasses/features/scanner/presentation/cubit/scanner_state.dart';

/// Cubit for managing barcode scanner
class ScannerCubit extends Cubit<ScannerState> implements MultiScannerDelegate {
  ScannerCubit() : super(const ScannerIdle());

  final BaseController _baseController = BaseController();
  late final MultiScanner _scanner = MultiScanner.last();
  StreamSubscription<bool>? _serviceSub;

  /// Initialize scanner
  Future<void> init() async {
    emit(const ScannerConnecting());
    _scanner.addDelegate(this);

    try {
      await _baseController.init();
      _baseController.setRecomendedSettings();

      _serviceSub = _baseController.isServiceConnected.listen((connected) {
        if (connected) {
          emit(const ScannerReady());
        }
      });
    } catch (e) {
      emit(ScannerError(e.toString()));
    }
  }

  @override
  bool? onScanEvent(String payload) {
    print('Barcode scanned: $payload');
    emit(ScannerScanned(payload));
    return false;
  }

  @override
  bool? onErrorScan(Exception error) {
    print('Scanner error: $error');
    emit(ScannerError(error.toString()));
    return false;
  }

  @override
  Future<void> close() {
    _scanner.removeDelegate(this);
    _serviceSub?.cancel();
    return super.close();
  }
}
