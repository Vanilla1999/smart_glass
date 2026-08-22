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

  static WearRuntimeAuthority? _identityAuthority;
  static AuthenticatedUser? _bootstrapUser;
  static WearPrinterSelection? _printerSelection;

  static final StreamController<AuthenticatedUser> _bootstrapAuthorized =
      StreamController<AuthenticatedUser>.broadcast();
  static final StreamController<void> _bootstrapCleared =
      StreamController<void>.broadcast();
  static final StreamController<WearPrinterSelection?>
      _printerSelectionController =
      StreamController<WearPrinterSelection?>.broadcast();

  static void configureIdentityAuthority(WearRuntimeAuthority authority) {
    final WearRuntimeAuthority? current = _identityAuthority;
    if (identical(current, authority)) return;
    if (current != null) {
      throw StateError('Wear session identity authority is already configured');
    }
    if (_bootstrapUser != null) {
      throw StateError(
        'Wear identity authority must be configured before authorization',
      );
    }
    _identityAuthority = authority;
  }

  static bool get hasIdentityAuthority => _identityAuthority != null;

  static bool get isAuthorized =>
      _identityAuthority?.isAuthorized ?? _bootstrapUser != null;

  static AuthenticatedUser? get userOrNull =>
      _identityAuthority?.userOrNull ?? _bootstrapUser;

  static Stream<AuthenticatedUser> get authorizedStream =>
      _identityAuthority?.authorizedStream ?? _bootstrapAuthorized.stream;

  static Stream<void> get clearedStream =>
      _identityAuthority?.clearedStream ?? _bootstrapCleared.stream;

  static WearPrinterSelection? get printerSelectionOrNull => _printerSelection;

  static bool get hasPrinterSelection => _printerSelection != null;

  static Stream<WearPrinterSelection?> get printerSelectionStream =>
      _printerSelectionController.stream;

  static AuthenticatedUser get user =>
      userOrNull ?? (throw StateError('Пользователь не авторизован'));

  static Future<void> setUser(AuthenticatedUser user) async {
    final WearRuntimeAuthority? authority = _identityAuthority;
    if (authority == null) {
      _bootstrapUser = user;
      if (!_bootstrapAuthorized.isClosed) _bootstrapAuthorized.add(user);
      return;
    }
    final WearDispatchResult result = await authority.authorize(user);
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
    final WearRuntimeAuthority? authority = _identityAuthority;
    if (authority == null) {
      final bool wasAuthorized = _bootstrapUser != null;
      _bootstrapUser = null;
      if (wasAuthorized && !_bootstrapCleared.isClosed) {
        _bootstrapCleared.add(null);
      }
      return;
    }
    final WearDispatchResult result = await authority.clearSession();
    if (!result.accepted) {
      throw StateError(
        'Wear session clear rejected: ${result.rejectReason?.name}',
      );
    }
  }
}
