import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_glasses/modules/wear/domain/availability/model/wear_availability_flow_state.dart';
import 'package:smart_glasses/modules/wear/domain/availability/model/wear_availability_product.dart';
import 'package:smart_glasses/modules/wear/presentation/glasses/wear_availability_glasses_payloads.dart';
import 'package:smart_glasses/modules/wear/presentation/glasses/wear_glasses_payload.dart';
import 'package:smart_glasses/modules/wear/presentation/input/wear_print_code_input_screen.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/availability/cubit/wear_availability_check_cubit.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/status/wear_status_args.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/status/wear_status_screen.dart';
import 'package:smart_glasses/modules/wear/presentation/widgets/wear_loading.dart';
import 'package:smart_glasses/modules/wear/presentation/widgets/wear_pill.dart';
import 'package:smart_glasses/modules/wear/presentation/widgets/wear_screen_scaffold.dart';
import 'package:smart_glasses/modules/wear/services/wear_status_icon_reporter.dart';
import 'package:smart_glasses/modules/wear/theme/wear_colors.dart';
import 'package:smart_glasses/modules/wear/theme/wear_images.dart';
import 'package:smart_glasses/modules/wear/theme/wear_typography.dart';

class WearAvailabilityCheckScreen extends ConsumerStatefulWidget {
  const WearAvailabilityCheckScreen({
    super.key,
    required this.product,
  });

  static const String route = '/wear_availability_check';

  final WearAvailabilityProduct? product;

  @override
  ConsumerState<WearAvailabilityCheckScreen> createState() =>
      _WearAvailabilityCheckScreenState();
}

class _WearAvailabilityCheckScreenState
    extends ConsumerState<WearAvailabilityCheckScreen> {
  bool _isStatusRouteOpen = false;
  int _statusRouteSession = 0;

  @override
  Widget build(BuildContext context) {
    final WearAvailabilityProduct? product = widget.product;
    if (product == null) {
      return WearScreenScaffold(
        showHomeButton: true,
        child: _buildMessage('Товар не выбран'),
      );
    }

    final provider = wearAvailabilityCheckNotifierProvider(product);
    final WearAvailabilityCheckState state = ref.watch(provider);

    ref.listen<WearAvailabilityCheckState>(provider,
        (WearAvailabilityCheckState? previous,
            WearAvailabilityCheckState next) {
      if (previous?.flow != next.flow ||
          previous?.phase != next.phase ||
          previous?.loadingText != next.loadingText) {
        _sendGlassesState(next);
      }
      if (previous?.navStatus != next.navStatus && next.navStatus != null) {
        final WearStatusScreenArgs args = next.navStatus!;
        WearStatusIconReporter.I.send(
          WearGlassesPayload.status(
            isError: args.kind == WearStatusKind.error,
            title: args.title,
            subtitle: args.message,
            statusText: args.kind == WearStatusKind.error ? 'Ошибка' : 'Готово',
            statusIcon:
                args.kind == WearStatusKind.success ? WearImages.good : null,
          ),
        );
        ref.read(provider.notifier).consumeNavigation();
        _openOrReplaceStatus(args);
      }
    });

    return WearScreenScaffold(
      showHomeButton: true,
      child: Stack(
        children: <Widget>[
          Center(
            child: Padding(
              padding: const EdgeInsets.all(4.5),
              child: _CheckContent(
                state: state,
                onYes: () =>
                    ref.read(provider.notifier).answerProductAvailable(true),
                onNo: () =>
                    ref.read(provider.notifier).answerProductAvailable(false),
                onManualInput: () => _manualInput(provider),
                onPrint: () => ref.read(provider.notifier).printPriceTag(),
                onPhoto: () => ref.read(provider.notifier).capturePhoto(),
                onComplete: () => ref.read(provider.notifier).complete(),
                onBackToList: () => context.pop(),
              ),
            ),
          ),
          if (state.isLoading)
            Positioned.fill(
              child: ColoredBox(
                color: const Color(0xCCFFFFFF),
                child: Center(
                  child: _LoadingContent(state: state),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _manualInput(
    AutoDisposeStateNotifierProvider<WearAvailabilityCheckNotifier,
            WearAvailabilityCheckState>
        provider,
  ) async {
    final String? code = await context.push<String>(
      WearPrintCodeInputScreen.route,
    );
    if (code == null || code.trim().isEmpty) return;
    ref.read(provider.notifier).handleBarcode(code.trim());
  }

  Widget _buildMessage(String message) {
    return Center(
      child: Text(
        message,
        style: WearTypography.lable,
        textAlign: TextAlign.center,
      ),
    );
  }

  void _sendGlassesState(WearAvailabilityCheckState state) {
    final WearAvailabilityFlowState flow = state.flow;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (state.isLoading) {
        WearStatusIconReporter.I.send(
          WearAvailabilityGlassesPayloads.loading(
            title: 'Доступность',
            subtitle: flow.selectedProduct?.name,
            statusText: state.loadingText,
            statusIcon: state.loadingIcon,
          ),
        );
        return;
      }
      WearStatusIconReporter.I.send(
        WearAvailabilityGlassesPayloads.fromFlow(flow),
      );
    });
  }

  Future<void> _openOrReplaceStatus(WearStatusScreenArgs args) async {
    final int session = ++_statusRouteSession;
    final bool checkScreenIsCurrent = ModalRoute.of(context)?.isCurrent ?? true;

    if (_isStatusRouteOpen && !checkScreenIsCurrent) {
      if (mounted && Navigator.of(context).canPop()) {
        context.pop();
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }

    if (!mounted) return;

    _isStatusRouteOpen = true;
    await context.push(WearStatusScreen.route, extra: args);

    if (!mounted) return;
    if (session == _statusRouteSession) {
      _isStatusRouteOpen = false;
    }
  }
}

class _CheckContent extends StatelessWidget {
  const _CheckContent({
    required this.state,
    required this.onYes,
    required this.onNo,
    required this.onManualInput,
    required this.onPrint,
    required this.onPhoto,
    required this.onComplete,
    required this.onBackToList,
  });

  final WearAvailabilityCheckState state;
  final VoidCallback onYes;
  final VoidCallback onNo;
  final VoidCallback onManualInput;
  final VoidCallback onPrint;
  final VoidCallback onPhoto;
  final VoidCallback onComplete;
  final VoidCallback onBackToList;

  @override
  Widget build(BuildContext context) {
    final WearAvailabilityFlowState flow = state.flow;
    final WearAvailabilityProduct? product = flow.selectedProduct;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          _screenTitle(flow.step),
          style: WearTypography.lable18,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          product?.name ?? '',
          style: WearTypography.lable,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        if (product != null)
          Text(
            'Код ${product.code} · ост. ${_rest(product.rest)} · ${_price(product)}',
            style: WearTypography.bodyxsm,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        const SizedBox(height: 16),
        Text(
          flow.message ?? _defaultMessage(flow.step),
          style: WearTypography.bodysml.copyWith(
            color: flow.step == WearAvailabilityFlowStep.manualInventoryRequired
                ? WearColors.buttonPrimary
                : WearColors.textDefault,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        _Actions(
          step: flow.step,
          onYes: onYes,
          onNo: onNo,
          onManualInput: onManualInput,
          onPrint: onPrint,
          onPhoto: onPhoto,
          onComplete: onComplete,
          onBackToList: onBackToList,
        ),
      ],
    );
  }

  String _screenTitle(WearAvailabilityFlowStep step) {
    return switch (step) {
      WearAvailabilityFlowStep.productQuestion => 'Товар есть на полке?',
      WearAvailabilityFlowStep.productScan => 'Сканирование товара',
      WearAvailabilityFlowStep.priceTagScan => 'Проверка ценника',
      WearAvailabilityFlowStep.priceTagOutdated => 'Ценник неактуален',
      WearAvailabilityFlowStep.photoCapture => 'Фотофиксация',
      WearAvailabilityFlowStep.readyToComplete => 'Завершение проверки',
      WearAvailabilityFlowStep.manualInventoryRequired => 'Требуется действие',
      WearAvailabilityFlowStep.completed => 'Проверка завершена',
      _ => 'Доступность',
    };
  }

  String _defaultMessage(WearAvailabilityFlowStep step) {
    return switch (step) {
      WearAvailabilityFlowStep.productScan => 'Отсканируйте ШК товара',
      WearAvailabilityFlowStep.priceTagScan => 'Отсканируйте ценник',
      WearAvailabilityFlowStep.priceTagOutdated => 'Напечатайте новый ценник',
      WearAvailabilityFlowStep.photoCapture => 'Сделайте фото выкладки',
      WearAvailabilityFlowStep.readyToComplete => 'Можно завершить проверку',
      _ => '',
    };
  }

  String _rest(double value) {
    if (value == value.roundToDouble()) return value.toInt().toString();
    return value.toStringAsFixed(2);
  }

  String _price(WearAvailabilityProduct product) {
    return '${product.price.toStringAsFixed(2)} ₽';
  }
}

class _Actions extends StatelessWidget {
  const _Actions({
    required this.step,
    required this.onYes,
    required this.onNo,
    required this.onManualInput,
    required this.onPrint,
    required this.onPhoto,
    required this.onComplete,
    required this.onBackToList,
  });

  final WearAvailabilityFlowStep step;
  final VoidCallback onYes;
  final VoidCallback onNo;
  final VoidCallback onManualInput;
  final VoidCallback onPrint;
  final VoidCallback onPhoto;
  final VoidCallback onComplete;
  final VoidCallback onBackToList;

  @override
  Widget build(BuildContext context) {
    return switch (step) {
      WearAvailabilityFlowStep.productQuestion => Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            SizedBox(
              width: 96,
              child: WearPill(title: 'Да', onTap: onYes),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 96,
              child: WearPill(title: 'Нет', onTap: onNo),
            ),
          ],
        ),
      WearAvailabilityFlowStep.productScan ||
      WearAvailabilityFlowStep.priceTagScan =>
        SizedBox(
          width: 150,
          child: WearPill(
            title: 'Ручной ввод',
            icon: WearImages.barcode,
            onTap: onManualInput,
          ),
        ),
      WearAvailabilityFlowStep.priceTagOutdated => SizedBox(
          width: 150,
          child: WearPill(
            title: 'Напечатать',
            icon: WearImages.printer,
            onTap: onPrint,
          ),
        ),
      WearAvailabilityFlowStep.photoCapture => SizedBox(
          width: 150,
          child: WearPill(
            title: 'Фото сделано',
            onTap: onPhoto,
          ),
        ),
      WearAvailabilityFlowStep.readyToComplete ||
      WearAvailabilityFlowStep.manualInventoryRequired =>
        SizedBox(
          width: 150,
          child: WearPill(
            title: 'Завершить',
            icon: WearImages.ok,
            onTap: onComplete,
          ),
        ),
      WearAvailabilityFlowStep.completed => SizedBox(
          width: 150,
          child: WearPill(
            title: 'К списку',
            onTap: onBackToList,
          ),
        ),
      _ => const SizedBox.shrink(),
    };
  }
}

class _LoadingContent extends StatelessWidget {
  const _LoadingContent({required this.state});

  final WearAvailabilityCheckState state;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const WearLoading(size: 44),
        const SizedBox(height: 12),
        Text(
          state.loadingText,
          style: WearTypography.lable,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
