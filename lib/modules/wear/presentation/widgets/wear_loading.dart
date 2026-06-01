import 'package:flutter/material.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';
import 'package:smart_glasses/modules/wear/theme/wear_colors.dart';

class WearLoading extends StatelessWidget {
  const WearLoading({
    super.key,
    this.size = 42,
  });

  final double size;

  @override
  Widget build(BuildContext context) {
    return LoadingAnimationWidget.discreteCircle(
      color: WearColors.red1,
      secondRingColor: WearColors.red2,
      thirdRingColor: WearColors.red3,
      size: size,
    );
  }
}
