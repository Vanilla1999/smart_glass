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
    final WearRuntimeAuthority? configured = _configuredAuthority;
    if (configured != null) return configured;

    final WearRuntimeAuthority? current = _lazyAuthority;
    if (current == null || current.state.terminal) {
      _lazyAuthority = WearRuntimeAuthority();
    }
    return _lazyAuthority!;
  }

  static void configureIdentityAuthority(WearRuntimeAuthority authority) {
    final WearRuntimeAuthority? configured = _configuredAuthority;
    if (identical(configured, authority)) return;
    if (configured != null && !configured.state.terminal) {
      throw StateError('Wear session identity authority is already configured');
    }
    final WearRuntimeAuthority? lazy = _lazyAuthority;
    if (lazy != null && !lazy.state.terminal) {
      throw StateError(
        'Lazy Wear identity authority was already created; configure earlier',
      );
    }
    _lazyAuthority = null;
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
