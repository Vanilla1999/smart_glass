import 'dart:async';

/// Starts the same three long-lived subsystems that the production application
/// starts after authorization: scanner SDK, UAC4 voice capture, and a secondary
/// Flutter engine for the glasses display.
class MainAppParityRuntime {
  MainAppParityRuntime({
    required Future<void> Function() startScanner,
    required Future<String> Function() startVoice,
    required Future<bool> Function() showGlassesDisplay,
    required Future<int> Function() getFlashlightState,
    required Future<void> Function(int state) setFlashlight,
    Future<Map<String, dynamic>> Function()? nativeDiagnostics,
    Future<void> Function(Duration duration)? delay,
  }) : _startScanner = startScanner,
       _startVoice = startVoice,
       _showGlassesDisplay = showGlassesDisplay,
       _getFlashlightState = getFlashlightState,
       _setFlashlight = setFlashlight,
       _nativeDiagnostics = nativeDiagnostics,
       _delay = delay ?? Future<void>.delayed;

  final Future<void> Function() _startScanner;
  final Future<String> Function() _startVoice;
  final Future<bool> Function() _showGlassesDisplay;
  final Future<int> Function() _getFlashlightState;
  final Future<void> Function(int state) _setFlashlight;
  final Future<Map<String, dynamic>> Function()? _nativeDiagnostics;
  final Future<void> Function(Duration duration) _delay;

  Future<MainAppParityStartReport>? _startFuture;
  int? _trackedFlashlightState;

  bool get isStarted => _startFuture != null;

  /// Production starts scanner and voice without awaiting one before the other.
  /// Keeping the operations in the same Future.wait is intentional: this is the
  /// race/load shape we need the example to reproduce.
  Future<MainAppParityStartReport> start() {
    return _startFuture ??= _startInternal().catchError((Object error) {
      _startFuture = null;
      throw error;
    });
  }

  Future<MainAppParityStartReport> _startInternal() async {
    final Stopwatch total = Stopwatch()..start();

    // The production app normally has its secondary glasses engine alive before
    // authorization completes. Register that second engine first, then reproduce
    // the authorization-time scanner/voice overlap.
    final _TimedResult<bool> displayResult = await _timed<bool>(
      'display',
      _showGlassesDisplay,
    );
    final Future<_TimedResult<bool>> scanner = _timed<bool>(
      'scanner',
      () async {
        await _startScanner();
        return true;
      },
    );
    final Future<_TimedResult<String>> voice = _timed<String>(
      'voice',
      _startVoice,
    );

    final List<Object> completed = await Future.wait<Object>(<Future<Object>>[
      scanner,
      voice,
    ], eagerError: true);
    total.stop();

    final _TimedResult<bool> scannerResult = completed[0] as _TimedResult<bool>;
    final _TimedResult<String> voiceResult =
        completed[1] as _TimedResult<String>;
    final Map<String, dynamic> diagnostics =
        await (_nativeDiagnostics?.call() ??
            Future<Map<String, dynamic>>.value(const <String, dynamic>{}));

    return MainAppParityStartReport(
      totalMs: total.elapsedMilliseconds,
      scannerMs: scannerResult.elapsedMs,
      voiceMs: voiceResult.elapsedMs,
      displayMs: displayResult.elapsedMs,
      voiceStatus: voiceResult.value,
      displayShown: displayResult.value,
      diagnostics: diagnostics,
    );
  }

  /// Mirrors WearFlowController._toggleScannerFlashlight(): read hardware once,
  /// then prefer the process-local tracked state on subsequent calls.
  /// A read-after-write probe is added only for diagnosis; it does not change
  /// the requested target or the tracked state.
  Future<FlashlightParityProbe> toggleFlashlightLikeMain() async {
    final Stopwatch stopwatch = Stopwatch()..start();
    final int observedBefore = await _getFlashlightState();
    final int logicalBefore = _trackedFlashlightState ?? observedBefore;
    final int requested = logicalBefore == 1 ? 0 : 1;

    await _setFlashlight(requested);
    _trackedFlashlightState = requested;

    int observedAfter = await _getFlashlightState();
    var attempts = 1;
    while (observedAfter != requested && attempts < 5) {
      await _delay(const Duration(milliseconds: 100));
      observedAfter = await _getFlashlightState();
      attempts++;
    }
    stopwatch.stop();

    final Map<String, dynamic> diagnostics =
        await (_nativeDiagnostics?.call() ??
            Future<Map<String, dynamic>>.value(const <String, dynamic>{}));
    return FlashlightParityProbe(
      observedBefore: observedBefore,
      logicalBefore: logicalBefore,
      requested: requested,
      observedAfter: observedAfter,
      verificationAttempts: attempts,
      elapsedMs: stopwatch.elapsedMilliseconds,
      diagnostics: diagnostics,
    );
  }

  void resetTrackedFlashlightState() {
    _trackedFlashlightState = null;
  }

  Future<_TimedResult<T>> _timed<T>(
    String name,
    Future<T> Function() operation,
  ) async {
    final Stopwatch stopwatch = Stopwatch()..start();
    try {
      final T value = await operation();
      stopwatch.stop();
      return _TimedResult<T>(name, value, stopwatch.elapsedMilliseconds);
    } catch (error) {
      stopwatch.stop();
      throw MainAppParityException(
        operation: name,
        elapsedMs: stopwatch.elapsedMilliseconds,
        cause: error,
      );
    }
  }
}

class MainAppParityStartReport {
  const MainAppParityStartReport({
    required this.totalMs,
    required this.scannerMs,
    required this.voiceMs,
    required this.displayMs,
    required this.voiceStatus,
    required this.displayShown,
    required this.diagnostics,
  });

  final int totalMs;
  final int scannerMs;
  final int voiceMs;
  final int displayMs;
  final String voiceStatus;
  final bool displayShown;
  final Map<String, dynamic> diagnostics;

  @override
  String toString() =>
      'started total=${totalMs}ms scanner=${scannerMs}ms '
      'voice=${voiceMs}ms($voiceStatus) display=${displayMs}ms($displayShown) '
      'native=$diagnostics';
}

class FlashlightParityProbe {
  const FlashlightParityProbe({
    required this.observedBefore,
    required this.logicalBefore,
    required this.requested,
    required this.observedAfter,
    required this.verificationAttempts,
    required this.elapsedMs,
    required this.diagnostics,
  });

  final int observedBefore;
  final int logicalBefore;
  final int requested;
  final int observedAfter;
  final int verificationAttempts;
  final int elapsedMs;
  final Map<String, dynamic> diagnostics;

  bool get stateAcknowledged => observedAfter == requested;

  @override
  String toString() =>
      'flashlight observedBefore=$observedBefore logicalBefore=$logicalBefore '
      'requested=$requested observedAfter=$observedAfter '
      'acknowledged=$stateAcknowledged attempts=$verificationAttempts '
      'elapsed=${elapsedMs}ms native=$diagnostics';
}

class MainAppParityException implements Exception {
  const MainAppParityException({
    required this.operation,
    required this.elapsedMs,
    required this.cause,
  });

  final String operation;
  final int elapsedMs;
  final Object cause;

  @override
  String toString() =>
      'MainAppParityException(operation=$operation, elapsedMs=$elapsedMs, '
      'cause=$cause)';
}

class _TimedResult<T> {
  const _TimedResult(this.name, this.value, this.elapsedMs);

  final String name;
  final T value;
  final int elapsedMs;
}
