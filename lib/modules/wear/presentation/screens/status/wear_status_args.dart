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
}
