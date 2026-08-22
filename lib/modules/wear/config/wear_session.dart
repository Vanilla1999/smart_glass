import 'package:smart_glasses/modules/wear/domain/auth/model/authenticated_user.dart';
import 'package:smart_glasses/modules/wear/models/wear_printer_selection.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_authority.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_store.dart';

/// Compatibility facade during the single-state migration.
///
/// Identity and printer selection are aggregate-owned. Legacy callers may
/// read them here; compatibility writes are translated into store intents.
class WearSession {
  WearSession._();

  static WearRuntimeAuthority? _configuredAuthority;
  static WearRuntimeAuthority? _lazyAuthority;

  static WearRuntimeAuthority get identityAuthority {
    final WearRuntimeAuthority? configured = _configuredAuthority;
    if (configured != null) return configured;
    return _lazyAuthority ??= WearRuntimeAuthority();
  }

  static WearRuntimeAuthority beginNewIdentityRuntime() {
    final WearRuntimeAuthority current = identityAuthority;
    if (!current.state.terminal) return current;
    if (_configuredAuthority != null) {
      throw StateError(
        'A configured terminal authority must be explicitly replaced',
      );
    }
    return _lazyAuthority = WearRuntimeAuthority();
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

  static WearPrinterSelection? get printerSelectionOrNull =>
      identityAuthority.printerTask.selection;

  static bool get hasPrinterSelection => printerSelectionOrNull != null;

  static Stream<WearPrinterSelection?> get printerSelectionStream {
    return identityAuthority.states
        .map(
          (WearRuntimeState state) => state
              .payloadAs<WearAggregatePayload>()
              .features as WearRuntimeFeaturePayload,
        )
        .map((WearRuntimeFeaturePayload features) => features.printer.selection)
        .distinct(_sameSelection);
  }

  static AuthenticatedUser get user =>
      userOrNull ?? (throw StateError('Пользователь не авторизован'));

  static Future<void> setUser(AuthenticatedUser user) async {
    final WearDispatchResult result = await identityAuthority.authorize(user);
    _throwIfRejected('authorization', result);
  }

  static Future<void> setPrinterSelection(
    WearPrinterSelection selection,
  ) async {
    final WearDispatchResult result =
        await identityAuthority.importPrinterSelection(selection);
    _throwIfRejected('printer selection import', result);
  }

  static Future<void> clearPrinterSelection() async {
    final WearDispatchResult result =
        await identityAuthority.clearPrinterSelection();
    _throwIfRejected('printer selection clear', result);
  }

  static Future<void> clear() async {
    final WearDispatchResult result = await identityAuthority.clearSession();
    _throwIfRejected('session clear', result);
  }

  static bool _sameSelection(
    WearPrinterSelection? left,
    WearPrinterSelection? right,
  ) {
    if (identical(left, right)) return true;
    if (left == null || right == null) return false;
    return left.whitePrinter.id == right.whitePrinter.id &&
        left.whitePrinter.name == right.whitePrinter.name &&
        left.yellowPrinter.id == right.yellowPrinter.id &&
        left.yellowPrinter.name == right.yellowPrinter.name;
  }

  static void _throwIfRejected(
    String action,
    WearDispatchResult result,
  ) {
    if (result.accepted) return;
    throw StateError(
      'Wear $action rejected: ${result.rejectReason?.name}',
    );
  }
}
