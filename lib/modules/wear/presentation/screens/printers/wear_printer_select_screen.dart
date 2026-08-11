import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_glasses/modules/wear/application/wear_flow_controller.dart';
import 'package:smart_glasses/modules/wear/application/wear_printer_runtime.dart';
import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/config/wear_dependencies.dart';
import 'package:smart_glasses/modules/wear/infrastructure/screen_lifecycle_logging.dart';
import 'package:smart_glasses/modules/wear/models/wear_printer.dart';
import 'package:smart_glasses/modules/wear/presentation/widgets/wear_loading.dart';
import 'package:smart_glasses/modules/wear/presentation/widgets/wear_pill.dart';
import 'package:smart_glasses/modules/wear/presentation/widgets/wear_scaling_list_view.dart';
import 'package:smart_glasses/modules/wear/presentation/widgets/wear_screen_scaffold.dart';
import 'package:smart_glasses/modules/wear/theme/wear_images.dart';
import 'package:smart_glasses/modules/wear/theme/wear_typography.dart';

class WearPrinterSelectScreen extends StatefulWidget {
  const WearPrinterSelectScreen({
    super.key,
    this.flowController,
    this.returnSelection = false,
  });

  static const String route = '/wear_printer_select';

  final WearFlowController? flowController;
  final bool returnSelection;

  @override
  State<WearPrinterSelectScreen> createState() =>
      _WearPrinterSelectScreenState();
}

class _WearPrinterSelectScreenState extends State<WearPrinterSelectScreen>
    with ScreenLifecycleLogging<WearPrinterSelectScreen> {
  final ScrollController _scroll = ScrollController();
  late final WearFlowController _flowController;
  late final StreamSubscription<WearPrinterRuntimeState> _stateSubscription;
  late WearPrinterRuntimeState _state;
  bool _selectionReturned = false;

  @override
  void initState() {
    super.initState();
    _flowController =
        widget.flowController ?? WearDependencies.I.wearFlowController;
    _state = _flowController.printerState;
    _stateSubscription = _flowController.printerStateStream.listen(_onState);
    _flowController.enterScreen(
      WearScreenId.printerSelect,
      extra: widget.returnSelection,
    );
  }

  void _onState(WearPrinterRuntimeState next) {
    final int previousIndex = _state.focusedIndex;
    final WearPrinterRuntimeStep previousStep = _state.step;
    if (mounted) setState(() => _state = next);
    if (previousStep != next.step || previousIndex != next.focusedIndex) {
      _scrollToFocused(next.focusedIndex);
    }
    if (widget.returnSelection &&
        !_selectionReturned &&
        next.selection != null) {
      _selectionReturned = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.pop(next.selection);
      });
    }
  }

  @override
  void dispose() {
    unawaited(_stateSubscription.cancel());
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return WearScreenScaffold(
      showHomeButton: true,
      scrollController: _scroll,
      child: _buildContent(),
    );
  }

  Widget _buildContent() {
    if (_state.isLoading) {
      return const Center(child: WearLoading());
    }
    if (_state.error != null && _state.printers.isEmpty) {
      return _buildRefreshableMessage(
        'Ошибка загрузки принтеров\n${_state.error}',
      );
    }

    final List<WearPrinter> printers = _state.visiblePrinters;
    if (printers.isEmpty) {
      return _buildRefreshableMessage('Список принтеров пуст.');
    }

    return RefreshIndicator(
      onRefresh: _flowController.reloadPrinters,
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
        itemBuilder: (BuildContext context, int index) {
          if (index == 0) {
            return Align(
              alignment: Alignment.topCenter,
              child: Text(
                _headerText,
                style: WearTypography.lable,
                textAlign: TextAlign.center,
              ),
            );
          }
          if (index == printers.length + 1) return const SizedBox.shrink();
          final WearPrinter printer = printers[index - 1];
          return WearPill(
            title: printer.name,
            icon: WearImages.printer,
            onTap: () => _flowController.selectPrinter(printer),
          );
        },
        onFocusChanged: (int listIndex) {
          _flowController.focusPrinter(
            (listIndex - 1).clamp(0, printers.length - 1),
          );
        },
      ),
    );
  }

  Widget _buildRefreshableMessage(String message) {
    return RefreshIndicator(
      onRefresh: _flowController.reloadPrinters,
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
        itemBuilder: (BuildContext context, int index) {
          return Align(
            alignment: Alignment.center,
            child: Text(
              index == 0 ? _headerText : message,
              style: WearTypography.lable,
              textAlign: TextAlign.center,
            ),
          );
        },
      ),
    );
  }

  String get _headerText => _state.step == WearPrinterRuntimeStep.yellow
      ? 'Выберите принтер\nдля желтых ценников'
      : 'Выберите принтер\nдля белых ценников';

  void _scrollToFocused(int index) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final double target = (index * 56.0).clamp(
        0.0,
        _scroll.position.maxScrollExtent,
      );
      _scroll.animateTo(
        target,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
      );
    });
  }
}
