import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_glasses/modules/wear/models/wear_printer.dart';
import 'package:smart_glasses/modules/wear/models/wear_printer_selection.dart';
import 'package:smart_glasses/modules/wear/presentation/glasses/wear_glasses_bridge.dart';
import 'package:smart_glasses/modules/wear/presentation/glasses/wear_glasses_payload.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/printers/cubit/wear_printer_select_cubit.dart';

import 'package:smart_glasses/modules/wear/presentation/screens/scan/wear_scan_idle_screen.dart';
import 'package:smart_glasses/modules/wear/presentation/widgets/wear_loading.dart';
import 'package:smart_glasses/modules/wear/presentation/widgets/wear_pill.dart';
import 'package:smart_glasses/modules/wear/presentation/widgets/wear_scaling_list_view.dart';
import 'package:smart_glasses/modules/wear/presentation/widgets/wear_screen_scaffold.dart';
import 'package:smart_glasses/modules/wear/theme/wear_images.dart';
import 'package:smart_glasses/modules/wear/theme/wear_typography.dart';

class WearPrinterSelectScreen extends ConsumerStatefulWidget {
  const WearPrinterSelectScreen({super.key});

  static const String route = '/wear_printer_select';

  @override
  ConsumerState<WearPrinterSelectScreen> createState() =>
      _WearPrinterSelectScreenState();
}

class _WearPrinterSelectScreenState
    extends ConsumerState<WearPrinterSelectScreen> {
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _sendGlassesState(ref.read(wearPrinterSelectNotifierProvider));
    });
  }

  @override
  void dispose() {
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
      ),
    );
  }

  String _headerText(WearPrinterSelectStep step) {
    if (step == WearPrinterSelectStep.yellow) {
      return 'Выберите принтер\nдля желтых ценников';
    }
    return 'Выберите принтер\nдля белых ценников';
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

  void _openScanScreen(BuildContext context, WearPrinterSelectState state) {
    final WearPrinter? white = state.whitePrinter;
    final WearPrinter? yellow = state.yellowPrinter;
    if (white == null || yellow == null) {
      return;
    }
    if (white.id == yellow.id) {
      return;
    }
    final WearPrinterSelection selection = WearPrinterSelection(
      whitePrinter: white,
      yellowPrinter: yellow,
    );
    context.go(WearScanIdleScreen.route, extra: selection);
  }

  void _sendGlassesState(WearPrinterSelectState state) {
    if (state.isLoading) {
      wearGlassesBridge.update(
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
      wearGlassesBridge.update(
        WearGlassesPayload.status(
          isError: true,
          title: 'Ошибка загрузки принтеров',
          subtitle: state.error,
        ),
      );
      return;
    }

    final List<WearPrinter> printers = _visiblePrinters(state);
    wearGlassesBridge.update(
      WearGlassesPayload(
        screenType: WearGlassesScreenType.printer,
        phase: WearGlassesPhase.idle,
        title: 'Выбор принтера',
        subtitle: state.step == WearPrinterSelectStep.yellow
            ? 'Жёлтые ценники'
            : 'Белые ценники',
        items: printers.map((WearPrinter printer) => printer.name).toList(),
        selectedIndex: 0,
        pageText: printers.length > 5 ? 'Показаны первые 5' : null,
      ),
    );
  }

  void _scrollToTop() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.jumpTo(0.0);
    });
  }
}
