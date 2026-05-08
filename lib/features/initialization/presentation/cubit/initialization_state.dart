/// Initialization state
sealed class InitializationState {
  const InitializationState();
}

/// Initialization in progress
class InitializationInProgress extends InitializationState {
  const InitializationInProgress({
    required this.scannerReady,
    required this.voiceReady,
  });
  
  final bool scannerReady;
  final bool voiceReady;
  
  /// Calculate progress (0.0 to 1.0)
  double get progress {
    int completed = 0;
    if (scannerReady) completed++;
    if (voiceReady) completed++;
    return completed / 2.0;
  }
  
  /// Check if initialization is completed (voice is required, scanner is optional)
  bool get isCompleted => voiceReady;
}

/// Initialization completed successfully
class InitializationCompleted extends InitializationState {
  const InitializationCompleted();
}
