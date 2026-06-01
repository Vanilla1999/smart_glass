import 'package:flutter/material.dart';
import 'package:smart_glasses/modules/wear/theme/wear_colors.dart';

typedef WearKeyBuilder = Widget Function(BuildContext context, bool pressed);

class WearKeyButton extends StatefulWidget {
  const WearKeyButton({
    super.key,
    required this.onTap,
    required this.builder,
    this.width = 40,
    this.height = 28,
    this.padding = const EdgeInsets.all(4),
    this.backgroundColor,
    this.pressedBackgroundColor,
  });

  final VoidCallback? onTap;
  final WearKeyBuilder builder;

  final double width;
  final double height;
  final EdgeInsets padding;
  final Color? backgroundColor;
  final Color? pressedBackgroundColor;

  @override
  State<WearKeyButton> createState() => _WearKeyButtonState();
}

class _WearKeyButtonState extends State<WearKeyButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final bool enabled = widget.onTap != null;

    final Color bg = _pressed
        ? (widget.pressedBackgroundColor ?? WearColors.buttonSecondaryPressed)
        : (widget.backgroundColor ?? WearColors.buttonSecondaryDefault);

    return Opacity(
      opacity: enabled ? 1.0 : 0.35,
      child: Material(
        color: bg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
        ),
        child: InkWell(
          customBorder: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
          ),
          onTap: widget.onTap,
          onHighlightChanged: (bool v) {
            if (!enabled) return;
            if (_pressed == v) return;
            setState(() => _pressed = v);
          },
          child: SizedBox(
            width: widget.width,
            height: widget.height,
            child: Padding(
              padding: widget.padding,
              child: Center(
                child: widget.builder(context, _pressed),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
