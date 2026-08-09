import 'dart:async';

enum FreeTextRecognizerState {
  absent,
  creating,
  ready,
  retiring,
  recovering,
  disposed,
}

typedef FreeTextRecognizerDisposer<T> = Future<void> Function(T recognizer);

/// Owns the asynchronous lifetime of the single free-text recognizer.
class FreeTextRecognizerController<T> {
  FreeTextRecognizerController({
    required Future<T> Function() create,
    required FreeTextRecognizerDisposer<T> dispose,
    bool initiallyEnabled = false,
  })  : _create = create,
        _dispose = dispose,
        _enabled = initiallyEnabled;

  final Future<T> Function() _create;
  final FreeTextRecognizerDisposer<T> _dispose;

  FreeTextRecognizerState _state = FreeTextRecognizerState.absent;
  Future<T?>? _creation;
  int? _creationGeneration;
  T? _recognizer;
  int _generation = 0;
  bool _enabled;

  FreeTextRecognizerState get state => _state;
  T? get recognizer => _recognizer;
  Future<void> get ready =>
      (_creation ?? Future<T?>.value(_recognizer)).then((_) {});

  Future<T?> enable() {
    _ensureUsable();
    _enabled = true;
    return acquire(commandWorkPending: true);
  }

  void disable({Future<void>? pendingOperation}) {
    if (_state == FreeTextRecognizerState.disposed) return;
    _enabled = false;
    _generation++;
    final T? recognizer = _recognizer;
    _recognizer = null;
    if (recognizer == null) {
      _state = FreeTextRecognizerState.absent;
      return;
    }
    _state = FreeTextRecognizerState.retiring;
    _disposeSafely(recognizer, pendingOperation).whenComplete(() {
      if (_state == FreeTextRecognizerState.retiring) {
        _state = FreeTextRecognizerState.absent;
      }
    });
  }

  Future<T?> acquire({required bool commandWorkPending}) {
    _ensureUsable();
    if (!_enabled && !commandWorkPending) return Future<T?>.value();
    final T? recognizer = _recognizer;
    if (recognizer != null) return Future<T?>.value(recognizer);
    final Future<T?>? creation = _creation;
    if (creation != null) {
      if (_creationGeneration == _generation) return creation;
      return creation
          .then((_) => acquire(commandWorkPending: commandWorkPending));
    }
    return _startCreation(
      _state == FreeTextRecognizerState.retiring
          ? FreeTextRecognizerState.recovering
          : FreeTextRecognizerState.creating,
    );
  }

  void abandonCreation() {
    if (_state == FreeTextRecognizerState.disposed || _creation == null) return;
    _generation++;
    _creation = null;
    _creationGeneration = null;
    _state = FreeTextRecognizerState.absent;
  }

  Future<T?> recover(
    T failed, {
    Future<void>? pendingOperation,
    required bool commandWorkPending,
  }) {
    _ensureUsable();
    if (!identical(_recognizer, failed)) {
      return _creation ?? Future<T?>.value(_recognizer);
    }
    _recognizer = null;
    _generation++;
    _state = FreeTextRecognizerState.retiring;
    unawaited(_disposeSafely(failed, pendingOperation));
    if (!_enabled && !commandWorkPending) {
      _state = FreeTextRecognizerState.absent;
      return Future<T?>.value();
    }
    return _creation ?? _startCreation(FreeTextRecognizerState.recovering);
  }

  void adopt(T recognizer) {
    _ensureUsable();
    if (_recognizer == null && _creation == null) {
      _recognizer = recognizer;
      _state = FreeTextRecognizerState.ready;
      return;
    }
    if (!identical(_recognizer, recognizer)) {
      unawaited(_disposeSafely(recognizer, null));
    }
  }

  Future<void> dispose({Future<void>? pendingOperation}) async {
    if (_state == FreeTextRecognizerState.disposed) return;
    _enabled = false;
    _generation++;
    _state = FreeTextRecognizerState.disposed;
    final T? recognizer = _recognizer;
    final Future<T?>? creation = _creation;
    _recognizer = null;
    if (recognizer != null) {
      await _disposeSafely(recognizer, pendingOperation);
    }
    if (creation != null) {
      try {
        await creation;
      } catch (_) {}
    }
  }

  Future<T?> _startCreation(FreeTextRecognizerState state) {
    final int generation = _generation;
    _state = state;
    _creationGeneration = generation;
    late final Future<T?> creation;
    creation = _create().then((T created) async {
      if (_state == FreeTextRecognizerState.disposed ||
          generation != _generation ||
          (!_enabled && state != FreeTextRecognizerState.recovering)) {
        await _disposeSafely(created, null);
        return _recognizer;
      }
      _recognizer = created;
      _state = FreeTextRecognizerState.ready;
      return created;
    }).whenComplete(() {
      if (identical(_creation, creation)) {
        _creation = null;
        _creationGeneration = null;
      }
      if (identical(_creation, creation) &&
          _recognizer == null &&
          _state != FreeTextRecognizerState.disposed) {
        _state = FreeTextRecognizerState.absent;
      }
    });
    _creation = creation;
    return creation;
  }

  Future<void> _disposeWhenSafe(T recognizer, Future<void>? pending) async {
    if (pending != null) {
      try {
        await pending;
      } catch (_) {}
    }
    await _dispose(recognizer);
  }

  Future<void> _disposeSafely(T recognizer, Future<void>? pending) async {
    try {
      await _disposeWhenSafe(recognizer, pending);
    } catch (_) {}
  }

  void _ensureUsable() {
    if (_state == FreeTextRecognizerState.disposed) {
      throw StateError('Free-text recognizer controller is disposed');
    }
  }
}
