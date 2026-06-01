import 'package:smart_glasses/modules/wear/domain/auth/model/authenticated_user.dart';

class WearSession {
  WearSession._();

  static AuthenticatedUser? _user;

  static bool get isAuthorized => _user != null;

  static AuthenticatedUser? get userOrNull => _user;

  static AuthenticatedUser get user =>
      _user ?? (throw StateError('Пользователь не авторизован'));

  static void setUser(AuthenticatedUser user) {
    _user = user;
  }

  static void clear() {
    _user = null;
  }
}
