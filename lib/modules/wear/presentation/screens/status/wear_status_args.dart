enum WearStatusKind { success, error }

enum WearStatusAutoAction { none, pop, go }

class WearStatusScreenArgs {
  const WearStatusScreenArgs({
    required this.kind,
    required this.title,
    required this.message,
    this.details,
    this.autoAfter,
    this.autoRoute,
    this.autoExtra,
    this.autoAction = WearStatusAutoAction.none,
    this.showHome = false,
    this.glassesStatusText,
    this.glassesStatusIcon,
    this.autoStartedAtMillis,
  });

  factory WearStatusScreenArgs.userNotFound() {
    return const WearStatusScreenArgs(
      kind: WearStatusKind.error,
      title: 'Ошибка',
      message: 'Пользователь не найден',
      autoAfter: Duration(seconds: 5),
      autoAction: WearStatusAutoAction.pop,
    );
  }

  final WearStatusKind kind;

  final String title;
  final String message;

  final String? details;

  final Duration? autoAfter;
  final String? autoRoute;
  final Object? autoExtra;

  final WearStatusAutoAction autoAction;

  final bool showHome;

  final String? glassesStatusText;
  final String? glassesStatusIcon;

  /// Wall-clock timestamp for auto action deadline.
  ///
  /// Flutter timers can be delayed while the Android device is sleeping. Passing
  /// the original event timestamp lets the status screen execute the action
  /// immediately after wake if the deadline already passed.
  final int? autoStartedAtMillis;

  WearStatusScreenArgs withAutoStartedAt(int millis) {
    return WearStatusScreenArgs(
      kind: kind,
      title: title,
      message: message,
      details: details,
      autoAfter: autoAfter,
      autoRoute: autoRoute,
      autoExtra: autoExtra,
      autoAction: autoAction,
      showHome: showHome,
      glassesStatusText: glassesStatusText,
      glassesStatusIcon: glassesStatusIcon,
      autoStartedAtMillis: millis,
    );
  }
}
