import 'dart:async';
import 'dart:math' as math;

import 'package:smart_glasses/modules/wear/application/wear_background_runtime.dart';
import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/domain/price_tag_print/model/available_printer.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/voice_list_matcher.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/voice_utterance_coordinator.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/wear_voice_command.dart';
import 'package:smart_glasses/modules/wear/models/wear_printer.dart';
import 'package:smart_glasses/modules/wear/models/wear_printer_selection.dart';
import 'package:smart_glasses/modules/wear/presentation/glasses/wear_glasses_payload.dart';
import 'package:smart_glasses/modules/wear/presentation/glasses/wear_glasses_voice_hints.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_authority.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_printer_effects.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_store.dart';

typedef WearPrinterLoader = Future<List<AvailablePrinter>> Function();
typedef WearPrinterNavigation = Future<void> Function(
  WearScreenId screen, {
  Object? extra,
  bool replaceCurrent,
});
typedef WearPrinterRuntimeStep = WearPrinterTaskStep;
typedef WearPrinterRuntimePhase = WearPrinterTaskPhase;

class WearPrinterRuntimeState {
  const WearPrinterRuntimeState({
    required this.phase,
    required this.printers,
    required this.whitePrinter,
    required this.selection,
    required this.step,
    required this.focusedIndex,
    required this.error,
  });

  final WearPrinterRuntimePhase phase;
  final List<WearPrinter> printers;
  final WearPrinter? whitePrinter;
  final WearPrinterSelection? selection;
  final WearPrinterRuntimeStep step;
  final int focusedIndex;
  final String? error;

  bool get isLoading => phase == WearPrinterRuntimePhase.loading;

  List<WearPrinter> get visiblePrinters {
    final WearPrinter? white = whitePrinter;
    if (step == WearPrinterRuntimeStep.yellow && white != null) {
      return List<WearPrinter>.unmodifiable(
        printers.where((WearPrinter item) => item.id != white.id),
      );
    }
    return printers;
  }
}

/// Compatibility facade for existing controller/widgets.
///
/// It has no mutable printer fields. Aggregate `WearPrinterTaskSlice` is the
/// only writable owner; this adapter translates old calls and projections.
class WearPrinterRuntime implements WearBackgroundRuntime {
  WearPrinterRuntime({
    required WearPrinterLoader loadPrinters,
    required WearPrinterNavigation navigate,
    WearRuntimeAuthority? authority,
  }) : _authority = authority ?? WearRuntimeAuthority() {
    _authority.registerEffectExecutor(
      WearPrinterEffectExecutor(
        loadPrinters: loadPrinters,
        navigate: navigate,
      ),
    );
    _lastTask = _authority.printerTask;
    _stateSubscription = _authority.states.listen(_onRuntimeState);
  }

  static const int _visibleItemCount = 4;

  final WearRuntimeAuthority _authority;
  final StreamController<WearBackgroundScreenUpdate> _updates =
      StreamController<WearBackgroundScreenUpdate>.broadcast();
  final StreamController<WearPrinterRuntimeState> _states =
      StreamController<WearPrinterRuntimeState>.broadcast();

  late WearPrinterTaskSlice _lastTask;
  late final StreamSubscription<WearRuntimeState> _stateSubscription;
  bool _disposed = false;

  @override
  Stream<WearBackgroundScreenUpdate> get updates => _updates.stream;

  Stream<WearPrinterRuntimeState> get stateStream => _states.stream;

  WearPrinterRuntimeState get state => _mapState(_authority.printerTask);

  @override
  bool handles(WearScreenId screen) => screen == WearScreenId.printerSelect;

  @override
  bool acceptsBarcode(WearScreenId screen) => false;

  @override
  bool supportsCommand(WearScreenId screen, WearVoiceCommand command) {
    final WearPrinterTaskSlice task = _authority.printerTask;
    if (!handles(screen) ||
        _authority.payload.navigation.logicalScreen != screen ||
        task.isLoading ||
        task.visiblePrinters.isEmpty) {
      return false;
    }
    return <WearVoiceCommand>{
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
    await _authority.enterPrinterScreen(returnSelection: extra == true);
  }

  Future<void> load() async {
    await _authority.reloadPrinters();
  }

  void focusPrinter(int index) {
    unawaited(_authority.focusPrinter(index));
  }

  Future<void> selectPrinter(WearPrinter printer) async {
    await _authority.selectPrinter(printer);
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
        result = await _authority.movePrinterFocus(-1);
        break;
      case WearVoiceCommand.down:
        result = await _authority.movePrinterFocus(1);
        break;
      case WearVoiceCommand.select:
        final List<WearPrinter> visible = _authority.printerTask.visiblePrinters;
        final int index = _authority.printerTask.focusedIndex
            .clamp(0, visible.length - 1);
        result = await _authority.selectPrinter(visible[index]);
        break;
      case WearVoiceCommand.nextPage:
        result = await _authority.movePrinterPage(1);
        break;
      case WearVoiceCommand.previousPage:
        result = await _authority.movePrinterPage(-1);
        break;
      default:
        return false;
    }
    return result.accepted;
  }

  @override
  Future<bool> handlePhrase(WearScreenId screen, String phrase) async {
    if (!handles(screen) || _authority.printerTask.isLoading) return false;
    final List<WearPrinter> printers = _authority.printerTask.visiblePrinters;
    final VoiceListMatch<WearPrinter> match = VoiceListMatcher.match(
      phrase,
      printers,
      (WearPrinter item) => item.name,
    );
    if (match.type != VoiceListMatchType.unique || match.item == null) {
      return false;
    }
    final WearDispatchResult result =
        await _authority.selectPrinter(match.item!);
    return result.accepted;
  }

  @override
  Future<bool> handleDynamicItem(WearScreenId screen, String itemId) async {
    if (!handles(screen) || _authority.printerTask.isLoading) return false;
    final WearDispatchResult result =
        await _authority.selectPrinterById(itemId);
    return result.accepted;
  }

  @override
  Future<bool> handleBarcode(WearScreenId screen, String barcode) async {
    return false;
  }

  @override
  VoiceDynamicItemsSnapshot dynamicVoiceItemsFor(WearScreenId screen) {
    if (!handles(screen)) return VoiceDynamicItemsSnapshot.empty;
    final List<VoiceDynamicItem> items = _authority
        .printerTask.visiblePrinters
        .map(
          (WearPrinter item) => VoiceDynamicItem(
            id: item.id,
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
    await _authority.resetPrinterTask();
  }

  void _onRuntimeState(WearRuntimeState _) {
    if (_disposed) return;
    final WearPrinterTaskSlice next = _authority.printerTask;
    if (identical(next, _lastTask)) return;
    _lastTask = next;
    final WearPrinterRuntimeState mapped = _mapState(next);
    if (!_states.isClosed) _states.add(mapped);
    if (!_updates.isClosed) {
      _updates.add(
        WearBackgroundScreenUpdate(
          screen: WearScreenId.printerSelect,
          payload: _payload(next),
        ),
      );
    }
  }

  WearPrinterRuntimeState _mapState(WearPrinterTaskSlice task) {
    return WearPrinterRuntimeState(
      phase: task.phase,
      printers: task.printers,
      whitePrinter: task.whitePrinter,
      selection: task.selection,
      step: task.step,
      focusedIndex: task.focusedIndex,
      error: task.error,
    );
  }

  WearGlassesPayload _payload(WearPrinterTaskSlice task) {
    if (task.isLoading) {
      return const WearGlassesPayload(
        screenType: WearGlassesScreenType.printer,
        phase: WearGlassesPhase.loading,
        title: 'Выбор принтера',
        statusText: 'Инициализация...',
        isLoading: true,
      );
    }
    if (task.error != null && task.printers.isEmpty) {
      return WearGlassesPayload.status(
        isError: true,
        title: 'Ошибка загрузки принтеров',
        subtitle: task.error,
      );
    }
    final List<WearPrinter> printers = task.visiblePrinters;
    if (printers.isEmpty) {
      return WearGlassesPayload.status(
        isError: true,
        title: 'Принтеры',
        statusText: 'Список принтеров пуст',
      );
    }
    final int selected = task.focusedIndex.clamp(0, printers.length - 1);
    final int pageStart = selected ~/ _visibleItemCount * _visibleItemCount;
    final List<WearPrinter> visible = printers
        .skip(pageStart)
        .take(_visibleItemCount)
        .toList(growable: false);
    final VoiceDynamicItemsSnapshot snapshot =
        dynamicVoiceItemsFor(WearScreenId.printerSelect);
    final int pageCount =
        math.max(1, (printers.length - 1) ~/ _visibleItemCount + 1);
    final int page = selected ~/ _visibleItemCount + 1;
    return WearGlassesPayload(
      screenType: WearGlassesScreenType.printer,
      phase: WearGlassesPhase.idle,
      title: 'Выбор принтера',
      subtitle: task.step == WearPrinterTaskStep.yellow
          ? 'Жёлтые ценники'
          : 'Белые ценники',
      items: visible.map((WearPrinter item) => item.name).toList(growable: false),
      voiceHints: WearGlassesVoiceHints.forVisibleItems(
        screen: WearScreenId.printerSelect,
        snapshot: snapshot,
        visibleItemIds:
            visible.map((WearPrinter item) => item.id).toList(growable: false),
      ),
      selectedIndex: selected - pageStart,
      pageText: pageCount > 1 ? 'Страница: $page из $pageCount' : null,
    );
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _stateSubscription.cancel();
    await _states.close();
    await _updates.close();
  }
}
