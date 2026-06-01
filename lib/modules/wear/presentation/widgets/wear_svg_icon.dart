import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class WearSvgIcon extends StatelessWidget {
  const WearSvgIcon(
    this.asset, {
    super.key,
    required this.size,
    required this.color,
  });

  final String asset;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      asset,
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
    );
  }
}
