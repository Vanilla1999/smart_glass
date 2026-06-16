import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_glasses/modules/wear/application/wear_flow_controller.dart';
import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/config/wear_dependencies.dart';
import 'package:smart_glasses/modules/wear/config/wear_session.dart';
import 'package:smart_glasses/modules/wear/infrastructure/screen_lifecycle_logging.dart';
import 'package:smart_glasses/modules/wear/models/wear_printer.dart';
import 'package:smart_glasses/modules/wear/models/wear_printer_selection.dart';
import 'package:smart_glasses/modules/wear/presentation/glasses/wear_glasses_payload.dart';
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
  const WearPrinterSelectScreen({super.key, this.flowController});

  static const String route = '/wear_printer_select';

  final WearFlowController? flowController;

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
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
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
    print('[PrinterSelect] _onVoiceSelect called, focusedIndex=$_focusedIndex');
    final WearPrinterSelectState s =
        ref.read(wearPrinterSelectNotifierProvider);
    if (s.isLoading || s.printers.isEmpty) return;
    final List<WearPrinter> printers = _visiblePrinters(s);
    if (_focusedIndex >= 0 && _focusedIndex < printers.length) {
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

  List<WearPrinter> _visiblePrinters(WearPrinterSelectState state) {
    if (state.step == WearPrinterSelectStep.yellow &&
        state.whitePrinter != null) {
      return state.printers
          .where((WearPrinter p) => p.id != state.whitePrinter!.id)
          .toList();
    }
    return state.printers;
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
      send(
        const WearGlassesPayload(
          screenType: WearGlassesScreenType.printer,
          phase: WearGlassesPhase.loading,
          title: 'Выбор принтера',
          statusText: 'Инициализация...',
          isLoading: true,
        ),
      );
      return;
    }

    if (state.hasError && state.printers.isEmpty) {
      send(
        WearGlassesPayload.status(
          isError: true,
          title: 'Ошибка загрузки принтеров',
          subtitle: state.error,
        ),
      );
      return;
    }

    final List<WearPrinter> printers = _visiblePrinters(state);
    if (printers.isEmpty) return;
    send(
      WearGlassesPayload(
        screenType: WearGlassesScreenType.printer,
        phase: WearGlassesPhase.idle,
        title: 'Выбор принтера',
        subtitle: state.step == WearPrinterSelectStep.yellow
            ? 'Жёлтые ценники'
            : 'Белые ценники',
        items: printers.map((WearPrinter printer) => printer.name).toList(),
        selectedIndex: _focusedIndex.clamp(0, printers.length - 1),
        pageText: printers.length > 4 ? 'Показаны первые 4' : null,
      ),
    );
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
