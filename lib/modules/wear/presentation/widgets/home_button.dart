import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
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
      child: SvgPicture.asset(WearImages.homeButton),
    );
  }
}
