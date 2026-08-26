enum BarcodeTrackingPhase { candidate, locked, clear }

class BarcodeTrackingEvent {
  const BarcodeTrackingEvent({
    required this.contractVersion,
    required this.sequence,
    required this.candidateId,
    required this.capturedAtElapsedRealtimeNanos,
    required this.detectedAtElapsedRealtimeNanos,
    required this.phase,
    required this.frameWidth,
    required this.frameHeight,
    required this.rotationDegrees,
    required this.mirrored,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  final int contractVersion;
  final int sequence;
  final int candidateId;
  final int capturedAtElapsedRealtimeNanos;
  final int detectedAtElapsedRealtimeNanos;
  final BarcodeTrackingPhase phase;
  final int frameWidth;
  final int frameHeight;
  final int rotationDegrees;
  final bool mirrored;
  final double left;
  final double top;
  final double right;
  final double bottom;

  double get centerX => (left + right) / 2;
  double get centerY => (top + bottom) / 2;

  static BarcodeTrackingEvent? tryParse(dynamic value) {
    if (value is! Map) return null;
    final Map<dynamic, dynamic> map = value;
    final int? contractVersion = _int(map['contractVersion']);
    final int? sequence = _int(map['sequence']);
    final int? candidateId = _int(map['candidateId']);
    final int? captured = _int(map['capturedAtElapsedRealtimeNanos']);
    final int? detected = _int(map['detectedAtElapsedRealtimeNanos']);
    final int? frameWidth = _int(map['frameWidth']);
    final int? frameHeight = _int(map['frameHeight']);
    final int? rotationDegrees = _int(map['rotationDegrees']);
    final double? left = _double(map['left']);
    final double? top = _double(map['top']);
    final double? right = _double(map['right']);
    final double? bottom = _double(map['bottom']);
    final BarcodeTrackingPhase? phase = switch (map['phase']) {
      'candidate' => BarcodeTrackingPhase.candidate,
      'locked' => BarcodeTrackingPhase.locked,
      'clear' => BarcodeTrackingPhase.clear,
      _ => null,
    };
    if (contractVersion != 1 ||
        sequence == null ||
        candidateId == null ||
        captured == null ||
        detected == null ||
        phase == null ||
        frameWidth == null ||
        frameHeight == null ||
        rotationDegrees == null ||
        map['mirrored'] is! bool ||
        left == null ||
        top == null ||
        right == null ||
        bottom == null ||
        frameWidth <= 0 ||
        frameHeight <= 0 ||
        left < 0 ||
        top < 0 ||
        right > 1 ||
        bottom > 1 ||
        left > right ||
        top > bottom) {
      return null;
    }
    return BarcodeTrackingEvent(
      contractVersion: contractVersion!,
      sequence: sequence,
      candidateId: candidateId,
      capturedAtElapsedRealtimeNanos: captured,
      detectedAtElapsedRealtimeNanos: detected,
      phase: phase,
      frameWidth: frameWidth,
      frameHeight: frameHeight,
      rotationDegrees: rotationDegrees,
      mirrored: map['mirrored'] as bool,
      left: left,
      top: top,
      right: right,
      bottom: bottom,
    );
  }

  static int? _int(dynamic value) => value is num ? value.toInt() : null;
  static double? _double(dynamic value) =>
      value is num ? value.toDouble() : null;
}
