import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_bloc/flutter_bloc.dart';

enum WearScanOverlayPhase { searching, candidate, locked }

class WearScanOverlayState {
  const WearScanOverlayState({
    this.visible = false,
    this.sessionId = 0,
    this.revision = 0,
    this.phase = WearScanOverlayPhase.searching,
    this.centerX = 0.5,
    this.centerY = 0.5,
  });

  final bool visible;
  final int sessionId;
  final int revision;
  final WearScanOverlayPhase phase;
  final double centerX;
  final double centerY;
}

class WearScanOverlayCubit extends Cubit<WearScanOverlayState> {
  WearScanOverlayCubit() : super(const WearScanOverlayState());

  static const Duration _candidateStaleTimeout = Duration(milliseconds: 1000);
  static const int _candidateConfirmationEvents = 2;
  static const double _movementDeadZone = 0.015;
  static const double _fallbackElapsedSeconds = 1 / 15;

  Timer? _staleTimer;
  final _OneEuroFilter _centerXFilter = _OneEuroFilter();
  final _OneEuroFilter _centerYFilter = _OneEuroFilter();
  int? _candidateId;
  int? _pendingCandidateId;
  int _pendingCandidateEvents = 0;
  int? _detectedAtNanos;

  void update(Map<String, dynamic> payload) {
    final int sessionId = payload['sessionId'] as int? ?? state.sessionId;
    final int revision = payload['revision'] as int? ?? state.revision + 1;
    if (sessionId < state.sessionId) return;
    if (sessionId == state.sessionId && revision <= state.revision) return;
    final bool visible = payload['visible'] == true;
    final WearScanOverlayPhase phase = switch (payload['phase']) {
      'candidate' => WearScanOverlayPhase.candidate,
      'locked' => WearScanOverlayPhase.locked,
      _ => WearScanOverlayPhase.searching,
    };
    final bool sessionChanged = sessionId != state.sessionId;
    final (double, double) center;
    if (phase == WearScanOverlayPhase.searching) {
      _resetTracking();
      center = (0.5, 0.5);
    } else {
      center = _smoothedCenter(
        payload,
        reset: sessionChanged,
        locked: phase == WearScanOverlayPhase.locked,
      );
    }
    _staleTimer?.cancel();
    emit(WearScanOverlayState(
      visible: visible,
      sessionId: sessionId,
      revision: revision,
      phase: phase,
      centerX: center.$1,
      centerY: center.$2,
    ));
    if (visible && phase == WearScanOverlayPhase.candidate) {
      _staleTimer = Timer(_candidateStaleTimeout, () {
        _resetTracking();
        emit(WearScanOverlayState(
          visible: true,
          sessionId: state.sessionId,
          revision: state.revision,
        ));
      });
    }
  }

  (double, double) _smoothedCenter(
    Map<String, dynamic> payload, {
    required bool reset,
    required bool locked,
  }) {
    if (reset) _resetTracking();
    final double centerX = _center(payload['left'], payload['right']);
    final double centerY = _center(payload['top'], payload['bottom']);
    final int candidateId = payload['candidateId'] as int? ?? -1;
    final bool hasVisualCandidate =
        _candidateId != null && _centerXFilter.initialized;
    final bool candidateChanged = candidateId != _candidateId;
    if (candidateChanged && !locked && !_confirmCandidate(candidateId)) {
      return (_centerXFilter.value, _centerYFilter.value);
    }
    if (candidateChanged) {
      _candidateId = candidateId;
      _clearPendingCandidate();
      if (locked && hasVisualCandidate) {
        _detectedAtNanos = payload['detectedAtElapsedRealtimeNanos'] as int?;
        return (_centerXFilter.value, _centerYFilter.value);
      }
    }
    _clearPendingCandidate();

    final int? detectedAtNanos =
        payload['detectedAtElapsedRealtimeNanos'] as int?;
    final int? previousNanos = _detectedAtNanos;
    final double? elapsedSeconds =
        detectedAtNanos == null || previousNanos == null
            ? null
            : (detectedAtNanos - previousNanos) / 1000000000;
    if (!_centerXFilter.initialized || !_centerYFilter.initialized) {
      _centerXFilter.reset(centerX);
      _centerYFilter.reset(centerY);
    } else {
      final double interval =
          elapsedSeconds != null && elapsedSeconds > 0 && elapsedSeconds <= 0.5
              ? elapsedSeconds
              : _fallbackElapsedSeconds;
      if ((centerX - _centerXFilter.value).abs() <= _movementDeadZone) {
        _centerXFilter.hold(centerX);
      } else {
        _centerXFilter.filter(centerX, interval);
      }
      if ((centerY - _centerYFilter.value).abs() <= _movementDeadZone) {
        _centerYFilter.hold(centerY);
      } else {
        _centerYFilter.filter(centerY, interval);
      }
    }
    _detectedAtNanos = detectedAtNanos;
    return (_centerXFilter.value, _centerYFilter.value);
  }

  bool _confirmCandidate(int candidateId) {
    if (_pendingCandidateId == candidateId) {
      _pendingCandidateEvents++;
    } else {
      _pendingCandidateId = candidateId;
      _pendingCandidateEvents = 1;
    }
    return _pendingCandidateEvents >= _candidateConfirmationEvents;
  }

  void _clearPendingCandidate() {
    _pendingCandidateId = null;
    _pendingCandidateEvents = 0;
  }

  void _resetTracking() {
    _candidateId = null;
    _clearPendingCandidate();
    _detectedAtNanos = null;
    _centerXFilter.clear();
    _centerYFilter.clear();
  }

  static double _center(dynamic start, dynamic end) {
    if (start is! num || end is! num) return 0.5;
    return ((start.toDouble() + end.toDouble()) / 2).clamp(0, 1);
  }

  @override
  Future<void> close() {
    _staleTimer?.cancel();
    return super.close();
  }
}

class _OneEuroFilter {
  static const double _minCutoff = 1;
  static const double _beta = 0.3;
  static const double _derivativeCutoff = 1;

  double? _rawValue;
  double? _filteredValue;
  double? _filteredDerivative;

  bool get initialized => _filteredValue != null;
  double get value => _filteredValue ?? 0.5;

  void reset(double value) {
    _rawValue = value;
    _filteredValue = value;
    _filteredDerivative = 0;
  }

  void clear() {
    _rawValue = null;
    _filteredValue = null;
    _filteredDerivative = null;
  }

  void hold(double rawValue) {
    _rawValue = rawValue;
  }

  void filter(double value, double elapsedSeconds) {
    final double derivative = (value - _rawValue!) / elapsedSeconds;
    final double derivativeAlpha = _alpha(_derivativeCutoff, elapsedSeconds);
    _filteredDerivative = _lowPass(
      _filteredDerivative!,
      derivative,
      derivativeAlpha,
    );
    final double cutoff = _minCutoff + _beta * _filteredDerivative!.abs();
    _filteredValue = _lowPass(
      _filteredValue!,
      value,
      _alpha(cutoff, elapsedSeconds),
    );
    _rawValue = value;
  }

  static double _alpha(double cutoff, double elapsedSeconds) {
    final double timeConstant = 1 / (2 * math.pi * cutoff);
    return 1 / (1 + timeConstant / elapsedSeconds);
  }

  static double _lowPass(double previous, double value, double alpha) =>
      alpha * value + (1 - alpha) * previous;
}
