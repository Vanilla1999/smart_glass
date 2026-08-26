import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:multi_scanner/multi_scanner.dart';
import 'package:smart_glasses/features/scanner/presentation/cubit/scanner_state.dart';

/// Cubit for managing barcode scanner
class ScannerCubit extends Cubit<ScannerState> implements MultiScannerDelegate {
  ScannerCubit({BaseController? controller, MultiScanner? scanner})
      : _baseController = controller ?? BaseController(),
        _scanner = scanner ?? MultiScanner.last(),
        super(const ScannerIdle());

  final BaseController _baseController;
  final MultiScanner _scanner;
  StreamSubscription<bool>? _serviceSub;
  Future<void>? _initOperation;
  Future<void>? _closeOperation;
  int _lifecycleGeneration = 0;
  bool _delegateRegistered = false;
  bool _closing = false;

  /// Initialize scanner
  Future<void> init() {
    if (_closing || isClosed) return Future<void>.value();
    final Future<void>? operation = _initOperation;
    if (operation != null) return operation;
    final Future<void> next = _initialize(++_lifecycleGeneration);
    _initOperation = next;
    next.catchError((Object _) {}).whenComplete(() {
      if (_initOperation == next && state is ScannerError) {
        _initOperation = null;
      }
    });
    return next;
  }

  Future<void> _initialize(int generation) async {
    emit(const ScannerConnecting());
    if (!_delegateRegistered) {
      _scanner.addDelegate(this);
      _delegateRegistered = true;
    }

    try {
      await _baseController.init();
      if (!_isCurrent(generation)) return;
      await _baseController.setRecomendedSettings();
      if (!_isCurrent(generation)) return;

      _serviceSub = _baseController.isServiceConnected.listen((connected) {
        if (connected && _isCurrent(generation)) {
          emit(const ScannerReady());
        }
      });
    } catch (e) {
      if (_isCurrent(generation)) emit(ScannerError(e.toString()));
    }
  }

  bool _isCurrent(int generation) =>
      !_closing && !isClosed && generation == _lifecycleGeneration;

  @override
  bool? onScanEvent(String payload) {
    if (_closing || isClosed) return false;
    print('Barcode scanned: $payload');
    emit(ScannerScanned(payload));
    return false;
  }

  @override
  bool? onErrorScan(Exception error) {
    if (_closing || isClosed) return false;
    print('Scanner error: $error');
    emit(ScannerError(error.toString()));
    return false;
  }

  @override
  // Cleanup and super.close() run once in the shared operation below.
  // ignore: must_call_super
  Future<void> close() => _closeOperation ??= _close();

  Future<void> _close() async {
    if (isClosed) return;
    _closing = true;
    _lifecycleGeneration += 1;
    if (_delegateRegistered) {
      _scanner.removeDelegate(this);
      _delegateRegistered = false;
    }
    await _serviceSub?.cancel();
    _serviceSub = null;
    await super.close();
  }
}
