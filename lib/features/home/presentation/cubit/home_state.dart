/// Home screen state
sealed class HomeState {
  const HomeState();
}

/// Home screen is initializing
class HomeInitial extends HomeState {
  const HomeInitial();
}

/// Home screen is loaded
class HomeLoaded extends HomeState {
  const HomeLoaded({
    required this.counter,
  });

  final int counter;
}
