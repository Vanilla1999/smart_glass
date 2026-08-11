import 'dart:async';

import 'package:smart_glasses/modules/wear/application/wear_background_runtime.dart';
import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/application/wear_status_state.dart';
import 'package:smart_glasses/modules/wear/config/wear_mock_config.dart';
import 'package:smart_glasses/modules/wear/config/wear_session.dart';
import 'package:smart_glasses/modules/wear/domain/price_tag_print/model/barcode_product_info.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/voice_list_matcher.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/voice_utterance_coordinator.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/wear_voice_command.dart';
import 'package:smart_glasses/modules/wear/presentation/glasses/wear_glasses_payload.dart';
import 'package:smart_glasses/modules/wear/presentation/glasses/wear_glasses_voice_hints.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/scan/wear_product_select_screen.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/status/wear_status_args.dart';
import 'package:smart_glasses/modules/wear/theme/wear_images.dart';

typedef WearBarcodeLookup = Future<List<BarcodeProductInfo>> Function(
  String barcode,
);
typedef WearProductPrint = Future<String> Function(BarcodeProductInfo product);
typedef WearScanNavigation = Future<void> Function(
  WearScreenId screen, {
  Object? extra,
  bool replaceCurrent,
});
typedef WearScanStatusPublisher = Future<void> Function(
  WearStatusScreenArgs args,
  WearStatusCompletion completion,
);

enum WearScanRuntimePhase { waiting, lookup, selection, printing, status }

class WearScanRuntimeState {
  const WearScanRuntimeState({
    required this.phase,
    required this.screen,
    required this.barcode,
    required this.products,
    required this.focusedIndex,
    required this.productName,
    required this.loadingText,
    required this.loadingIcon,
    required this.status,
    required this.lastAcceptedBarcode,
  });

  factory WearScanRuntimeState.initial() => const WearScanRuntimeState(
        phase: WearScanRuntimePhase.waiting,
        screen: WearScreenId.scanIdle,
        barcode: null,
        products: <BarcodeProductInfo>[],
        focusedIndex: 0,
        productName: null,
        loadingText: 'ШК отсканирован, распознаю...',
        loadingIcon: WearImages.barcode,
        status: null,
        lastAcceptedBarcode: null,
      );

  final WearScanRuntimePhase phase;
  final WearScreenId screen;
  final String? barcode;
  final List<BarcodeProductInfo> products;
  final int focusedIndex;
  final String? productName;
  final String loadingText;
  final String loadingIcon;
  final WearStatusScreenArgs? status;
  final String? lastAcceptedBarcode;

  bool get busy =>
      phase == WearScanRuntimePhase.lookup ||
      phase == WearScanRuntimePhase.printing;
}

class WearScanRuntime implements WearBackgroundRuntime {
  WearScanRuntime({
    required WearBarcodeLookup lookupBarcode,
    required WearProductPrint printProduct,
    required WearScanNavigation navigate,
    required WearScanStatusPublisher showStatus,
  })  : _lookupBarcode = lookupBarcode,
        _printProduct = printProduct,
        _navigate = navigate,
        _showStatusOutput = showStatus;

  static const int _pageSize = 4;
  final WearBarcodeLookup _lookupBarcode;
  final WearProductPrint _printProduct;
  final WearScanNavigation _navigate;
  final WearScanStatusPublisher _showStatusOutput;
  final StreamController<WearBackgroundScreenUpdate> _updates =
      StreamController<WearBackgroundScreenUpdate>.broadcast();
  final StreamController<WearScanRuntimeState> _states =
      StreamController<WearScanRuntimeState>.broadcast();

  WearScreenId _screen = WearScreenId.scanIdle;
  List<BarcodeProductInfo> _products = const <BarcodeProductInfo>[];
  int _focusedIndex = 0;
  bool _loading = false;
  String? _lastBarcode;
  int _generation = 0;
  String? _barcode;
  String? _productName;
  String _loadingText = 'ШК отсканирован, распознаю...';
  String _loadingIcon = WearImages.barcode;
  WearStatusScreenArgs? _status;
  WearScanRuntimePhase _phase = WearScanRuntimePhase.waiting;

  @override
  Stream<WearBackgroundScreenUpdate> get updates => _updates.stream;

  Stream<WearScanRuntimeState> get stateStream => _states.stream;

  WearScanRuntimeState get state => WearScanRuntimeState(
        phase: _phase,
        screen: _screen,
        barcode: _barcode,
        products: List<BarcodeProductInfo>.unmodifiable(_products),
        focusedIndex: _focusedIndex,
        productName: _productName,
        loadingText: _loadingText,
        loadingIcon: _loadingIcon,
        status: _status,
        lastAcceptedBarcode: _lastBarcode,
      );

  @override
  bool handles(WearScreenId screen) {
    return screen == WearScreenId.scanIdle ||
        screen == WearScreenId.productSelect;
  }

  @override
  bool acceptsBarcode(WearScreenId screen) {
    return screen == WearScreenId.scanIdle && !_loading;
  }

  @override
  bool supportsCommand(WearScreenId screen, WearVoiceCommand command) {
    return screen == WearScreenId.productSelect &&
        <WearVoiceCommand>{
          WearVoiceCommand.up,
          WearVoiceCommand.down,
          WearVoiceCommand.select,
          WearVoiceCommand.nextPage,
          WearVoiceCommand.previousPage,
        }.contains(command);
  }

  @override
  Future<void> enterScreen(WearScreenId screen, {Object? extra}) async {
    if (!handles(screen)) return;
    _screen = screen;
    _focusedIndex = 0;
    _status = null;
    if (screen == WearScreenId.scanIdle) {
      _lastBarcode = null;
      _barcode = null;
      _products = const <BarcodeProductInfo>[];
      _phase = WearScanRuntimePhase.waiting;
    } else if (extra is WearProductSelectArgs) {
      _products = extra.products;
      _barcode = extra.barcode;
      _phase = WearScanRuntimePhase.selection;
    }
    _publish(_payload());
  }

  @override
  Future<bool> handleBarcode(WearScreenId screen, String barcode) async {
    if (screen != WearScreenId.scanIdle || _loading) return false;
    final String value = barcode.trim();
    if (value.isEmpty || value == _lastBarcode) return true;
    _lastBarcode = value;
    _barcode = value;
    if (WearSession.printerSelectionOrNull == null) {
      await _showStatus(isError: true, message: 'Не выбраны принтеры');
      return true;
    }
    if (WearSession.userOrNull == null) {
      await _showStatus(isError: true, message: 'Пользователь не авторизован');
      return true;
    }
    _loading = true;
    _phase = WearScanRuntimePhase.lookup;
    _loadingText = 'ШК отсканирован, распознаю...';
    _loadingIcon = WearImages.barcode;
    final int generation = _generation;
    _publish(WearGlassesPayload.scanLoading());
    try {
      _products = WearMockConfig.isEnabled
          ? _mockProducts(value)
          : await _lookupBarcode(value);
      if (generation != _generation) return true;
      if (_products.isEmpty) {
        await _showStatus(isError: true, message: 'Товар не найден');
      } else if (_products.length == 1) {
        await _print(_products.single);
      } else {
        _loading = false;
        _phase = WearScanRuntimePhase.selection;
        await _navigate(
          WearScreenId.productSelect,
          extra: WearProductSelectArgs(barcode: value, products: _products),
        );
      }
    } catch (error) {
      if (generation != _generation) return true;
      await _showStatus(isError: true, message: _messageFor(error));
    }
    return true;
  }

  @override
  Future<bool> handleCommand(
    WearScreenId screen,
    WearVoiceCommand command,
  ) async {
    if (screen != WearScreenId.productSelect || _loading) return false;
    switch (command) {
      case WearVoiceCommand.up:
        _move(-1);
        return true;
      case WearVoiceCommand.down:
        _move(1);
        return true;
      case WearVoiceCommand.nextPage:
        _move(_pageSize);
        return true;
      case WearVoiceCommand.previousPage:
        _move(-_pageSize);
        return true;
      case WearVoiceCommand.select:
        if (_products.isNotEmpty) {
          await _print(
            _products[_focusedIndex.clamp(0, _products.length - 1)],
          );
        }
        return true;
      default:
        return false;
    }
  }

  @override
  Future<bool> handlePhrase(WearScreenId screen, String phrase) async {
    if (screen != WearScreenId.productSelect || _loading) return false;
    final VoiceListMatch<BarcodeProductInfo> match = VoiceListMatcher.match(
      phrase,
      _products,
      (BarcodeProductInfo product) => product.name,
    );
    if (match.type != VoiceListMatchType.unique) return false;
    await _print(match.item!);
    return true;
  }

  @override
  Future<bool> handleDynamicItem(WearScreenId screen, String itemId) async {
    if (screen != WearScreenId.productSelect || _loading) return false;
    for (final BarcodeProductInfo product in _products) {
      if (product.id.toString() != itemId) continue;
      await _print(product);
      return true;
    }
    return false;
  }

  void setFocusedIndex(int index) {
    if (_products.isEmpty || _loading) return;
    _focusedIndex = index.clamp(0, _products.length - 1);
    _publish(_payload());
  }

  Future<void> selectProduct(BarcodeProductInfo product) async {
    if (_loading || !_products.any((item) => item.id == product.id)) return;
    await _print(product);
  }

  Future<void> _print(BarcodeProductInfo product) async {
    _loading = true;
    _phase = WearScanRuntimePhase.printing;
    _productName = product.name.trim().isEmpty ? 'Без названия' : product.name;
    _loadingText = 'Отправляем на печать...';
    _loadingIcon = WearImages.printer;
    final int generation = _generation;
    _publish(WearGlassesPayload.printing(productName: product.name));
    try {
      final String printer = WearMockConfig.isEnabled
          ? (product.id.isEven
              ? WearSession.printerSelectionOrNull!.yellowPrinter.name
              : WearSession.printerSelectionOrNull!.whitePrinter.name)
          : await _printProduct(product);
      if (generation != _generation) return;
      await _showStatus(
        isError: false,
        message: product.name,
        details: printer,
      );
    } catch (error) {
      if (generation != _generation) return;
      await _showStatus(isError: true, message: _messageFor(error));
    }
  }

  Future<void> _showStatus({
    required bool isError,
    required String message,
    String? details,
  }) async {
    _loading = false;
    final WearStatusScreenArgs args = WearStatusScreenArgs(
      kind: isError ? WearStatusKind.error : WearStatusKind.success,
      title: isError ? 'Ошибка' : 'Ценник отправлен на печать',
      message: message,
      details: details,
      autoAfter: const Duration(seconds: 5),
      autoAction: WearStatusAutoAction.none,
    );
    _status = args;
    _phase = WearScanRuntimePhase.status;
    _emitState();
    await _showStatusOutput(
      args,
      const WearStatusCompletion.goTo(WearScreenId.scanIdle),
    );
  }

  @override
  Future<void> reset() async {
    _generation += 1;
    _screen = WearScreenId.scanIdle;
    _products = const <BarcodeProductInfo>[];
    _focusedIndex = 0;
    _loading = false;
    _lastBarcode = null;
    _barcode = null;
    _productName = null;
    _status = null;
    _phase = WearScanRuntimePhase.waiting;
    _loadingText = 'ШК отсканирован, распознаю...';
    _loadingIcon = WearImages.barcode;
    _emitState();
  }

  void _move(int delta) {
    if (_products.isEmpty) return;
    _focusedIndex = (_focusedIndex + delta).clamp(0, _products.length - 1);
    _publish(_payload());
  }

  @override
  VoiceDynamicItemsSnapshot dynamicVoiceItemsFor(WearScreenId screen) {
    if (screen != WearScreenId.productSelect) {
      return VoiceDynamicItemsSnapshot.empty;
    }
    final List<VoiceDynamicItem> items = _products
        .map(
          (BarcodeProductInfo product) => VoiceDynamicItem(
            id: product.id.toString(),
            label: product.name,
          ),
        )
        .toList(growable: false);
    return VoiceDynamicItemsSnapshot(
      revision: Object.hashAll(
        items.map((VoiceDynamicItem item) => item.revisionHash),
      ),
      items: items,
    );
  }

  @override
  void restorePresentationState(WearScreenId screen, Object state) {}

  @override
  Object? presentationStateFor(WearScreenId screen) => null;

  WearGlassesPayload _payload() {
    if (_screen == WearScreenId.scanIdle) {
      return WearGlassesPayload.scanWaiting();
    }
    if (_products.isEmpty) {
      return WearGlassesPayload.status(
        isError: true,
        title: 'Дубль ШК',
        statusText: 'Список товаров пуст',
      );
    }
    final int selected = _focusedIndex.clamp(0, _products.length - 1);
    final int start = selected ~/ _pageSize * _pageSize;
    final List<BarcodeProductInfo> visible =
        _products.skip(start).take(_pageSize).toList(growable: false);
    final VoiceDynamicItemsSnapshot snapshot =
        dynamicVoiceItemsFor(WearScreenId.productSelect);
    return WearGlassesPayload(
      screenType: WearGlassesScreenType.productSelect,
      phase: WearGlassesPhase.idle,
      title: 'Дубль ШК',
      subtitle: 'Выберите нужный товар',
      items: visible
          .map((BarcodeProductInfo product) => product.name)
          .toList(growable: false),
      voiceHints: WearGlassesVoiceHints.forVisibleItems(
        screen: WearScreenId.productSelect,
        snapshot: snapshot,
        visibleItemIds: visible
            .map((BarcodeProductInfo product) => product.id.toString())
            .toList(growable: false),
      ),
      selectedIndex: selected - start,
    );
  }

  void _publish(WearGlassesPayload payload) {
    _emitState();
    if (_updates.isClosed) return;
    _updates.add(WearBackgroundScreenUpdate(screen: _screen, payload: payload));
  }

  void _emitState() {
    if (!_states.isClosed) _states.add(state);
  }

  List<BarcodeProductInfo> _mockProducts(String barcode) {
    if (barcode.endsWith('2')) {
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
        name: 'MOCK Товар $barcode',
        articleRest: 42,
      ),
    ];
  }

  String _messageFor(Object error) {
    final String message = error.toString();
    return message.startsWith('Exception: ')
        ? message.substring('Exception: '.length)
        : message;
  }

  @override
  Future<void> dispose() async {
    await reset();
    await _updates.close();
    await _states.close();
  }
}
