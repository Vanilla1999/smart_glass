/// Glasses coordinator state
sealed class GlassesCoordinatorState {
  const GlassesCoordinatorState();
}

/// Coordinator is initializing
class GlassesCoordinatorInitial extends GlassesCoordinatorState {
  const GlassesCoordinatorInitial();
}

/// Coordinator is ready
class GlassesCoordinatorReady extends GlassesCoordinatorState {
  const GlassesCoordinatorReady({
    required this.currentRoute,
  });

  final String currentRoute;
}
