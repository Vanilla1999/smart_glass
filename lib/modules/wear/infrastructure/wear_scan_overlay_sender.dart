import 'dart:async';

import 'package:multi_scanner/multi_scanner.dart';
import 'package:smart_glasses/core/services/method_channel_service.dart';

class WearScanOverlaySender {
  WearScanOverlaySender({
    MovfastGlassController? controller,
    MethodChannelService? methodChannelService,
    void Function(Object error, StackTrace stackTrace)? onError,
  })  : _controller = controller ?? MovfastGlassController(),
        _methodChannelService = methodChannelService ?? MethodChannelService(),
        _onError = onError;

  final MovfastGlassController _controller;
  final MethodChannelService _methodChannelService;
  final void Function(Object error, StackTrace stackTrace)? _onError;

  StreamSubscription<BarcodeTrackingEvent>? _subscription;
  Future<void> _operation = Future<void>.value();
  Future<void>? _trackingDrain;
  Map<String, dynamic>? _pendingTrackingPayload;
  bool _enabled = false;
  int _revision = 0;
  final int _sessionId = DateTime.now().microsecondsSinceEpoch;

  Future<void> setEnabled(bool enabled) {
    _operation = _operation
        .catchError(_reportError)
        .then<void>((_) => _applyEnabled(enabled));
    return _operation;
  }

  Future<void> _applyEnabled(bool enabled) async {
    if (_enabled == enabled) return;
    _enabled = enabled;
    if (enabled) {
      _subscription ??= _controller.trackingEvents.listen(
        _onTracking,
        onError: _reportStreamError,
      );
      try {
        await _send(<String, dynamic>{
          'visible': true,
          'phase': 'searching',
        });
        await _controller.startBarcodeTracking();
      } catch (_) {
        _enabled = false;
        rethrow;
      }
      return;
    }
    _pendingTrackingPayload = null;
    await _trackingDrain;
    try {
      await _controller.stopBarcodeTracking();
    } finally {
      await _send(<String, dynamic>{
        'visible': false,
        'phase': 'clear',
      });
    }
  }

  void _onTracking(BarcodeTrackingEvent event) {
    if (!_enabled) return;
    final Map<String, dynamic> payload = <String, dynamic>{
      'visible': true,
      'phase': event.phase == BarcodeTrackingPhase.clear
          ? 'searching'
          : event.phase.name,
      'sourceSequence': event.sequence,
      'candidateId': event.candidateId,
      'capturedAtElapsedRealtimeNanos': event.capturedAtElapsedRealtimeNanos,
      'detectedAtElapsedRealtimeNanos': event.detectedAtElapsedRealtimeNanos,
      'frameWidth': event.frameWidth,
      'frameHeight': event.frameHeight,
      'rotationDegrees': event.rotationDegrees,
      'mirrored': event.mirrored,
      if (event.phase != BarcodeTrackingPhase.clear) ...<String, double>{
        'left': event.left,
        'top': event.top,
        'right': event.right,
        'bottom': event.bottom,
      },
    };
    _pendingTrackingPayload = payload;
    _trackingDrain ??= _drainTracking();
  }

  Future<void> _drainTracking() async {
    try {
      while (_enabled && _pendingTrackingPayload != null) {
        final Map<String, dynamic> payload = _pendingTrackingPayload!;
        _pendingTrackingPayload = null;
        try {
          await _send(payload);
        } catch (error, stackTrace) {
          await _reportError(error, stackTrace);
        }
      }
    } finally {
      _trackingDrain = null;
    }
  }

  Future<void> _send(Map<String, dynamic> payload) {
    return _methodChannelService.updateWearScanOverlay(<String, dynamic>{
      'version': 1,
      'sessionId': _sessionId,
      'revision': ++_revision,
      ...payload,
    });
  }

  Future<void> dispose() async {
    await setEnabled(false);
    await _subscription?.cancel();
    _subscription = null;
  }

  void _reportStreamError(Object error, StackTrace stackTrace) {
    _onError?.call(error, stackTrace);
  }

  Future<void> _reportError(Object error, StackTrace stackTrace) async {
    _onError?.call(error, stackTrace);
  }
}
