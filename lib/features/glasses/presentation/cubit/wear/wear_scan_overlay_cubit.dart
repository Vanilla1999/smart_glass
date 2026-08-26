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

  Timer? _staleTimer;
  final _OneEuroFilter _centerXFilter = _OneEuroFilter();
  final _OneEuroFilter _centerYFilter = _OneEuroFilter();
  int? _candidateId;
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
      center = _smoothedCenter(payload, reset: sessionChanged);
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
  }) {
    final double centerX = _center(payload['left'], payload['right']);
    final double centerY = _center(payload['top'], payload['bottom']);
    final int candidateId = payload['candidateId'] as int? ?? -1;
    final int? detectedAtNanos =
        payload['detectedAtElapsedRealtimeNanos'] as int?;
    final int? previousNanos = _detectedAtNanos;
    final double? elapsedSeconds =
        detectedAtNanos == null || previousNanos == null
            ? null
            : (detectedAtNanos - previousNanos) / 1000000000;
    final bool invalidInterval =
        elapsedSeconds == null || elapsedSeconds <= 0 || elapsedSeconds > 0.5;
    if (reset || candidateId != _candidateId || invalidInterval) {
      _centerXFilter.reset(centerX);
      _centerYFilter.reset(centerY);
    } else {
      _centerXFilter.filter(centerX, elapsedSeconds);
      _centerYFilter.filter(centerY, elapsedSeconds);
    }
    _candidateId = candidateId;
    _detectedAtNanos = detectedAtNanos;
    return (_centerXFilter.value, _centerYFilter.value);
  }

  void _resetTracking() {
    _candidateId = null;
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
  static const double _minCutoff = 1.5;
  static const double _beta = 0.7;
  static const double _derivativeCutoff = 1;

  double? _rawValue;
  double? _filteredValue;
  double? _filteredDerivative;

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
