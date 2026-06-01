import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_glasses/modules/wear/domain/price_tag_print/model/barcode_product_info.dart';
import 'package:smart_glasses/modules/wear/models/wear_printer_selection.dart';
import 'package:smart_glasses/modules/wear/presentation/glasses/wear_glasses_bridge.dart';
import 'package:smart_glasses/modules/wear/presentation/glasses/wear_glasses_payload.dart';
import 'package:smart_glasses/modules/wear/presentation/input/wear_print_code_input_screen.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/scan/cubit/wear_scan_cubit.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/scan/wear_product_select_screen.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/status/wear_status_args.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/status/wear_status_screen.dart';
import 'package:smart_glasses/modules/wear/presentation/widgets/wear_loading.dart';
import 'package:smart_glasses/modules/wear/presentation/widgets/wear_screen_scaffold.dart';
import 'package:smart_glasses/modules/wear/theme/wear_colors.dart';
import 'package:smart_glasses/modules/wear/theme/wear_typography.dart';

class WearScanIdleScreen extends ConsumerStatefulWidget {
  const WearScanIdleScreen({
    super.key,
    required this.printers,
  });

  static const String route = '/wear_scan_idle';

  final WearPrinterSelection? printers;

  @override
  ConsumerState<WearScanIdleScreen> createState() => _WearScanIdleScreenState();
}

class _WearScanIdleScreenState extends ConsumerState<WearScanIdleScreen> {
  bool _isStatusRouteOpen = false;
  int _statusRouteSession = 0;

  AutoDisposeStateNotifierProvider<WearScanNotifier, WearScanState>
      get _provider => wearScanNotifierProvider(widget.printers);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      wearGlassesBridge.update(WearGlassesPayload.scanWaiting());
    });
  }

  @override
  Widget build(BuildContext context) {
    final WearScanState state = ref.watch(_provider);

    ref.listen<WearScanState>(_provider,
        (WearScanState? previous, WearScanState next) {
      if (previous?.phase != next.phase && next.phase == WearScanPhase.loading) {
        wearGlassesBridge.update(WearGlassesPayload.scanLoading());
        _dismissStatusIfOpen();
      }

      if (previous?.navStatus != next.navStatus && next.navStatus != null) {
        final WearStatusScreenArgs nav = next.navStatus!;
        wearGlassesBridge.update(
          WearGlassesPayload.status(
            isError: nav.kind == WearStatusKind.error,
            title: nav.title,
            subtitle: nav.message,
            statusText: nav.kind == WearStatusKind.error ? 'Ошибка' : 'Успешно',
          ),
        );
        ref.read(_provider.notifier).consumeNavigation();
        _openOrReplaceStatus(nav);
      }
      if (previous?.navSelect != next.navSelect && next.navSelect != null) {
        final WearProductSelectArgs args = next.navSelect!;
        wearGlassesBridge.update(
          WearGlassesPayload(
            screenType: WearGlassesScreenType.productSelect,
            phase: WearGlassesPhase.idle,
            title: 'Дубль ШК',
            subtitle: 'Выберите нужный товар',
            items: args.products.map((BarcodeProductInfo p) => p.name).toList(),
            selectedIndex: 0,
            pageText: args.products.length > 5 ? 'Показаны первые 5' : null,
          ),
        );
        ref.read(_provider.notifier).consumeNavigation();
        _openProductSelect(args);
      }
    });

    return WearScreenScaffold(
      showHomeButton: true,
      child: Stack(
        children: <Widget>[
          Center(
            child: Padding(
              padding: const EdgeInsets.all(4.5),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    'Для печати\nотсканируйте ценник\nили товар',
                    style: WearTypography.lable.copyWith(height: 1.25),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  _PillButton(
                    title: 'Ручной ввод',
                    onTap: () async {
                      final String? code = await context.push<String>(
                        WearPrintCodeInputScreen.route,
                      );

                      if (code == null || code.trim().isEmpty) {
                        return;
                      }
                      ref.read(_provider.notifier).handleBarcode(code.trim());
                    },
                  ),
                ],
              ),
            ),
          ),
          if (state.isLoading)
            const Positioned.fill(
              child: ColoredBox(
                color: Color(0x66FFFFFF),
                child: Center(
                  child: WearLoading(size: 44),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _openOrReplaceStatus(WearStatusScreenArgs args) async {
    final int session = ++_statusRouteSession;
    final bool scanScreenIsCurrent = ModalRoute.of(context)?.isCurrent ?? true;

    if (_isStatusRouteOpen && !scanScreenIsCurrent) {
      if (mounted && Navigator.of(context).canPop()) {
        context.pop();
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }

    if (!mounted) {
      return;
    }

    _isStatusRouteOpen = true;
    await context.push(WearStatusScreen.route, extra: args);

    if (!mounted) {
      return;
    }
    if (session == _statusRouteSession) {
      _isStatusRouteOpen = false;
    }
  }

  void _dismissStatusIfOpen() {
    final bool scanScreenIsCurrent = ModalRoute.of(context)?.isCurrent ?? true;
    if (!_isStatusRouteOpen || scanScreenIsCurrent) {
      return;
    }
    if (Navigator.of(context).canPop()) {
      context.pop();
    }
    _isStatusRouteOpen = false;
  }

  Future<void> _openProductSelect(
    WearProductSelectArgs args,
  ) async {
    final bool scanScreenIsCurrent = ModalRoute.of(context)?.isCurrent ?? true;
    if (_isStatusRouteOpen && !scanScreenIsCurrent) {
      if (mounted && Navigator.of(context).canPop()) {
        context.pop();
      }
      _isStatusRouteOpen = false;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }

    if (!mounted) {
      return;
    }

    final BarcodeProductInfo? product = await context.push<BarcodeProductInfo>(
      WearProductSelectScreen.route,
      extra: args,
    );
    if (product == null) {
      return;
    }
    ref.read(_provider.notifier).printSelectedProduct(product);
  }
}

class _PillButton extends StatelessWidget {
  const _PillButton({
    required this.title,
    required this.onTap,
  });

  final String title;
  final VoidCallback onTap;

  static const double _radius = 33.0;
  static const double _height = 34.0;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: WearColors.buttonSecondaryDefault,
      borderRadius: BorderRadius.circular(_radius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 123,
          height: _height,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Center(
              child: Text(
                title,
                style: WearTypography.lable.copyWith(fontSize: 15),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
