import 'dart:ui' show lerpDouble;
import 'package:flutter/material.dart';

class WearScalingListView extends StatefulWidget {
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
    this.onFocusChanged,
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
  final ValueChanged<int>? onFocusChanged;

  static double computeTopInset(
    double paddingTop,
    double viewportHeight,
    double edgeFractionTop,
  ) {
    return paddingTop + viewportHeight * edgeFractionTop;
  }

  static int computeFocusedListIndex({
    required double offset,
    required double viewportHeight,
    required double topInset,
    required double itemExtent,
    required int itemCount,
  }) {
    final double viewportCenter = offset + viewportHeight / 2;
    return ((viewportCenter - topInset - itemExtent / 2) / itemExtent)
        .round()
        .clamp(0, itemCount - 1);
  }

  @override
  State<WearScalingListView> createState() => _WearScalingListViewState();
}

class _WearScalingListViewState extends State<WearScalingListView> {
  int _lastFocusIndex = -1;

  @override
  void initState() {
    super.initState();
    if (widget.onFocusChanged != null) {
      widget.controller.addListener(_onScroll);
    }
  }

  @override
  void dispose() {
    if (widget.onFocusChanged != null) {
      widget.controller.removeListener(_onScroll);
    }
    super.dispose();
  }

  void _onScroll() {
    if (!widget.controller.hasClients) return;
    final double viewH = widget.controller.position.viewportDimension;
    final double topInset = WearScalingListView.computeTopInset(
      widget.padding.top,
      viewH,
      widget.edgeFractionTop,
    );
    final int index = WearScalingListView.computeFocusedListIndex(
      offset: widget.controller.offset,
      viewportHeight: viewH,
      topInset: topInset,
      itemExtent: widget.itemExtent,
      itemCount: widget.itemCount,
    );
    if (index == _lastFocusIndex) return;
    _lastFocusIndex = index;
    widget.onFocusChanged!(index);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double viewport = constraints.maxHeight;

        final double edgeTop = viewport * widget.edgeFractionTop;
        final double edgeBottom = viewport * widget.edgeFractionBottom;

        final EdgeInsets effectivePad = EdgeInsets.fromLTRB(
          widget.padding.left,
          widget.padding.top + edgeTop,
          widget.padding.right,
          widget.padding.bottom + edgeBottom,
        );

        final double topInset = effectivePad.top;

        return ListView.builder(
          controller: widget.controller,
          itemCount: widget.itemCount,
          itemExtent: widget.itemExtent,
          padding: effectivePad,
          physics: widget.physics,
          itemBuilder: (BuildContext context, int index) {
            final Widget child = widget.itemBuilder(context, index);

            return AnimatedBuilder(
              animation: widget.controller,
              child: child,
              builder: (BuildContext context, Widget? c) {
                final double offset =
                    widget.controller.hasClients ? widget.controller.offset : 0.0;
                final double viewH = widget.controller.hasClients
                    ? widget.controller.position.viewportDimension
                    : viewport;

                final double itemCenter =
                    topInset + index * widget.itemExtent + widget.itemExtent / 2;
                final double viewportCenter = offset + viewH / 2;
                final double dist = (itemCenter - viewportCenter).abs();

                final double norm = (dist / (viewH / 2)).clamp(0.0, 1.0);

                final double scale = lerpDouble(1.0, widget.minScale, norm) ?? 1.0;
                final double opacity = lerpDouble(1.0, widget.minOpacity, norm) ?? 1.0;

                final double sideInset = lerpDouble(
                        widget.baseSideInset,
                        widget.baseSideInset + widget.extraSideInset,
                        norm) ??
                    widget.baseSideInset;

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
