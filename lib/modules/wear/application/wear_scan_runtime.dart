import 'dart:async';

import 'package:smart_glasses/modules/wear/application/wear_background_runtime.dart';
import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
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

typedef WearBarcodeLookup = Future<List<BarcodeProductInfo>> Function(
  String barcode,
);
typedef WearProductPrint = Future<String> Function(BarcodeProductInfo product);
typedef WearScanNavigation = Future<void> Function(
  WearScreenId screen, {
  Object? extra,
  bool replaceCurrent,
});

class WearScanRuntime implements WearBackgroundRuntime {
  WearScanRuntime({
    required WearBarcodeLookup lookupBarcode,
    required WearProductPrint printProduct,
    required WearScanNavigation navigate,
  })  : _lookupBarcode = lookupBarcode,
        _printProduct = printProduct,
        _navigate = navigate;

  static const int _pageSize = 4;
  final WearBarcodeLookup _lookupBarcode;
  final WearProductPrint _printProduct;
  final WearScanNavigation _navigate;
  final StreamController<WearBackgroundScreenUpdate> _updates =
      StreamController<WearBackgroundScreenUpdate>.broadcast();

  WearScreenId _screen = WearScreenId.scanIdle;
  List<BarcodeProductInfo> _products = const <BarcodeProductInfo>[];
  int _focusedIndex = 0;
  bool _loading = false;
  String? _lastBarcode;
  Timer? _statusTimer;
  int _generation = 0;

  @override
  Stream<WearBackgroundScreenUpdate> get updates => _updates.stream;

  @override
  bool handles(WearScreenId screen) {
    return screen == WearScreenId.scanIdle ||
        screen == WearScreenId.productSelect;
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
    if (screen == WearScreenId.scanIdle) {
      _lastBarcode = null;
      _products = const <BarcodeProductInfo>[];
    } else if (extra is WearProductSelectArgs) {
      _products = extra.products;
    }
    _publish(_payload());
  }

  @override
  Future<bool> handleBarcode(WearScreenId screen, String barcode) async {
    if (screen != WearScreenId.scanIdle || _loading) return false;
    final String value = barcode.trim();
    if (value.isEmpty || value == _lastBarcode) return true;
    _lastBarcode = value;
    if (WearSession.printerSelectionOrNull == null) {
      await _showStatus(isError: true, message: 'Не выбраны принтеры');
      return true;
    }
    if (WearSession.userOrNull == null) {
      await _showStatus(isError: true, message: 'Пользователь не авторизован');
      return true;
    }
    _loading = true;
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

  Future<void> _print(BarcodeProductInfo product) async {
    _loading = true;
    final int generation = _generation;
    _publish(WearGlassesPayload.printing(productName: product.name));
    try {
      final String printer = WearMockConfig.isEnabled
          ? WearSession.printerSelectionOrNull!.whitePrinter.name
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
    await _navigate(WearScreenId.status, extra: args);
    _statusTimer?.cancel();
    final int generation = _generation;
    _statusTimer = Timer(const Duration(seconds: 5), () {
      if (generation != _generation) return;
      _navigate(
        isError ? WearScreenId.scanIdle : WearScreenId.continueScan,
        replaceCurrent: true,
      );
    });
  }

  @override
  Future<void> reset() async {
    _generation += 1;
    _statusTimer?.cancel();
    _statusTimer = null;
    _screen = WearScreenId.scanIdle;
    _products = const <BarcodeProductInfo>[];
    _focusedIndex = 0;
    _loading = false;
    _lastBarcode = null;
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
    if (_updates.isClosed) return;
    _updates.add(WearBackgroundScreenUpdate(screen: _screen, payload: payload));
  }

  List<BarcodeProductInfo> _mockProducts(String barcode) {
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
  }
}
