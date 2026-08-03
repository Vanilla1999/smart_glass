import 'dart:async';
import 'dart:math' as math;

import 'package:smart_glasses/modules/wear/application/wear_background_runtime.dart';
import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/config/wear_mock_config.dart';
import 'package:smart_glasses/modules/wear/config/wear_session.dart';
import 'package:smart_glasses/modules/wear/domain/price_tag_print/model/available_printer.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/voice_list_matcher.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/voice_utterance_coordinator.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/wear_voice_command.dart';
import 'package:smart_glasses/modules/wear/models/wear_printer.dart';
import 'package:smart_glasses/modules/wear/models/wear_printer_selection.dart';
import 'package:smart_glasses/modules/wear/presentation/glasses/wear_glasses_payload.dart';
import 'package:smart_glasses/modules/wear/presentation/glasses/wear_glasses_voice_hints.dart';

typedef WearPrinterLoader = Future<List<AvailablePrinter>> Function();
typedef WearPrinterNavigation = Future<void> Function(
  WearScreenId screen, {
  Object? extra,
  bool replaceCurrent,
});

enum WearPrinterRuntimeStep { white, yellow }

class WearPrinterRuntimeState {
  const WearPrinterRuntimeState({
    required this.printers,
    required this.whitePrinter,
    required this.step,
    required this.focusedIndex,
  });

  final List<WearPrinter> printers;
  final WearPrinter? whitePrinter;
  final WearPrinterRuntimeStep step;
  final int focusedIndex;
}

class WearPrinterRuntime implements WearBackgroundRuntime {
  WearPrinterRuntime({
    required WearPrinterLoader loadPrinters,
    required WearPrinterNavigation navigate,
  })  : _loadPrinters = loadPrinters,
        _navigate = navigate;

  static const int _visibleItemCount = 4;

  final WearPrinterLoader _loadPrinters;
  final WearPrinterNavigation _navigate;
  final StreamController<WearBackgroundScreenUpdate> _updates =
      StreamController<WearBackgroundScreenUpdate>.broadcast();

  List<WearPrinter> _printers = const <WearPrinter>[];
  WearPrinter? _whitePrinter;
  WearPrinterRuntimeStep _step = WearPrinterRuntimeStep.white;
  int _focusedIndex = 0;
  bool _loading = false;
  String? _error;
  Future<void>? _loadOperation;
  int _generation = 0;

  @override
  Stream<WearBackgroundScreenUpdate> get updates => _updates.stream;

  @override
  bool handles(WearScreenId screen) => screen == WearScreenId.printerSelect;

  @override
  bool supportsCommand(WearScreenId screen, WearVoiceCommand command) {
    return handles(screen) &&
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
    _whitePrinter = null;
    _step = WearPrinterRuntimeStep.white;
    _focusedIndex = 0;
    if (_printers.isEmpty) {
      await load();
    } else {
      _publish();
    }
  }

  Future<void> load() {
    final Future<void>? existing = _loadOperation;
    if (existing != null) return existing;
    late final Future<void> operation;
    operation = _load().whenComplete(() {
      if (identical(_loadOperation, operation)) _loadOperation = null;
    });
    _loadOperation = operation;
    return operation;
  }

  Future<void> _load() async {
    final int generation = _generation;
    _loading = true;
    _error = null;
    _publish();
    try {
      final List<AvailablePrinter> available = WearMockConfig.isEnabled
          ? <AvailablePrinter>[
              AvailablePrinter(number: 'mock-white-1', name: 'MOCK Белый 1'),
              AvailablePrinter(number: 'mock-yellow-1', name: 'MOCK Желтый 1'),
              AvailablePrinter(
                  number: 'mock-mobile-2', name: 'MOCK Мобильный 2'),
            ]
          : await _loadPrinters();
      final List<WearPrinter> printers = available
          .map(
            (AvailablePrinter printer) => WearPrinter(
              id: printer.number,
              name: printer.name,
            ),
          )
          .toList(growable: false);
      if (generation != _generation) return;
      _printers = printers;
    } catch (error) {
      if (generation != _generation) return;
      _error = _messageFor(error);
    } finally {
      if (generation == _generation) {
        _loading = false;
        _focusedIndex = 0;
        _publish();
      }
    }
  }

  @override
  Future<bool> handleCommand(
    WearScreenId screen,
    WearVoiceCommand command,
  ) async {
    if (!handles(screen)) return false;
    switch (command) {
      case WearVoiceCommand.up:
        _move(-1);
        return true;
      case WearVoiceCommand.down:
        _move(1);
        return true;
      case WearVoiceCommand.select:
        await _selectFocused();
        return true;
      case WearVoiceCommand.nextPage:
        _movePage(1);
        return true;
      case WearVoiceCommand.previousPage:
        _movePage(-1);
        return true;
      default:
        return false;
    }
  }

  @override
  Future<bool> handlePhrase(WearScreenId screen, String phrase) async {
    if (!handles(screen) || _loading) return false;
    final List<WearPrinter> printers = _visiblePrinters;
    final VoiceListMatch<WearPrinter> match = VoiceListMatcher.match(
      phrase,
      printers,
      (WearPrinter printer) => printer.name,
    );
    if (match.type != VoiceListMatchType.unique) return false;
    await _select(match.item!);
    return true;
  }

  @override
  Future<bool> handleDynamicItem(WearScreenId screen, String itemId) async {
    if (!handles(screen) || _loading) return false;
    for (final WearPrinter printer in _visiblePrinters) {
      if (printer.id != itemId) continue;
      await _select(printer);
      return true;
    }
    return false;
  }

  @override
  Future<bool> handleBarcode(WearScreenId screen, String barcode) async {
    return false;
  }

  @override
  VoiceDynamicItemsSnapshot dynamicVoiceItemsFor(WearScreenId screen) {
    if (!handles(screen)) return VoiceDynamicItemsSnapshot.empty;
    final List<VoiceDynamicItem> items = _visiblePrinters
        .map(
          (WearPrinter printer) => VoiceDynamicItem(
            id: printer.id,
            label: printer.name,
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
  void restorePresentationState(WearScreenId screen, Object state) {
    if (!handles(screen) || state is! WearPrinterRuntimeState) return;
    _printers = List<WearPrinter>.unmodifiable(state.printers);
    _whitePrinter = state.whitePrinter;
    _step = state.step;
    _focusedIndex = state.focusedIndex;
    _loading = false;
    _error = null;
    _publish();
  }

  @override
  Object? presentationStateFor(WearScreenId screen) {
    if (!handles(screen)) return null;
    return WearPrinterRuntimeState(
      printers: _printers,
      whitePrinter: _whitePrinter,
      step: _step,
      focusedIndex: _focusedIndex,
    );
  }

  void _move(int delta) {
    final List<WearPrinter> printers = _visiblePrinters;
    if (printers.isEmpty) return;
    _focusedIndex = (_focusedIndex + delta).clamp(0, printers.length - 1);
    _publish();
  }

  void _movePage(int delta) {
    final List<WearPrinter> printers = _visiblePrinters;
    if (printers.isEmpty) return;
    _focusedIndex = (_focusedIndex + delta * _visibleItemCount)
        .clamp(0, printers.length - 1);
    _publish();
  }

  Future<void> _selectFocused() async {
    final List<WearPrinter> printers = _visiblePrinters;
    if (_loading || printers.isEmpty) return;
    final int index = _focusedIndex.clamp(0, printers.length - 1);
    await _select(printers[index]);
  }

  Future<void> _select(WearPrinter printer) async {
    if (_step == WearPrinterRuntimeStep.white) {
      _whitePrinter = printer;
      _step = WearPrinterRuntimeStep.yellow;
      _focusedIndex = 0;
      _publish();
      return;
    }
    final WearPrinter? white = _whitePrinter;
    if (white == null || white.id == printer.id) return;
    final WearPrinterSelection selection = WearPrinterSelection(
      whitePrinter: white,
      yellowPrinter: printer,
    );
    WearSession.setPrinterSelection(selection);
    await _navigate(WearScreenId.scanIdle, extra: selection);
  }

  List<WearPrinter> get _visiblePrinters {
    final WearPrinter? white = _whitePrinter;
    if (_step == WearPrinterRuntimeStep.yellow && white != null) {
      return _printers
          .where((WearPrinter printer) => printer.id != white.id)
          .toList(growable: false);
    }
    return _printers;
  }

  void _publish() {
    if (_updates.isClosed) return;
    _updates.add(
      WearBackgroundScreenUpdate(
        screen: WearScreenId.printerSelect,
        payload: _payload(),
      ),
    );
  }

  WearGlassesPayload _payload() {
    if (_loading) {
      return const WearGlassesPayload(
        screenType: WearGlassesScreenType.printer,
        phase: WearGlassesPhase.loading,
        title: 'Выбор принтера',
        statusText: 'Инициализация...',
        isLoading: true,
      );
    }
    if (_error != null && _printers.isEmpty) {
      return WearGlassesPayload.status(
        isError: true,
        title: 'Ошибка загрузки принтеров',
        subtitle: _error,
      );
    }
    final List<WearPrinter> printers = _visiblePrinters;
    if (printers.isEmpty) {
      return WearGlassesPayload.status(
        isError: true,
        title: 'Принтеры',
        statusText: 'Список принтеров пуст',
      );
    }
    final int selected = _focusedIndex.clamp(0, printers.length - 1);
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
      subtitle: _step == WearPrinterRuntimeStep.yellow
          ? 'Жёлтые ценники'
          : 'Белые ценники',
      items: visible
          .map((WearPrinter printer) => printer.name)
          .toList(growable: false),
      voiceHints: WearGlassesVoiceHints.forVisibleItems(
        screen: WearScreenId.printerSelect,
        snapshot: snapshot,
        visibleItemIds: visible
            .map((WearPrinter printer) => printer.id)
            .toList(growable: false),
      ),
      selectedIndex: selected - pageStart,
      pageText: pageCount > 1 ? 'Страница: $page из $pageCount' : null,
    );
  }

  String _messageFor(Object error) {
    final String message = error.toString();
    return message.startsWith('Exception: ')
        ? message.substring('Exception: '.length)
        : message;
  }

  @override
  Future<void> reset() async {
    _generation += 1;
    _loadOperation = null;
    _printers = const <WearPrinter>[];
    _whitePrinter = null;
    _step = WearPrinterRuntimeStep.white;
    _focusedIndex = 0;
    _loading = false;
    _error = null;
  }

  @override
  Future<void> dispose() async {
    await reset();
    await _updates.close();
  }
}
