import 'dart:async';

import 'package:smart_glasses/modules/wear/domain/auth/model/authenticated_user.dart';
import 'package:smart_glasses/modules/wear/models/wear_printer_selection.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_authority.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_store.dart';

/// Compatibility facade during the single-state migration.
///
/// Session identity is runtime-authority-owned from MR-S2. Printer selection
/// deliberately remains legacy-owned here until MR-S4.
class WearSession {
  WearSession._();

  static WearRuntimeAuthority? _configuredAuthority;
  static WearRuntimeAuthority? _lazyAuthority;
  static WearPrinterSelection? _printerSelection;

  static final StreamController<WearPrinterSelection?>
      _printerSelectionController =
      StreamController<WearPrinterSelection?>.broadcast();

  static WearRuntimeAuthority get identityAuthority {
    return _configuredAuthority ??=
        _lazyAuthority ??= WearRuntimeAuthority();
  }

  static void configureIdentityAuthority(WearRuntimeAuthority authority) {
    final WearRuntimeAuthority? current = _configuredAuthority;
    if (identical(current, authority)) return;
    if (current != null || _lazyAuthority != null) {
      throw StateError('Wear session identity authority is already configured');
    }
    _configuredAuthority = authority;
  }

  static bool get isAuthorized => identityAuthority.isAuthorized;

  static AuthenticatedUser? get userOrNull => identityAuthority.userOrNull;

  static Stream<AuthenticatedUser> get authorizedStream =>
      identityAuthority.authorizedStream;

  static Stream<void> get clearedStream => identityAuthority.clearedStream;

  static WearPrinterSelection? get printerSelectionOrNull => _printerSelection;

  static bool get hasPrinterSelection => _printerSelection != null;

  static Stream<WearPrinterSelection?> get printerSelectionStream =>
      _printerSelectionController.stream;

  static AuthenticatedUser get user =>
      userOrNull ?? (throw StateError('Пользователь не авторизован'));

  static Future<void> setUser(AuthenticatedUser user) async {
    final WearDispatchResult result = await identityAuthority.authorize(user);
    if (!result.accepted) {
      throw StateError(
        'Wear authorization rejected: ${result.rejectReason?.name}',
      );
    }
  }

  static void setPrinterSelection(WearPrinterSelection selection) {
    _printerSelection = selection;
    if (!_printerSelectionController.isClosed) {
      _printerSelectionController.add(selection);
    }
  }

  static void clearPrinterSelection() {
    _printerSelection = null;
    if (!_printerSelectionController.isClosed) {
      _printerSelectionController.add(null);
    }
  }

  static Future<void> clear() async {
    clearPrinterSelection();
    final WearDispatchResult result = await identityAuthority.clearSession();
    if (!result.accepted) {
      throw StateError(
        'Wear session clear rejected: ${result.rejectReason?.name}',
      );
    }
  }
}
