import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:multi_scanner/multi_scanner.dart';
import 'package:smart_glasses/modules/wear/config/wear_dependencies.dart';
import 'package:smart_glasses/modules/wear/config/wear_session.dart';
import 'package:smart_glasses/modules/wear/domain/auth/model/authenticated_user.dart';
import 'package:smart_glasses/modules/wear/domain/price_tag_print/model/barcode_product_info.dart';
import 'package:smart_glasses/modules/wear/domain/price_tag_print/use_case/get_barcode_info_use_case.dart';
import 'package:smart_glasses/modules/wear/domain/price_tag_print/use_case/print_price_tag_use_case.dart';
import 'package:smart_glasses/modules/wear/models/wear_printer_selection.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/scan/wear_product_select_screen.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/status/wear_status_args.dart';
import 'package:smart_glasses/modules/wear/presentation/utils/wear_feedback.dart';

final AutoDisposeStateNotifierProviderFamily<WearScanNotifier, WearScanState,
        WearPrinterSelection?> wearScanNotifierProvider =
    StateNotifierProvider.autoDispose
        .family<WearScanNotifier, WearScanState, WearPrinterSelection?>(
  (Ref ref, WearPrinterSelection? selection) =>
      WearScanNotifier(ref, selection),
);

enum WearScanPhase { idle, loading }

class WearScanState {
  const WearScanState({
    required this.phase,
    required this.navStatus,
    required this.navSelect,
  });

  factory WearScanState.initial() {
    return const WearScanState(
      phase: WearScanPhase.idle,
      navStatus: null,
      navSelect: null,
    );
  }

  final WearScanPhase phase;
  final WearStatusScreenArgs? navStatus;
  final WearProductSelectArgs? navSelect;

  bool get isLoading => phase == WearScanPhase.loading;

  WearScanState copyWith({
    WearScanPhase? phase,
    WearStatusScreenArgs? navStatus,
    WearProductSelectArgs? navSelect,
    bool clearNav = false,
  }) {
    return WearScanState(
      phase: phase ?? this.phase,
      navStatus: clearNav ? null : (navStatus ?? this.navStatus),
      navSelect: clearNav ? null : (navSelect ?? this.navSelect),
    );
  }
}

class WearScanNotifier extends StateNotifier<WearScanState>
    implements MultiScannerDelegate {
  WearScanNotifier(Ref ref, this._selection)
      : super(WearScanState.initial()) {
    // TODO: remove stub dep
    // _scannerNotifier = ref.read(scannerNotifierProvider.notifier);
    // _wearMetricsService = ref.read(wearMetricsServiceProvider.notifier);
    // _scannerNotifier.multiScanner.addDelegate(this);
  }

  final WearPrinterSelection? _selection;
  // late final ScannerNotifier _scannerNotifier;
  // late final WearMetricsService _wearMetricsService;
  @override
  void dispose() {
    // _scannerNotifier.multiScanner.removeDelegate(this);
    super.dispose();
  }

  @override
  bool? onScanEvent(String payload) {
    // _wearMetricsService.showWakeNotification();
    // if (_scannerNotifier.onScanEvent(payload) == true) {
    //   return true;
    // }
    handleBarcode(payload);
    return true;
  }

  @override
  bool? onErrorScan(Exception error) {
    return false;
  }

  Future<void> handleBarcode(String barcode) async {
    if (state.isLoading) return;
    final String trimmed = barcode.trim();
    if (trimmed.isEmpty) return;

    final WearPrinterSelection? selection = _selection;
    if (selection == null) {
      _emitStatus(
        const WearStatusScreenArgs(
          kind: WearStatusKind.error,
          title: 'Ошибка',
          message: 'Не выбраны принтеры',
          autoAfter: Duration(seconds: 4),
          autoAction: WearStatusAutoAction.pop,
        ),
      );
      return;
    }

    final AuthenticatedUser? user = WearSession.userOrNull;
    if (user == null) {
      _emitStatus(
        const WearStatusScreenArgs(
          kind: WearStatusKind.error,
          title: 'Ошибка',
          message: 'Пользователь не авторизован',
          autoAfter: Duration(seconds: 4),
          autoAction: WearStatusAutoAction.pop,
        ),
      );
      return;
    }

    state = state.copyWith(phase: WearScanPhase.loading, clearNav: true);
    try {
      final GetBarcodeInfoUseCase infoUseCase =
          WearDependencies.I.getBarcodeInfoUseCase();
      final List<BarcodeProductInfo> products =
          await infoUseCase.call(trimmed);
      if (!mounted) return;

      if (products.isEmpty) {
        _emitStatus(
          const WearStatusScreenArgs(
            kind: WearStatusKind.error,
            title: 'Ошибка',
            message: 'Товар не найден',
            autoAfter: Duration(seconds: 5),
            autoAction: WearStatusAutoAction.pop,
          ),
        );
        return;
      }

      if (products.length == 1) {
        await _printProductInternal(
          product: products.first,
          user: user,
          selection: selection,
        );
        return;
      }

      state = state.copyWith(
        phase: WearScanPhase.idle,
        navSelect: WearProductSelectArgs(
          barcode: trimmed,
          products: products,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      _emitStatus(
        WearStatusScreenArgs(
          kind: WearStatusKind.error,
          title: 'Ошибка',
          message: _asUiMessage(error),
          autoAfter: const Duration(seconds: 5),
          autoAction: WearStatusAutoAction.pop,
        ),
      );
    }
  }

  Future<void> printSelectedProduct(BarcodeProductInfo product) async {
    if (state.isLoading) return;
    final WearPrinterSelection? selection = _selection;
    final AuthenticatedUser? user = WearSession.userOrNull;
    if (selection == null || user == null) {
      _emitStatus(
        const WearStatusScreenArgs(
          kind: WearStatusKind.error,
          title: 'Ошибка',
          message: 'Недостаточно данных для печати',
          autoAfter: Duration(seconds: 4),
          autoAction: WearStatusAutoAction.pop,
        ),
      );
      return;
    }
    state = state.copyWith(phase: WearScanPhase.loading, clearNav: true);
    await _printProductInternal(
      product: product,
      user: user,
      selection: selection,
    );
  }

  Future<void> _printProductInternal({
    required BarcodeProductInfo product,
    required AuthenticatedUser user,
    required WearPrinterSelection selection,
  }) async {
    try {
      final PrintPriceTagUseCase printUseCase =
          WearDependencies.I.printPriceTagUseCase;
      final String printerName = await printUseCase.call(
        userId: user.idUser,
        employeeId: user.idEmployee,
        articleId: product.id,
        whiteTagsPrinterName: selection.whitePrinter.name,
        yellowTagsPrinterName: selection.yellowPrinter.name,
      );
      if (!mounted) return;
      await WearFeedback.play(WearStatusKind.success);
      _emitStatus(
        WearStatusScreenArgs(
          kind: WearStatusKind.success,
          title: 'Ценник отправлен на печать',
          message: _resolveProductTitle(product),
          details: printerName,
          autoAfter: const Duration(seconds: 5),
          autoAction: WearStatusAutoAction.pop,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      await WearFeedback.play(WearStatusKind.error);
      _emitStatus(
        WearStatusScreenArgs(
          kind: WearStatusKind.error,
          title: 'Ошибка',
          message: _asUiMessage(error),
          autoAfter: const Duration(seconds: 5),
          autoAction: WearStatusAutoAction.pop,
        ),
      );
    }
  }

  void consumeNavigation() {
    state = state.copyWith(clearNav: true);
  }

  void _emitStatus(WearStatusScreenArgs args) {
    state = state.copyWith(
      phase: WearScanPhase.idle,
      navStatus: args,
    );
  }

  String _resolveProductTitle(BarcodeProductInfo product) {
    final String? name = product.name;
    if (name == null || name.trim().isEmpty) {
      return 'Без названия';
    }
    return name;
  }

  String _asUiMessage(Object error) {
    final String raw = error.toString();
    if (raw.startsWith('Exception: ')) {
      return raw.substring('Exception: '.length);
    }
    return raw;
  }
}
