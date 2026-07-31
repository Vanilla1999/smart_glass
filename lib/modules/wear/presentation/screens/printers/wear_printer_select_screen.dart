import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_glasses/modules/wear/application/wear_flow_controller.dart';
import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/config/wear_dependencies.dart';
import 'package:smart_glasses/modules/wear/config/wear_session.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/voice_list_matcher.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/voice_utterance_coordinator.dart';
import 'package:smart_glasses/modules/wear/infrastructure/screen_lifecycle_logging.dart';
import 'package:smart_glasses/modules/wear/models/wear_printer.dart';
import 'package:smart_glasses/modules/wear/models/wear_printer_selection.dart';
import 'package:smart_glasses/modules/wear/presentation/glasses/wear_glasses_payload.dart';
import 'package:smart_glasses/modules/wear/presentation/glasses/wear_glasses_voice_hints.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/printers/cubit/wear_printer_select_cubit.dart';

import 'package:smart_glasses/modules/wear/presentation/screens/scan/wear_scan_idle_screen.dart';
import 'package:smart_glasses/modules/wear/presentation/widgets/wear_loading.dart';
import 'package:smart_glasses/modules/wear/presentation/widgets/wear_pill.dart';
import 'package:smart_glasses/modules/wear/presentation/widgets/wear_scaling_list_view.dart';
import 'package:smart_glasses/modules/wear/presentation/widgets/wear_screen_scaffold.dart';
import 'package:smart_glasses/modules/wear/services/wear_status_icon_reporter.dart';
import 'package:smart_glasses/modules/wear/theme/wear_images.dart';
import 'package:smart_glasses/modules/wear/theme/wear_typography.dart';

class WearPrinterSelectScreen extends ConsumerStatefulWidget {
  const WearPrinterSelectScreen({
    super.key,
    this.flowController,
    this.returnSelection = false,
  });

  static const String route = '/wear_printer_select';

  final WearFlowController? flowController;
  final bool returnSelection;

  @override
  ConsumerState<WearPrinterSelectScreen> createState() =>
      _WearPrinterSelectScreenState();
}

class _WearPrinterSelectScreenState
    extends ConsumerState<WearPrinterSelectScreen>
    with ScreenLifecycleLogging<WearPrinterSelectScreen> {
  final ScrollController _scroll = ScrollController();
  int _focusedIndex = 0;
  bool _isScanScreenOpen = false;

  WearFlowController get _flowController =>
      widget.flowController ?? WearDependencies.I.wearFlowController;

  @override
  void initState() {
    super.initState();
    _flowController.enterScreen(WearScreenId.printerSelect);
    _flowController.registerScreenActions(
      WearScreenId.printerSelect,
      WearScreenActionHandler(
        onUp: _onVoiceUp,
        onDown: _onVoiceDown,
        onSelect: _onVoiceSelect,
        onNextPage: _onVoiceNextPage,
        onPreviousPage: _onVoicePreviousPage,
        onPhrase: _onVoicePhrase,
        onDynamicItem: _onVoiceDynamicItem,
        dynamicVoiceItems: _dynamicVoiceItems,
        onPartialPhrase: _onVoicePartialPhrase,
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.returnSelection) {
        ref.read(wearPrinterSelectNotifierProvider.notifier).resetSelection();
      }
      _sendGlassesState(ref.read(wearPrinterSelectNotifierProvider));
    });
  }

  @override
  void dispose() {
    _flowController.unregisterScreenActions(
      WearScreenId.printerSelect,
    );
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final WearPrinterSelectState state =
        ref.watch(wearPrinterSelectNotifierProvider);

    ref.listen<WearPrinterSelectState>(wearPrinterSelectNotifierProvider,
        (WearPrinterSelectState? previous, WearPrinterSelectState next) {
      if (previous?.step != next.step) {
        _focusedIndex = 0;
        _scrollToTop();
      }
      if (previous?.phase != next.phase ||
          previous?.step != next.step ||
          previous?.printers != next.printers ||
          previous?.error != next.error) {
        _sendGlassesState(next);
      }
      if (previous?.yellowPrinter != next.yellowPrinter &&
          next.yellowPrinter != null) {
        print(
          '[BACK-DEBUG] PrinterSelect.ref.listen: yellowPrinter changed, '
          'calling _openScanScreen. _isScanScreenOpen=$_isScanScreenOpen',
        );
        _openScanScreen(context, next);
      }
    });

    return WearScreenScaffold(
      showHomeButton: true,
      scrollController: _scroll,
      child: _buildContent(context, state),
    );
  }

  Widget _buildContent(BuildContext context, WearPrinterSelectState state) {
    if (state.isLoading) {
      return const Center(child: WearLoading());
    }

    if (state.hasError && state.printers.isEmpty) {
      return _buildRefreshableMessage(
        state,
        'Ошибка загрузки принтеров\n${state.error ?? ''}',
      );
    }

    final List<WearPrinter> printers = _visiblePrinters(state);
    if (printers.isEmpty) {
      return _buildRefreshableMessage(state, 'Список принтеров пуст.');
    }

    return RefreshIndicator(
      onRefresh: () =>
          ref.read(wearPrinterSelectNotifierProvider.notifier).load(),
      child: WearScalingListView(
        controller: _scroll,
        itemCount: printers.length + 2,
        itemExtent: 56,
        padding: const EdgeInsets.fromLTRB(0, 40, 0, 4.5),
        edgeFractionTop: 0.0,
        minScale: 0.68,
        minOpacity: 0.26,
        extraSideInset: 40,
        physics: const AlwaysScrollableScrollPhysics(
          parent: ClampingScrollPhysics(),
        ),
        itemBuilder: (BuildContext context, int i) {
          if (i == 0) {
            return Align(
              alignment: Alignment.topCenter,
              child: Text(
                _headerText(state.step),
                style: WearTypography.lable,
                textAlign: TextAlign.center,
              ),
            );
          }

          if (i == printers.length + 1) {
            return const SizedBox.shrink();
          }

          final WearPrinter p = printers[i - 1];
          return WearPill(
            title: p.name,
            icon: WearImages.printer,
            onTap: () => ref
                .read(wearPrinterSelectNotifierProvider.notifier)
                .selectPrinter(p),
          );
        },
        onFocusChanged: (int listIndex) {
          final List<WearPrinter> current =
              _visiblePrinters(ref.read(wearPrinterSelectNotifierProvider));
          if (current.isEmpty) return;
          final int printerIndex = (listIndex - 1).clamp(0, current.length - 1);
          if (printerIndex == _focusedIndex) return;
          _focusedIndex = printerIndex;
          _sendGlassesState(ref.read(wearPrinterSelectNotifierProvider),
              fast: true);
        },
      ),
    );
  }

  String _headerText(WearPrinterSelectStep step) {
    if (step == WearPrinterSelectStep.yellow) {
      return 'Выберите принтер\nдля желтых ценников';
    }
    return 'Выберите принтер\nдля белых ценников';
  }

  void _onVoiceUp() {
    if (!_scroll.hasClients) return;
    final List<WearPrinter> printers =
        _visiblePrinters(ref.read(wearPrinterSelectNotifierProvider));
    if (printers.isEmpty) return;
    _focusedIndex = _focusedIndex.clamp(0, printers.length - 1);
    if (_focusedIndex <= 0) return;
    _focusedIndex = _focusedIndex - 1;
    final double target = (_focusedIndex * 56.0).clamp(
      0.0,
      _scroll.position.maxScrollExtent,
    );
    _scroll.animateTo(target,
        duration: const Duration(milliseconds: 150), curve: Curves.easeOut);
    _sendGlassesState(ref.read(wearPrinterSelectNotifierProvider), fast: true);
  }

  void _onVoiceDown() {
    print('[PrinterSelect] _onVoiceDown called, focusedIndex=$_focusedIndex');
    if (!_scroll.hasClients) return;
    final List<WearPrinter> printers =
        _visiblePrinters(ref.read(wearPrinterSelectNotifierProvider));
    if (printers.isEmpty) return;
    _focusedIndex = _focusedIndex.clamp(0, printers.length - 1);
    if (_focusedIndex >= printers.length - 1) return;
    _focusedIndex = _focusedIndex + 1;
    final double target = (_focusedIndex * 56.0).clamp(
      0.0,
      _scroll.position.maxScrollExtent,
    );
    _scroll.animateTo(target,
        duration: const Duration(milliseconds: 150), curve: Curves.easeOut);
    _sendGlassesState(ref.read(wearPrinterSelectNotifierProvider), fast: true);
  }

  void _onVoiceSelect() {
    final WearPrinterSelectState s =
        ref.read(wearPrinterSelectNotifierProvider);
    print(
      '[PrinterSelect] _onVoiceSelect focusedIndex=$_focusedIndex '
      'phase=${s.phase} step=${s.step} isLoading=${s.isLoading} '
      'printers=${s.printers.length}',
    );
    if (s.isLoading || s.printers.isEmpty) {
      print('[PrinterSelect] ignore voice select: printers are not ready');
      return;
    }
    final List<WearPrinter> printers = _visiblePrinters(s);
    if (_focusedIndex >= 0 && _focusedIndex < printers.length) {
      print(
        '[PrinterSelect] voice select printer index=$_focusedIndex '
        'id=${printers[_focusedIndex].id} name=${printers[_focusedIndex].name}',
      );
      ref
          .read(wearPrinterSelectNotifierProvider.notifier)
          .selectPrinter(printers[_focusedIndex]);
    }
    // If both printers are already selected, open scan directly even if
    // the same printer was re-selected (no state change → ref.listen won't fire).
    final WearPrinterSelectState updated =
        ref.read(wearPrinterSelectNotifierProvider);
    if (updated.whitePrinter != null && updated.yellowPrinter != null) {
      _openScanScreen(context, updated);
    }
  }

  void _onVoiceNextPage() {
    final List<WearPrinter> printers =
        _visiblePrinters(ref.read(wearPrinterSelectNotifierProvider));
    if (printers.isEmpty) return;
    final int currentPage = _focusedIndex ~/ _visibleGlassesItemCount;
    final int nextIndex = (currentPage + 1) * _visibleGlassesItemCount;
    if (nextIndex >= printers.length) {
      _showVoiceSearchMessage('Это последняя страница');
      return;
    }
    _focusedIndex = nextIndex.clamp(0, printers.length - 1);
    _scrollToFocused();
    _sendGlassesState(ref.read(wearPrinterSelectNotifierProvider), fast: true);
  }

  void _onVoicePreviousPage() {
    final List<WearPrinter> printers =
        _visiblePrinters(ref.read(wearPrinterSelectNotifierProvider));
    if (printers.isEmpty) return;
    final int currentPage = _focusedIndex ~/ _visibleGlassesItemCount;
    if (currentPage == 0) {
      _showVoiceSearchMessage('Это первая страница');
      return;
    }
    final int previousIndex = (currentPage - 1) * _visibleGlassesItemCount;
    _focusedIndex = previousIndex.clamp(0, printers.length - 1);
    _scrollToFocused();
    _sendGlassesState(ref.read(wearPrinterSelectNotifierProvider), fast: true);
  }

  VoiceDynamicItemsSnapshot _dynamicVoiceItems() {
    final WearPrinterSelectState state =
        ref.read(wearPrinterSelectNotifierProvider);
    final List<VoiceDynamicItem> items = _visiblePrinters(state)
        .map((WearPrinter item) =>
            VoiceDynamicItem(id: item.id, label: item.name))
        .toList(growable: false);
    return VoiceDynamicItemsSnapshot(
      revision: Object.hashAll(
        items.map((VoiceDynamicItem item) => item.revisionHash),
      ),
      items: items,
    );
  }

  void _onVoicePhrase(String phrase) {
    final WearPrinterSelectState state =
        ref.read(wearPrinterSelectNotifierProvider);
    if (state.isLoading) return;
    final List<WearPrinter> printers = _visiblePrinters(state);
    final VoiceListMatch<WearPrinter> match = VoiceListMatcher.match(
      phrase,
      printers,
      (WearPrinter printer) => printer.name,
    );
    switch (match.type) {
      case VoiceListMatchType.none:
        _showVoiceSearchMessage('Не найдено');
        break;
      case VoiceListMatchType.ambiguous:
        _showVoiceSearchMessage('Назовите точнее');
        break;
      case VoiceListMatchType.unique:
        final WearPrinter printer = match.item!;
        final int index = printers.indexWhere((WearPrinter item) {
          return item.id == printer.id;
        });
        if (index >= 0) {
          _focusedIndex = index;
          _scrollToFocused();
        }
        ref
            .read(wearPrinterSelectNotifierProvider.notifier)
            .selectPrinter(printer);
        final WearPrinterSelectState updated =
            ref.read(wearPrinterSelectNotifierProvider);
        if (updated.whitePrinter != null && updated.yellowPrinter != null) {
          _openScanScreen(context, updated);
        }
        break;
    }
  }

  void _onVoiceDynamicItem(String itemId) {
    final WearPrinterSelectState state =
        ref.read(wearPrinterSelectNotifierProvider);
    if (state.isLoading) return;
    final List<WearPrinter> printers = _visiblePrinters(state);
    for (final WearPrinter printer in printers) {
      if (printer.id != itemId) continue;
      final int index = printers.indexOf(printer);
      if (index >= 0) {
        _focusedIndex = index;
        _scrollToFocused();
      }
      ref
          .read(wearPrinterSelectNotifierProvider.notifier)
          .selectPrinter(printer);
      final WearPrinterSelectState updated =
          ref.read(wearPrinterSelectNotifierProvider);
      if (updated.whitePrinter != null && updated.yellowPrinter != null) {
        _openScanScreen(context, updated);
      }
      return;
    }
  }

  bool _onVoicePartialPhrase(String phrase) {
    final WearPrinterSelectState state =
        ref.read(wearPrinterSelectNotifierProvider);
    if (state.isLoading) return false;
    final List<WearPrinter> printers = _visiblePrinters(state);
    final VoiceListMatch<WearPrinter> match =
        VoiceListMatcher.canMatchPartial(phrase)
            ? VoiceListMatcher.match(
                phrase,
                printers,
                (WearPrinter printer) => printer.name,
              )
            : VoiceListMatcher.matchExactPhrase(
                phrase,
                printers,
                (WearPrinter printer) => printer.name,
              );
    if (match.type != VoiceListMatchType.unique) {
      return false;
    }

    final WearPrinter printer = match.item!;
    final int index = printers.indexWhere((WearPrinter item) {
      return item.id == printer.id;
    });
    if (index >= 0) {
      _focusedIndex = index;
      _scrollToFocused();
      _sendGlassesState(
        ref.read(wearPrinterSelectNotifierProvider),
        fast: true,
      );
    }
    return index >= 0;
  }

  List<WearPrinter> _visiblePrinters(WearPrinterSelectState state) {
    if (state.step == WearPrinterSelectStep.yellow &&
        state.whitePrinter != null) {
      return state.printers
          .where((WearPrinter p) => p.id != state.whitePrinter!.id)
          .toList();
    }
    return state.printers;
  }

  void _scrollToFocused() {
    if (!_scroll.hasClients) return;
    final double target = (_focusedIndex * 56.0).clamp(
      0.0,
      _scroll.position.maxScrollExtent,
    );
    _scroll.animateTo(
      target,
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
    );
  }

  void _showVoiceSearchMessage(String message) {
    WearStatusIconReporter.I.showTransientFastForScreen(
      WearScreenId.printerSelect,
      WearGlassesPayload.status(
        isError: true,
        title: 'Голосовой выбор',
        statusText: message,
      ),
    );
  }

  Widget _buildRefreshableMessage(
    WearPrinterSelectState state,
    String message,
  ) {
    return RefreshIndicator(
      onRefresh: () =>
          ref.read(wearPrinterSelectNotifierProvider.notifier).load(),
      child: WearScalingListView(
        controller: _scroll,
        itemCount: 2,
        itemExtent: 56,
        padding: const EdgeInsets.fromLTRB(0, 40, 0, 4.5),
        edgeFractionTop: 0.0,
        minScale: 0.68,
        minOpacity: 0.26,
        extraSideInset: 40,
        physics: const AlwaysScrollableScrollPhysics(
          parent: ClampingScrollPhysics(),
        ),
        itemBuilder: (BuildContext context, int i) {
          if (i == 0) {
            return Align(
              alignment: Alignment.topCenter,
              child: Text(
                _headerText(state.step),
                style: WearTypography.lable,
                textAlign: TextAlign.center,
              ),
            );
          }
          return Align(
            alignment: Alignment.center,
            child: Text(
              message,
              style: WearTypography.lable,
              textAlign: TextAlign.center,
            ),
          );
        },
      ),
    );
  }

  Future<void> _openScanScreen(
    BuildContext context,
    WearPrinterSelectState state,
  ) async {
    if (_isScanScreenOpen) {
      print(
        '[BACK-DEBUG] PrinterSelect._openScanScreen: '
        '_isScanScreenOpen already true, returning',
      );
      return;
    }
    final WearPrinter? white = state.whitePrinter;
    final WearPrinter? yellow = state.yellowPrinter;
    if (white == null || yellow == null) {
      print(
        '[BACK-DEBUG] PrinterSelect._openScanScreen: '
        'white=$white yellow=$yellow, returning',
      );
      return;
    }
    if (white.id == yellow.id) {
      print(
        '[BACK-DEBUG] PrinterSelect._openScanScreen: '
        'white.id==yellow.id, returning',
      );
      return;
    }
    final WearPrinterSelection selection = WearPrinterSelection(
      whitePrinter: white,
      yellowPrinter: yellow,
    );
    WearSession.setPrinterSelection(selection);
    _isScanScreenOpen = true;
    print('[BACK-DEBUG] PrinterSelect._openScanScreen: pushing scan screen');
    if (widget.returnSelection) {
      context.pop(selection);
      return;
    }

    await context.push(WearScanIdleScreen.route, extra: selection);
    _isScanScreenOpen = false;
    print(
      '[BACK-DEBUG] PrinterSelect._openScanScreen: scan popped back, '
      'mounted=$mounted, _isScanScreenOpen=$_isScanScreenOpen',
    );

    if (!mounted) {
      return;
    }
    if (!_isCurrentRoute()) {
      print(
        '[BACK-DEBUG] PrinterSelect._openScanScreen: '
        'screen is not current after scan pop, skip glasses update',
      );
      return;
    }
    _sendGlassesState(ref.read(wearPrinterSelectNotifierProvider));
  }

  void _sendGlassesState(WearPrinterSelectState state, {bool fast = false}) {
    if (!mounted) return;
    if (_isScanScreenOpen || !_isCurrentRoute()) {
      print(
        '[PrinterSelect] skip glasses update: '
        '_isScanScreenOpen=$_isScanScreenOpen isCurrent=${_isCurrentRoute()}',
      );
      return;
    }

    Future<void> Function(WearGlassesPayload) send = fast
        ? WearStatusIconReporter.I.sendFast
        : WearStatusIconReporter.I.send;

    if (state.isLoading) {
      const WearGlassesPayload payload = WearGlassesPayload(
        screenType: WearGlassesScreenType.printer,
        phase: WearGlassesPhase.loading,
        title: 'Выбор принтера',
        statusText: 'Инициализация...',
        isLoading: true,
      );
      _flowController.rememberScreenPayload(
          WearScreenId.printerSelect, payload);
      send(payload);
      return;
    }

    if (state.hasError && state.printers.isEmpty) {
      final WearGlassesPayload payload = WearGlassesPayload.status(
        isError: true,
        title: 'Ошибка загрузки принтеров',
        subtitle: state.error,
      );
      _flowController.rememberScreenPayload(
          WearScreenId.printerSelect, payload);
      send(payload);
      return;
    }

    final List<WearPrinter> printers = _visiblePrinters(state);
    if (printers.isEmpty) return;
    final int selected = _focusedIndex.clamp(0, printers.length - 1);
    final int start = _pageStart(selected);
    final List<WearPrinter> visiblePrinters = printers
        .skip(start)
        .take(_visibleGlassesItemCount)
        .toList(growable: false);
    final VoiceDynamicItemsSnapshot snapshot = _dynamicVoiceItems();
    final WearGlassesPayload payload = WearGlassesPayload(
      screenType: WearGlassesScreenType.printer,
      phase: WearGlassesPhase.idle,
      title: 'Выбор принтера',
      subtitle: state.step == WearPrinterSelectStep.yellow
          ? 'Жёлтые ценники'
          : 'Белые ценники',
      items: visiblePrinters
          .map((WearPrinter printer) => printer.name)
          .toList(growable: false),
      voiceHints: WearGlassesVoiceHints.forVisibleItems(
        screen: WearScreenId.printerSelect,
        snapshot: snapshot,
        visibleItemIds: visiblePrinters
            .map((WearPrinter printer) => printer.id)
            .toList(growable: false),
        onPrepared: () {
          if (!mounted || _dynamicVoiceItems().revision != snapshot.revision) {
            return;
          }
          _sendGlassesState(
            ref.read(wearPrinterSelectNotifierProvider),
            fast: true,
          );
        },
      ),
      selectedIndex: selected - start,
      pageText: _pageText(printers.length, selected),
    );
    _flowController.rememberScreenPayload(WearScreenId.printerSelect, payload);
    send(payload);
  }

  static const int _visibleGlassesItemCount = 4;

  int _pageStart(int selectedIndex) {
    return (selectedIndex ~/ _visibleGlassesItemCount) *
        _visibleGlassesItemCount;
  }

  String? _pageText(int itemCount, int selectedIndex) {
    if (itemCount <= _visibleGlassesItemCount) return null;
    final int page = (selectedIndex ~/ _visibleGlassesItemCount) + 1;
    final int pageCount = ((itemCount - 1) ~/ _visibleGlassesItemCount) + 1;
    return 'Страница: $page из $pageCount';
  }

  void _scrollToTop() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.jumpTo(0.0);
    });
  }

  bool _isCurrentRoute() {
    final ModalRoute<dynamic>? route = ModalRoute.of(context);
    return route == null || route.isCurrent;
  }
}
