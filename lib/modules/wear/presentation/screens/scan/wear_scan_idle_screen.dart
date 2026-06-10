import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_glasses/modules/wear/domain/price_tag_print/model/barcode_product_info.dart';
import 'package:smart_glasses/modules/wear/models/wear_printer_selection.dart';
import 'package:smart_glasses/modules/wear/presentation/glasses/wear_glasses_payload.dart';
import 'package:smart_glasses/modules/wear/presentation/input/wear_print_code_input_screen.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/scan/cubit/wear_scan_cubit.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/scan/wear_product_select_screen.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/continue_scan/wear_continue_scan_screen.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/status/wear_status_args.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/status/wear_status_screen.dart';
import 'package:smart_glasses/modules/wear/presentation/widgets/wear_screen_scaffold.dart';
import 'package:smart_glasses/modules/wear/presentation/widgets/wear_svg_icon.dart';
import 'package:smart_glasses/modules/wear/presentation/widgets/wear_voice_command_listener.dart';
import 'package:smart_glasses/modules/wear/services/wear_status_icon_reporter.dart';
import 'package:smart_glasses/modules/wear/theme/wear_colors.dart';
import 'package:smart_glasses/modules/wear/theme/wear_images.dart';
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
      WearStatusIconReporter.I.send(WearGlassesPayload.scanWaiting());
    });
  }

  Future<void> _onVoiceSelect() async {
    final String? code = await context.push<String>(
      WearPrintCodeInputScreen.route,
    );
    if (code == null || code.trim().isEmpty) {
      return;
    }
    ref.read(_provider.notifier).handleBarcode(code.trim());
  }

  @override
  Widget build(BuildContext context) {
    final WearScanState state = ref.watch(_provider);

    ref.listen<WearScanState>(_provider,
        (WearScanState? previous, WearScanState next) {
      void sendGlasses() {
        if (next.isPrinting) {
          WearStatusIconReporter.I.send(
            WearGlassesPayload.printing(
              productName: next.productName,
              statusIcon: next.loadingIcon,
            ),
          );
        } else {
          WearStatusIconReporter.I.send(
            WearGlassesPayload.loading(
              screenType: WearGlassesScreenType.scan,
              title: 'Сканирование',
              statusText: next.loadingText,
              statusIcon: next.loadingIcon,
            ),
          );
        }
      }

      if (previous?.phase != next.phase &&
          next.phase == WearScanPhase.loading) {
        sendGlasses();
        _dismissStatusIfOpen();
      }

      if (previous?.loadingText != next.loadingText && next.isLoading) {
        sendGlasses();
      }

      if (previous?.loadingIcon != next.loadingIcon && next.isLoading) {
        sendGlasses();
      }

      if (previous?.navStatus != next.navStatus && next.navStatus != null) {
        final WearStatusScreenArgs nav = next.navStatus!;
        WearStatusIconReporter.I.send(
          WearGlassesPayload.status(
            isError: nav.kind == WearStatusKind.error,
            title: nav.title,
            subtitle: nav.message,
            statusText: nav.kind == WearStatusKind.error
                ? (nav.glassesStatusText ?? 'Ошибка')
                : 'Успешно',
            statusIcon: nav.glassesStatusIcon ??
                (nav.kind == WearStatusKind.success ? WearImages.good : null),
          ),
        );
        ref.read(_provider.notifier).consumeNavigation();
        _openOrReplaceStatus(nav);
      }
      if (previous?.navSelect != next.navSelect && next.navSelect != null) {
        final WearProductSelectArgs args = next.navSelect!;
        WearStatusIconReporter.I.send(
          WearGlassesPayload(
            screenType: WearGlassesScreenType.productSelect,
            phase: WearGlassesPhase.idle,
            title: 'Дубль ШК',
            subtitle: 'Выберите нужный товар',
            items: args.products.map((BarcodeProductInfo p) => p.name).toList(),
            selectedIndex: 0,
            pageText: args.products.length > 4 ? 'Показаны первые 4' : null,
          ),
        );
        ref.read(_provider.notifier).consumeNavigation();
        _openProductSelect(args);
      }
    });

    return WearVoiceCommandListener(
      onSelect: _onVoiceSelect,
      child: WearScreenScaffold(
        showHomeButton: true,
        child: Stack(
          children: <Widget>[
            Center(
              child: Padding(
                padding: const EdgeInsets.all(4.5),
                child: _ScanWaitingContent(
                  onManualInput: _onVoiceSelect,
                ),
              ),
            ),
            if (state.isLoading)
              Positioned.fill(
                child: _ScanLoadingView(
                  statusText: state.loadingText,
                  icon: state.loadingIcon,
                ),
              ),
          ],
        ),
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

    final bool isPrintSuccess = args.kind == WearStatusKind.success &&
        args.title.toLowerCase().contains('ценник');
    if (isPrintSuccess && mounted) {
      await context.push<bool>(WearContinueScanScreen.route);
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

  Future<void> _openProductSelect(WearProductSelectArgs args) async {
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

class _ScanWaitingContent extends StatelessWidget {
  const _ScanWaitingContent({required this.onManualInput});

  final VoidCallback onManualInput;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const _ScanIconBubble(),
        const SizedBox(height: 12),
        Text(
          'Сканирование товара',
          style: WearTypography.lable18,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 6),
        Text(
          'Наведите камеру\nна штрих-код',
          style: WearTypography.lable.copyWith(
            color: WearColors.textSecondary,
            height: 1.2,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 14),
        const _ScanStatusLine(text: 'Поиск ШК...'),
        const SizedBox(height: 16),
        _PillButton(
          title: 'Ручной ввод',
          icon: WearImages.barcode,
          onTap: onManualInput,
        ),
      ],
    );
  }
}

class _ScanLoadingView extends StatelessWidget {
  const _ScanLoadingView({
    required this.statusText,
    required this.icon,
  });

  final String statusText;
  final String icon;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(color: Color(0xCCFFFFFF)),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(4.5),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _ScanIconBubble(icon: icon),
              const SizedBox(height: 12),
              Text(
                'Сканирование товара',
                style: WearTypography.lable18,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Text(
                'Наведите камеру\nна штрих-код',
                style: WearTypography.lable.copyWith(
                  color: WearColors.textSecondary,
                  height: 1.2,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 14),
              _ScanStatusLine(text: statusText, icon: icon),
              const SizedBox(height: 10),
              const SizedBox(
                width: 112,
                child: ClipRRect(
                  borderRadius: BorderRadius.all(Radius.circular(999)),
                  child: LinearProgressIndicator(
                    minHeight: 3,
                    backgroundColor: Color(0x1A464646),
                    valueColor: AlwaysStoppedAnimation<Color>(
                      WearColors.textDefault,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScanIconBubble extends StatelessWidget {
  const _ScanIconBubble({this.icon = WearImages.barcode});

  final String icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: const BoxDecoration(
        color: WearColors.buttonSecondaryDefault,
        shape: BoxShape.circle,
      ),
      child: Center(
        child: WearSvgIcon(
          icon,
          size: 22,
          color: WearColors.textDefault,
        ),
      ),
    );
  }
}

class _ScanStatusLine extends StatelessWidget {
  const _ScanStatusLine({
    required this.text,
    this.icon = WearImages.scanerIndicator,
  });

  final String text;
  final String icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        WearSvgIcon(
          icon == WearImages.printer
              ? WearImages.printer
              : WearImages.scanerIndicator,
          size: 16,
          color: WearColors.green,
        ),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            text,
            style: WearTypography.lable.copyWith(height: 1.1),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _PillButton extends StatelessWidget {
  const _PillButton({
    required this.title,
    required this.onTap,
    this.icon,
  });

  final String title;
  final VoidCallback onTap;
  final String? icon;

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
          width: 138,
          height: _height,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (icon != null) ...<Widget>[
                    WearSvgIcon(
                      icon!,
                      size: 14,
                      color: WearColors.textDefault,
                    ),
                    const SizedBox(width: 6),
                  ],
                  Flexible(
                    child: Text(
                      title,
                      style: WearTypography.lable.copyWith(fontSize: 15),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
