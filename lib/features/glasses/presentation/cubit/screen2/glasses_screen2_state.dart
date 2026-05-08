/// Glasses screen 2 state
sealed class GlassesScreen2State {
  const GlassesScreen2State();
}

/// Screen is initializing
class GlassesScreen2Initial extends GlassesScreen2State {
  const GlassesScreen2Initial();
}

/// Screen is updated with data
class GlassesScreen2Updated extends GlassesScreen2State {
  const GlassesScreen2Updated({
    required this.recognizedText,
  });

  final String recognizedText;
}
