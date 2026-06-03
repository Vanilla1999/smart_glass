import 'package:smart_glasses/modules/wear/domain/auth/model/authenticated_user.dart';
import 'package:smart_glasses/modules/wear/models/wear_printer_selection.dart';

class WearSession {
  WearSession._();

  static AuthenticatedUser? _user;
  static WearPrinterSelection? _printerSelection;

  static bool get isAuthorized => _user != null;

  static AuthenticatedUser? get userOrNull => _user;

  static WearPrinterSelection? get printerSelectionOrNull => _printerSelection;

  static bool get hasPrinterSelection => _printerSelection != null;

  static AuthenticatedUser get user =>
      _user ?? (throw StateError('Пользователь не авторизован'));

  static void setUser(AuthenticatedUser user) {
    _user = user;
  }

  static void setPrinterSelection(WearPrinterSelection selection) {
    _printerSelection = selection;
  }

  static void clearPrinterSelection() {
    _printerSelection = null;
  }

  static void clear() {
    _user = null;
    _printerSelection = null;
  }
}
