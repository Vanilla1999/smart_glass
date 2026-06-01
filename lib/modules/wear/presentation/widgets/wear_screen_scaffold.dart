import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/menu/wear_menu_screen.dart';
import 'package:smart_glasses/modules/wear/presentation/widgets/home_button.dart';
import 'package:smart_glasses/modules/wear/presentation/widgets/wear_scanner_status_indicator.dart';
import 'package:smart_glasses/modules/wear/presentation/widgets/wear_position_indicator.dart';
import 'package:smart_glasses/modules/wear/theme/wear_colors.dart';

class WearScreenScaffold extends ConsumerWidget {
  const WearScreenScaffold({
    super.key,
    required this.child,
    this.showHomeButton = false,
    this.onHomeTap,
    this.scrollController,
  });

  final Widget child;
  final bool showHomeButton;
  final VoidCallback? onHomeTap;

  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: WearColors.white,
      body: Stack(
        children: <Widget>[
          child,
          if (scrollController != null)
            IgnorePointer(
              child: WearPositionIndicator(controller: scrollController!),
            ),
          Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.all(4.5),
              child: IgnorePointer(
                child: Transform.translate(
                  offset: const Offset(-60, 20),
                  child: const WearScannerStatusIndicator(),
                ),
              ),
            ),
          ),
          if (showHomeButton)
            Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.all(4.5),
                child: HomeButtonWear(
                  onTap: onHomeTap ?? () => context.go(WearMenuScreen.route),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
