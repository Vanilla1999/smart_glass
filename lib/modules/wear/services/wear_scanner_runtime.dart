import 'package:multi_scanner/multi_scanner.dart';

class WearScannerRuntime {
  WearScannerRuntime({BaseController? controller})
      : _controller = controller ?? BaseController();

  final BaseController _controller;
  Future<void> _operation = Future<void>.value();
  bool _initialized = false;
  bool? _prepared;

  Future<void> start() {
    return _enqueue(() async {
      if (_prepared == true) return;
      if (!_initialized) {
        await _controller.init();
        _initialized = true;
      }
      await _controller.prepareForWear();
      _prepared = true;
    });
  }

  Future<void> pause() {
    return _enqueue(() async {
      if (_prepared == false) return;
      await _controller.pauseForWear();
      _prepared = false;
    });
  }

  Future<void> release() {
    return _enqueue(() async {
      await _controller.release();
      _initialized = false;
      _prepared = false;
    });
  }

  Future<void> _enqueue(Future<void> Function() operation) {
    final Future<void> next =
        _operation.catchError((Object _) {}).then<void>((_) => operation());
    _operation = next;
    return next;
  }
}
