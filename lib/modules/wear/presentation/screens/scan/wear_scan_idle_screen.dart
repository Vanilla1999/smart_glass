import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_glasses/modules/wear/application/wear_flow_controller.dart';
import 'package:smart_glasses/modules/wear/application/wear_scan_runtime.dart';
import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/config/wear_dependencies.dart';
import 'package:smart_glasses/modules/wear/infrastructure/screen_lifecycle_logging.dart';
import 'package:smart_glasses/modules/wear/models/wear_printer_selection.dart';
import 'package:smart_glasses/modules/wear/presentation/input/wear_print_code_input_screen.dart';
import 'package:smart_glasses/modules/wear/presentation/widgets/wear_screen_scaffold.dart';
import 'package:smart_glasses/modules/wear/presentation/widgets/wear_svg_icon.dart';
import 'package:smart_glasses/modules/wear/theme/wear_colors.dart';
import 'package:smart_glasses/modules/wear/theme/wear_images.dart';
import 'package:smart_glasses/modules/wear/theme/wear_typography.dart';

class WearScanIdleScreen extends StatefulWidget {
  const WearScanIdleScreen({
    super.key,
    required this.printers,
  });

  static const String route = '/wear_scan_idle';

  final WearPrinterSelection? printers;

  @override
  State<WearScanIdleScreen> createState() => _WearScanIdleScreenState();
}

class _WearScanIdleScreenState extends State<WearScanIdleScreen>
    with ScreenLifecycleLogging<WearScanIdleScreen> {
  late final StreamSubscription<WearScanRuntimeState> _stateSubscription;
  late WearScanRuntimeState _state;
  bool _isManualInputOpen = false;

  @override
  void initState() {
    super.initState();
    _state = WearDependencies.I.wearScanRuntime.state;
    _stateSubscription =
        WearDependencies.I.wearScanRuntime.stateStream.listen((next) {
      if (mounted) setState(() => _state = next);
    });
  }

  @override
  void dispose() {
    unawaited(_stateSubscription.cancel());
    super.dispose();
  }

  Future<void> _onVoiceSelect() async {
    final int t0 = DateTime.now().millisecondsSinceEpoch;
    final bool isCurrent = ModalRoute.of(context)?.isCurrent ?? true;
    print(
      '[ScanIdle] _onVoiceSelect called at $t0 '
      'mounted=$mounted isCurrent=$isCurrent '
      '_isManualInputOpen=$_isManualInputOpen',
    );
    if (_isManualInputOpen) {
      print('[ScanIdle] _onVoiceSelect ignored: manual input already open');
      return;
    }
    if (!isCurrent) {
      print('[ScanIdle] _onVoiceSelect ignored: route is not current');
      return;
    }
    _isManualInputOpen = true;
    final String? code = await context.push<String>(
      WearPrintCodeInputScreen.route,
    );
    if (mounted) {
      _isManualInputOpen = false;
    }
    print(
      '[ScanIdle] manual input returned at '
      '${DateTime.now().millisecondsSinceEpoch}: code=$code mounted=$mounted',
    );
    if (code == null || code.trim().isEmpty) {
      return;
    }
    await WearDependencies.I.wearFlowController.handleBarcode(code.trim());
  }

  @override
  Widget build(BuildContext context) {
    return WearScreenScaffold(
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
          if (_state.busy)
            Positioned.fill(
              child: _ScanLoadingView(
                statusText: _state.loadingText,
                icon: _state.loadingIcon,
              ),
            ),
        ],
      ),
    );
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
