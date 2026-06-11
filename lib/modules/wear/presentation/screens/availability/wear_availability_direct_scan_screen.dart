import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_glasses/modules/wear/domain/availability/model/wear_availability_product.dart';
import 'package:smart_glasses/modules/wear/presentation/glasses/wear_availability_glasses_payloads.dart';
import 'package:smart_glasses/modules/wear/presentation/input/wear_print_code_input_screen.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/availability/cubit/wear_availability_direct_scan_cubit.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/availability/wear_availability_check_screen.dart';
import 'package:smart_glasses/modules/wear/presentation/widgets/wear_loading.dart';
import 'package:smart_glasses/modules/wear/presentation/widgets/wear_pill.dart';
import 'package:smart_glasses/modules/wear/presentation/widgets/wear_scaling_list_view.dart';
import 'package:smart_glasses/modules/wear/presentation/widgets/wear_screen_scaffold.dart';
import 'package:smart_glasses/modules/wear/services/wear_status_icon_reporter.dart';
import 'package:smart_glasses/modules/wear/theme/wear_colors.dart';
import 'package:smart_glasses/modules/wear/theme/wear_images.dart';
import 'package:smart_glasses/modules/wear/theme/wear_typography.dart';

class WearAvailabilityDirectScanScreen extends ConsumerStatefulWidget {
  const WearAvailabilityDirectScanScreen({super.key});

  static const String route = '/wear_availability_direct_scan';

  @override
  ConsumerState<WearAvailabilityDirectScanScreen> createState() =>
      _WearAvailabilityDirectScanScreenState();
}

class _WearAvailabilityDirectScanScreenState
    extends ConsumerState<WearAvailabilityDirectScanScreen> {
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WearStatusIconReporter.I.send(
        WearAvailabilityGlassesPayloads.directScanWaiting(),
      );
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final WearAvailabilityDirectScanState state =
        ref.watch(wearAvailabilityDirectScanProvider);

    ref.listen<WearAvailabilityDirectScanState>(
      wearAvailabilityDirectScanProvider,
      (
        WearAvailabilityDirectScanState? previous,
        WearAvailabilityDirectScanState next,
      ) {
        _sendGlassesState(next);
        if (previous?.navProduct != next.navProduct &&
            next.navProduct != null) {
          final WearAvailabilityProduct product = next.navProduct!;
          ref
              .read(wearAvailabilityDirectScanProvider.notifier)
              .consumeNavigation();
          _openCheck(product);
        }
      },
    );

    return WearScreenScaffold(
      showHomeButton: true,
      scrollController: _scroll,
      child: Stack(
        children: <Widget>[
          Center(
            child: Padding(
              padding: const EdgeInsets.all(4.5),
              child: state.duplicateProducts.isEmpty
                  ? _DirectScanContent(
                      message: state.message,
                      onManualInput: _manualInput,
                    )
                  : _DuplicateProductsContent(
                      scroll: _scroll,
                      products: state.duplicateProducts,
                      onSelect: _openCheck,
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

  Future<void> _manualInput() async {
    final String? code = await context.push<String>(
      WearPrintCodeInputScreen.route,
    );
    if (code == null || code.trim().isEmpty) return;
    ref
        .read(wearAvailabilityDirectScanProvider.notifier)
        .handleBarcode(code.trim());
  }

  Future<void> _openCheck(WearAvailabilityProduct product) async {
    if (!mounted) return;
    await context.push(WearAvailabilityCheckScreen.route, extra: product);
  }

  void _sendGlassesState(WearAvailabilityDirectScanState state) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (state.isLoading) {
        WearStatusIconReporter.I.send(
          WearAvailabilityGlassesPayloads.loading(
            title: 'Сканирование товара',
            statusText: state.loadingText,
            statusIcon: state.loadingIcon,
          ),
        );
        return;
      }
      if (state.duplicateProducts.isNotEmpty) {
        WearStatusIconReporter.I.send(
          WearAvailabilityGlassesPayloads.duplicates(state.duplicateProducts),
        );
        return;
      }
      WearStatusIconReporter.I.send(
        WearAvailabilityGlassesPayloads.directScanWaiting(
          statusText: state.message,
        ),
      );
    });
  }
}

class _DirectScanContent extends StatelessWidget {
  const _DirectScanContent({
    required this.message,
    required this.onManualInput,
  });

  final String message;
  final VoidCallback onManualInput;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          'Сканирование товара',
          style: WearTypography.lable18,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'Наведите камеру\nна штрих-код',
          style: WearTypography.lable.copyWith(
            color: WearColors.textSecondary,
            height: 1.2,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 14),
        Text(
          message,
          style: WearTypography.bodysml,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: 150,
          child: WearPill(
            title: 'Ручной ввод',
            icon: WearImages.barcode,
            onTap: onManualInput,
          ),
        ),
      ],
    );
  }
}

class _DuplicateProductsContent extends StatelessWidget {
  const _DuplicateProductsContent({
    required this.scroll,
    required this.products,
    required this.onSelect,
  });

  final ScrollController scroll;
  final List<WearAvailabilityProduct> products;
  final ValueChanged<WearAvailabilityProduct> onSelect;

  @override
  Widget build(BuildContext context) {
    return WearScalingListView(
      controller: scroll,
      itemCount: products.length + 2,
      itemExtent: 56,
      padding: const EdgeInsets.fromLTRB(0, 40, 0, 4.5),
      edgeFractionTop: 0.0,
      minScale: 0.68,
      minOpacity: 0.26,
      extraSideInset: 40,
      itemBuilder: (BuildContext context, int i) {
        if (i == 0) {
          return Align(
            alignment: Alignment.topCenter,
            child: Text(
              'Дубль ШК',
              style: WearTypography.lable,
              textAlign: TextAlign.center,
            ),
          );
        }
        if (i == products.length + 1) {
          return const SizedBox.shrink();
        }

        final WearAvailabilityProduct product = products[i - 1];
        return WearPill(
          title: product.name,
          subtitle: 'Код ${product.code}',
          icon: WearImages.barcode,
          onTap: () => onSelect(product),
        );
      },
    );
  }
}

class _LoadingContent extends StatelessWidget {
  const _LoadingContent({required this.state});

  final WearAvailabilityDirectScanState state;

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
