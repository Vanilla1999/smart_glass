/// Glasses screen 1 state
sealed class GlassesScreenState {
  const GlassesScreenState();
}

/// Screen is initializing
class GlassesScreenInitial extends GlassesScreenState {
  const GlassesScreenInitial();
}

/// Screen is updated with data
class GlassesScreenUpdated extends GlassesScreenState {
  const GlassesScreenUpdated({
    required this.counter,
    required this.recognizedText,
  });

  final int counter;
  final String recognizedText;
}
