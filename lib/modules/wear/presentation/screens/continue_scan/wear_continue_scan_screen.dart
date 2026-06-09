import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_glasses/modules/wear/presentation/glasses/wear_glasses_payload.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/menu/wear_menu_screen.dart';
import 'package:smart_glasses/modules/wear/presentation/widgets/wear_screen_scaffold.dart';
import 'package:smart_glasses/modules/wear/presentation/widgets/wear_svg_icon.dart';
import 'package:smart_glasses/modules/wear/services/wear_status_icon_reporter.dart';
import 'package:smart_glasses/modules/wear/theme/wear_colors.dart';
import 'package:smart_glasses/modules/wear/theme/wear_images.dart';
import 'package:smart_glasses/modules/wear/theme/wear_typography.dart';

class WearContinueScanScreen extends StatefulWidget {
  const WearContinueScanScreen({super.key});

  static const String route = '/wear_continue_scan';

  @override
  State<WearContinueScanScreen> createState() => _WearContinueScanScreenState();
}

class _WearContinueScanScreenState extends State<WearContinueScanScreen> {
  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      WearStatusIconReporter.I.send(WearGlassesPayload.continueScan());
    });
  }

  @override
  Widget build(BuildContext context) {
    return WearScreenScaffold(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(4.5),
          child: Column(
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
                'Готовы продолжить?',
                style: WearTypography.lable.copyWith(
                  color: WearColors.textSecondary,
                  height: 1.2,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 22),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  _ContinueButton(
                    title: 'Продолжить',
                    onTap: () {
                      WearStatusIconReporter.I.send(
                        WearGlassesPayload.scanWaiting(),
                      );
                      context.pop(true);
                    },
                  ),
                  const SizedBox(width: 12),
                  _ContinueButton(
                    title: 'Завершить',
                    onTap: () => context.go(WearMenuScreen.route),
                    isSecondary: true,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScanIconBubble extends StatelessWidget {
  const _ScanIconBubble();

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
          WearImages.barcode,
          size: 22,
          color: WearColors.textDefault,
        ),
      ),
    );
  }
}

class _ContinueButton extends StatelessWidget {
  const _ContinueButton({
    required this.title,
    required this.onTap,
    this.isSecondary = false,
  });

  final String title;
  final VoidCallback onTap;
  final bool isSecondary;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isSecondary ? WearColors.buttonSecondaryDefault : WearColors.red1,
      borderRadius: BorderRadius.circular(33),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 138,
          height: 34,
          child: Center(
            child: Text(
              title,
              style: WearTypography.lable.copyWith(
                fontSize: 15,
                color: isSecondary ? WearColors.textDefault : WearColors.white,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ),
    );
  }
}
