import 'dart:async';
import 'dart:math' as math;

import 'package:smart_glasses/modules/wear/application/wear_background_runtime.dart';
import 'package:smart_glasses/modules/wear/application/wear_product_select_args.dart';
import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/application/wear_status_state.dart';
import 'package:smart_glasses/modules/wear/domain/price_tag_print/model/barcode_product_info.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/voice_list_matcher.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/voice_utterance_coordinator.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/wear_voice_command.dart';
import 'package:smart_glasses/modules/wear/models/wear_printer_selection.dart';
import 'package:smart_glasses/modules/wear/presentation/glasses/wear_glasses_payload.dart';
import 'package:smart_glasses/modules/wear/presentation/glasses/wear_glasses_voice_hints.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/status/wear_status_args.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_authority.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_scan_effects.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_store.dart';
import 'package:smart_glasses/modules/wear/theme/wear_images.dart';

typedef WearScanLookup = Future<List<BarcodeProductInfo>> Function(
  String barcode,
);
typedef WearScanPrinter = Future<String> Function(
  BarcodeProductInfo product,
  WearPrinterSelection selection,
);
typedef WearScanNavigation = Future<void> Function(
  WearScreenId screen, {
  Object? extra,
  bool replaceCurrent,
});
typedef WearScanStatusPresenter = Future<void> Function(
  WearStatusScreenArgs args, {
  required WearStatusCompletion completion,
});

enum WearScanRuntimePhase { waiting, loading, selection, printing, status }

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

  bool get isLoading =>
      phase == WearScanRuntimePhase.loading ||
      phase == WearScanRuntimePhase.printing;
}

class WearScanRuntime implements WearBackgroundRuntime {
  WearScanRuntime({
    required WearScanLookup lookupBarcode,
    required WearScanPrinter printProduct,
    required WearScanNavigation navigate,
    required WearScanStatusPresenter showStatus,
    WearScanEffectDelay delay = _defaultDelay,
    WearRuntimeAuthority? authority,
  }) : _authority = authority ?? WearRuntimeAuthority() {
    _effectExecutor = WearScanEffectExecutor(
      lookup: lookupBarcode,
      print: printProduct,
      navigate: navigate,
      presentStatus: showStatus,
      delay: delay,
    );
    _authority.registerEffectExecutor(_effectExecutor);
    _lastTask = _authority.scanTask;
    _subscription = _authority.states.listen(_onState);
  }

  static const int _visibleItemCount = 4;

  static Future<void> _defaultDelay(Duration duration) {
    return Future<void>.delayed(duration);
  }

  final WearRuntimeAuthority _authority;
  late final WearScanEffectExecutor _effectExecutor;
  final StreamController<WearBackgroundScreenUpdate> _updates =
      StreamController<WearBackgroundScreenUpdate>.broadcast();
  final StreamController<WearScanRuntimeState> _states =
      StreamController<WearScanRuntimeState>.broadcast();
  late final StreamSubscription<WearRuntimeState> _subscription;
  late WearScanTaskSlice _lastTask;
  bool _disposed = false;

  @override
  Stream<WearBackgroundScreenUpdate> get updates => _updates.stream;

  Stream<WearScanRuntimeState> get stateStream => _states.stream;

  WearScanRuntimeState get state => _mapState(_authority.scanTask);

  Future<bool> setFocusedIndex(int index) async {
    final WearDispatchResult result = await _authority.focusScanProduct(index);
    return result.accepted;
  }

  Future<bool> selectProduct(BarcodeProductInfo product) async {
    final WearDispatchResult result =
        await _authority.selectScanProduct(product.id);
    return result.accepted;
  }

  @override
  bool handles(WearScreenId screen) {
    return screen == WearScreenId.scanIdle ||
        screen == WearScreenId.productSelect;
  }

  @override
  bool acceptsBarcode(WearScreenId screen) {
    return screen == WearScreenId.scanIdle &&
        _authority.payload.navigation.logicalScreen == screen &&
        _authority.scanTask.phase == WearScanTaskPhase.waiting;
  }

  @override
  bool supportsCommand(WearScreenId screen, WearVoiceCommand command) {
    final WearScanTaskSlice task = _authority.scanTask;
    return screen == WearScreenId.productSelect &&
        _authority.payload.navigation.logicalScreen == screen &&
        task.phase == WearScanTaskPhase.selecting &&
        task.products.isNotEmpty &&
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
    await _authority.enterScanScreen(screen, extra: extra);
  }

  @override
  Future<bool> handleBarcode(WearScreenId screen, String barcode) async {
    if (!acceptsBarcode(screen)) return false;
    final WearDispatchResult result =
        await _authority.submitScanBarcode(barcode);
    return result.accepted;
  }

  @override
  Future<bool> handleCommand(
    WearScreenId screen,
    WearVoiceCommand command,
  ) async {
    if (!supportsCommand(screen, command)) return false;
    final WearDispatchResult result;
    switch (command) {
      case WearVoiceCommand.up:
        result = await _authority.moveScanFocus(-1);
        break;
      case WearVoiceCommand.down:
        result = await _authority.moveScanFocus(1);
        break;
      case WearVoiceCommand.select:
        final WearScanTaskSlice task = _authority.scanTask;
        final int index = task.focusedIndex.clamp(0, task.products.length - 1);
        result = await _authority.selectScanProduct(task.products[index].id);
        break;
      case WearVoiceCommand.nextPage:
        result = await _authority.moveScanPage(1);
        break;
      case WearVoiceCommand.previousPage:
        result = await _authority.moveScanPage(-1);
        break;
      default:
        return false;
    }
    return result.accepted;
  }

  @override
  Future<bool> handlePhrase(WearScreenId screen, String phrase) async {
    if (screen != WearScreenId.productSelect ||
        _authority.scanTask.phase != WearScanTaskPhase.selecting) {
      return false;
    }
    final VoiceListMatch<BarcodeProductInfo> match = VoiceListMatcher.match(
      phrase,
      _authority.scanTask.products,
      (BarcodeProductInfo item) => item.name,
    );
    if (match.type != VoiceListMatchType.unique || match.item == null) {
      return false;
    }
    final WearDispatchResult result =
        await _authority.selectScanProduct(match.item!.id);
    return result.accepted;
  }

  @override
  Future<bool> handleDynamicItem(WearScreenId screen, String itemId) async {
    if (screen != WearScreenId.productSelect ||
        _authority.scanTask.phase != WearScanTaskPhase.selecting) {
      return false;
    }
    final int? productId = int.tryParse(itemId);
    if (productId == null) return false;
    final WearDispatchResult result =
        await _authority.selectScanProduct(productId);
    return result.accepted;
  }

  @override
  VoiceDynamicItemsSnapshot dynamicVoiceItemsFor(WearScreenId screen) {
    if (screen != WearScreenId.productSelect) {
      return VoiceDynamicItemsSnapshot.empty;
    }
    final List<VoiceDynamicItem> items = _authority.scanTask.products
        .map(
          (BarcodeProductInfo item) => VoiceDynamicItem(
            id: item.id.toString(),
            label: item.name,
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

  @override
  Future<void> reset() async {
    await _authority.resetScanTask();
  }

  void _onState(WearRuntimeState _) {
    if (_disposed) return;
    final WearScanTaskSlice next = _authority.scanTask;
    if (identical(next, _lastTask)) return;
    _lastTask = next;
    final WearScanRuntimeState mapped = _mapState(next);
    if (!_states.isClosed) _states.add(mapped);
    if (handles(next.screen) && !_updates.isClosed) {
      _updates.add(
        WearBackgroundScreenUpdate(
          screen: next.screen,
          payload: _payload(next),
        ),
      );
    }
  }

  WearScanRuntimeState _mapState(WearScanTaskSlice task) {
    return WearScanRuntimeState(
      phase: switch (task.phase) {
        WearScanTaskPhase.waiting => WearScanRuntimePhase.waiting,
        WearScanTaskPhase.lookingUp => WearScanRuntimePhase.loading,
        WearScanTaskPhase.selecting => WearScanRuntimePhase.selection,
        WearScanTaskPhase.printing => WearScanRuntimePhase.printing,
        WearScanTaskPhase.status => WearScanRuntimePhase.status,
      },
      screen: task.screen,
      barcode: task.barcode,
      products: task.products,
      focusedIndex: task.focusedIndex,
      productName: task.productName,
      loadingText: task.phase == WearScanTaskPhase.printing
          ? 'Печатаю ценник...'
          : 'ШК отсканирован, распознаю...',
      loadingIcon: task.phase == WearScanTaskPhase.printing
          ? WearImages.printer
          : WearImages.barcode,
      status: task.status,
      lastAcceptedBarcode: task.lastAcceptedBarcode,
    );
  }

  WearGlassesPayload _payload(WearScanTaskSlice task) {
    switch (task.phase) {
      case WearScanTaskPhase.waiting:
        return WearGlassesPayload.scanWaiting();
      case WearScanTaskPhase.lookingUp:
        return WearGlassesPayload.loading(
          screenType: WearGlassesScreenType.scan,
          title: 'Сканирование товара',
          statusText: 'ШК отсканирован, распознаю...',
          statusIcon: WearImages.barcode,
        );
      case WearScanTaskPhase.printing:
        return WearGlassesPayload.loading(
          screenType: WearGlassesScreenType.scan,
          title: 'Печать ценника',
          subtitle: task.productName,
          statusText: 'Печатаю ценник...',
          statusIcon: WearImages.printer,
        );
      case WearScanTaskPhase.selecting:
        if (task.products.isEmpty) {
          return WearGlassesPayload.status(
            isError: true,
            title: 'Выбор товара',
            statusText: 'Список товаров пуст',
          );
        }
        final int selected =
            task.focusedIndex.clamp(0, task.products.length - 1);
        final int pageStart = selected ~/ _visibleItemCount * _visibleItemCount;
        final List<BarcodeProductInfo> visible = task.products
            .skip(pageStart)
            .take(_visibleItemCount)
            .toList(growable: false);
        final int pageCount =
            math.max(1, (task.products.length - 1) ~/ _visibleItemCount + 1);
        final int page = selected ~/ _visibleItemCount + 1;
        return WearGlassesPayload(
          screenType: WearGlassesScreenType.productSelect,
          phase: WearGlassesPhase.idle,
          title: 'Выбор товара',
          items: visible
              .map((BarcodeProductInfo item) => item.name)
              .toList(growable: false),
          voiceHints: WearGlassesVoiceHints.forVisibleItems(
            screen: WearScreenId.productSelect,
            snapshot: dynamicVoiceItemsFor(WearScreenId.productSelect),
            visibleItemIds: visible
                .map((BarcodeProductInfo item) => item.id.toString())
                .toList(growable: false),
          ),
          selectedIndex: selected - pageStart,
          pageText: pageCount > 1 ? 'Страница: $page из $pageCount' : null,
        );
      case WearScanTaskPhase.status:
        final WearStatusScreenArgs? status = task.status;
        return WearGlassesPayload.status(
          isError: status?.kind == WearStatusKind.error,
          title: status?.title ?? 'Статус',
          subtitle: status?.message,
          statusText: status?.glassesStatusText,
          statusIcon: status?.glassesStatusIcon,
        );
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _authority.resetScanTask();
    _effectExecutor.deactivate();
    await _subscription.cancel();
    await _states.close();
    await _updates.close();
  }
}
