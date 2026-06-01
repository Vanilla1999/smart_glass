import 'package:flutter/material.dart';
import 'package:pole_base_kit/pole_base_kit.dart';
import 'package:smart_glasses/modules/wear/theme/wear_images.dart';

class HomeButtonWear extends StatelessWidget {
  const HomeButtonWear({
    super.key,
    required this.onTap,
  });
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: const PBIcon(
        PBIconData(WearImages.homeButton, immutableColor: true),
      ),
    );
  }
}
