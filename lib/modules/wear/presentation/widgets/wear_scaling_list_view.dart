import 'dart:ui' show lerpDouble;
import 'package:flutter/material.dart';

class WearScalingListView extends StatelessWidget {
  const WearScalingListView({
    super.key,
    required this.controller,
    required this.itemCount,
    required this.itemBuilder,
    this.itemExtent = 66,
    this.padding = const EdgeInsets.symmetric(vertical: 4.5),
    this.minScale = 0.70,
    this.minOpacity = 0.28,
    this.baseSideInset = 8,
    this.extraSideInset = 36,
    this.edgeFractionTop = 0.08,
    this.edgeFractionBottom = 0.12,
    this.physics = const ClampingScrollPhysics(),
  });

  final ScrollController controller;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;

  final double itemExtent;
  final EdgeInsets padding;

  final double minScale;
  final double minOpacity;

  final double baseSideInset;
  final double extraSideInset;

  final double edgeFractionTop;
  final double edgeFractionBottom;

  final ScrollPhysics physics;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double viewport = constraints.maxHeight;

        final double edgeTop = viewport * edgeFractionTop;
        final double edgeBottom = viewport * edgeFractionBottom;

        final EdgeInsets effectivePad = EdgeInsets.fromLTRB(
          padding.left,
          padding.top + edgeTop,
          padding.right,
          padding.bottom + edgeBottom,
        );

        final double topInset = effectivePad.top;

        return ListView.builder(
          controller: controller,
          itemCount: itemCount,
          itemExtent: itemExtent,
          padding: effectivePad,
          physics: physics,
          itemBuilder: (BuildContext context, int index) {
            final Widget child = itemBuilder(context, index);

            return AnimatedBuilder(
              animation: controller,
              child: child,
              builder: (BuildContext context, Widget? c) {
                final double offset =
                    controller.hasClients ? controller.offset : 0.0;
                final double viewH = controller.hasClients
                    ? controller.position.viewportDimension
                    : viewport;

                final double itemCenter =
                    topInset + index * itemExtent + itemExtent / 2;
                final double viewportCenter = offset + viewH / 2;
                final double dist = (itemCenter - viewportCenter).abs();

                final double norm = (dist / (viewH / 2)).clamp(0.0, 1.0);

                final double scale = lerpDouble(1.0, minScale, norm) ?? 1.0;
                final double opacity = lerpDouble(1.0, minOpacity, norm) ?? 1.0;

                final double sideInset = lerpDouble(
                        baseSideInset, baseSideInset + extraSideInset, norm) ??
                    baseSideInset;

                return Opacity(
                  opacity: opacity,
                  child: Transform.scale(
                    scale: scale,
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: sideInset),
                      child: c,
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}
