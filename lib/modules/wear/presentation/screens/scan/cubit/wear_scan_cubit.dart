import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smart_glasses/modules/wear/config/wear_dependencies.dart';
import 'package:smart_glasses/modules/wear/config/wear_mock_config.dart';
import 'package:smart_glasses/modules/wear/config/wear_session.dart';
import 'package:smart_glasses/modules/wear/domain/auth/model/authenticated_user.dart';
import 'package:smart_glasses/modules/wear/domain/price_tag_print/model/barcode_product_info.dart';
import 'package:smart_glasses/modules/wear/domain/price_tag_print/use_case/get_barcode_info_use_case.dart';
import 'package:smart_glasses/modules/wear/domain/price_tag_print/use_case/print_price_tag_use_case.dart';
import 'package:smart_glasses/modules/wear/models/wear_printer.dart';
import 'package:smart_glasses/modules/wear/models/wear_printer_selection.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/scan/wear_product_select_screen.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/status/wear_status_args.dart';
import 'package:smart_glasses/modules/wear/presentation/utils/wear_feedback.dart';
import 'package:smart_glasses/modules/wear/theme/wear_images.dart';

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
    required this.loadingText,
    required this.loadingIcon,
    this.productName,
  });

  factory WearScanState.initial() {
    return const WearScanState(
      phase: WearScanPhase.idle,
      navStatus: null,
      navSelect: null,
      loadingText: 'ШК отсканирован, распознаю...',
      loadingIcon: WearImages.barcode,
    );
  }

  final WearScanPhase phase;
  final WearStatusScreenArgs? navStatus;
  final WearProductSelectArgs? navSelect;
  final String loadingText;
  final String loadingIcon;
  final String? productName;

  bool get isLoading => phase == WearScanPhase.loading;

  bool get isPrinting => isLoading && loadingIcon == WearImages.printer;

  WearScanState copyWith({
    WearScanPhase? phase,
    WearStatusScreenArgs? navStatus,
    WearProductSelectArgs? navSelect,
    String? loadingText,
    String? loadingIcon,
    String? productName,
    bool clearNav = false,
  }) {
    return WearScanState(
      phase: phase ?? this.phase,
      navStatus: clearNav ? null : (navStatus ?? this.navStatus),
      navSelect: clearNav ? null : (navSelect ?? this.navSelect),
      loadingText: loadingText ?? this.loadingText,
      loadingIcon: loadingIcon ?? this.loadingIcon,
      productName: productName ?? this.productName,
    );
  }
}

class WearScanNotifier extends StateNotifier<WearScanState> {
  WearScanNotifier(Ref ref, this._selection) : super(WearScanState.initial());

  final WearPrinterSelection? _selection;
  String? _lastAcceptedBarcode;

  Future<void> handleBarcode(String barcode) async {
    if (state.isLoading) return;
    final String trimmed = barcode.trim();
    if (trimmed.isEmpty) return;
    if (_lastAcceptedBarcode == trimmed) return;

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

    state = state.copyWith(
      phase: WearScanPhase.loading,
      loadingText: 'ШК отсканирован, распознаю...',
      loadingIcon: WearImages.barcode,
      clearNav: true,
    );
    _lastAcceptedBarcode = trimmed;
    try {
      if (WearMockConfig.isEnabled) {
        await _handleMockBarcode(
          barcode: trimmed,
          user: user,
          selection: selection,
        );
        return;
      }

      final GetBarcodeInfoUseCase infoUseCase =
          WearDependencies.I.getBarcodeInfoUseCase();
      final List<BarcodeProductInfo> products = await infoUseCase.call(trimmed);
      if (!mounted) return;

      if (products.isEmpty) {
        _emitStatus(
          const WearStatusScreenArgs(
            kind: WearStatusKind.error,
            title: 'Ошибка',
            message: 'Товар не найден',
            glassesStatusText: 'Ценник не найден',
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
          glassesStatusText: 'Ошибка сканирования',
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
    state = state.copyWith(
      phase: WearScanPhase.loading,
      loadingText: 'Отправляем на печать...',
      loadingIcon: WearImages.printer,
      clearNav: true,
    );
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
    final String resolvedName = _resolveProductTitle(product);
    state = state.copyWith(
      loadingText: 'Отправляем на печать...',
      loadingIcon: WearImages.printer,
      productName: resolvedName,
    );
    try {
      if (WearMockConfig.isEnabled) {
        await Future<void>.delayed(_mockStageDelay);
        if (!mounted) return;
        state = state.copyWith(
          loadingText: 'Печатаю...',
          loadingIcon: WearImages.printer,
        );
        await Future<void>.delayed(_mockStageDelay);
        if (!mounted) return;
        final WearPrinter mockPrinter = product.id.isEven
            ? selection.yellowPrinter
            : selection.whitePrinter;
        await WearFeedback.play(WearStatusKind.success);
        _emitStatus(
          WearStatusScreenArgs(
            kind: WearStatusKind.success,
            title: 'Ценник отправлен на печать',
            message: _resolveProductTitle(product),
            details: 'MOCK: ${mockPrinter.name}',
            autoAfter: const Duration(seconds: 5),
            autoAction: WearStatusAutoAction.pop,
          ),
        );
        return;
      }

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
          glassesStatusText: 'Ошибка при печати',
          autoAfter: const Duration(seconds: 5),
          autoAction: WearStatusAutoAction.pop,
        ),
      );
    }
  }

  void consumeNavigation() {
    state = state.copyWith(clearNav: true);
  }

  void allowRepeatLastBarcode() {
    _lastAcceptedBarcode = null;
  }

  void _emitStatus(WearStatusScreenArgs args) {
    state = state.copyWith(
      phase: WearScanPhase.idle,
      navStatus: args,
    );
  }

  Future<void> _handleMockBarcode({
    required String barcode,
    required AuthenticatedUser user,
    required WearPrinterSelection selection,
  }) async {
    state = state.copyWith(
      loadingText: 'ШК отсканирован, распознаю...',
      loadingIcon: WearImages.barcode,
    );
    await Future<void>.delayed(_mockStageDelay);
    if (!mounted) return;

    final List<BarcodeProductInfo> products = _mockProductsForBarcode(barcode);
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
        barcode: barcode,
        products: products,
      ),
    );
  }

  static const Duration _mockStageDelay = Duration(seconds: 5);

  List<BarcodeProductInfo> _mockProductsForBarcode(String barcode) {
    final String normalized = barcode.trim();
    if (normalized.endsWith('2')) {
      return <BarcodeProductInfo>[
        BarcodeProductInfo(
          id: 1002001,
          name: 'MOCK Молоко 2,5% 930 мл',
          articleRest: 24,
        ),
        BarcodeProductInfo(
          id: 1002002,
          name: 'MOCK Молоко 3,2% 930 мл',
          articleRest: 16,
        ),
      ];
    }
    return <BarcodeProductInfo>[
      BarcodeProductInfo(
        id: 1001001,
        name: normalized.isEmpty ? 'MOCK Товар' : 'MOCK Товар $normalized',
        articleRest: 42,
      ),
    ];
  }

  String _resolveProductTitle(BarcodeProductInfo product) {
    final String name = product.name;
    if (name.trim().isEmpty) {
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
