import 'package:flutter/material.dart';
import 'package:smart_glasses/modules/wear/presentation/widgets/wear_svg_icon.dart';
import 'package:smart_glasses/modules/wear/theme/wear_colors.dart';
import 'package:smart_glasses/modules/wear/theme/wear_typography.dart';

class WearPill extends StatelessWidget {
  const WearPill({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.iconSize = 14,
    this.onTap,
    this.onLongPress,
    this.height = 48,
  });

  final String title;
  final String? subtitle;
  final String? icon;
  final double iconSize;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: WearColors.buttonSecondaryDefault,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(999),
        child: SizedBox(
          height: height,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Center(
              child: _buildContent(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent() {
    final Widget textBlock = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        Text(
          title,
          style: WearTypography.lable,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
        ),
        if (subtitle != null && subtitle!.isNotEmpty) ...<Widget>[
          const SizedBox(height: 2),
          Text(
            subtitle!,
            style: WearTypography.bodyxsm,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );

    if (icon == null) {
      return textBlock;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        WearSvgIcon(
          icon!,
          size: iconSize,
          color: WearColors.textDefault,
        ),
        const SizedBox(width: 8),
        Flexible(child: textBlock),
      ],
    );
  }
}
