import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:smart_glasses/modules/wear/theme/wear_colors.dart';

class WearPositionIndicator extends StatefulWidget {
  const WearPositionIndicator({
    super.key,
    required this.controller,
    this.autoHide = const Duration(milliseconds: 900),
    this.trackFraction = 0.25,
  });

  final ScrollController controller;
  final Duration autoHide;
  final double trackFraction;

  @override
  State<WearPositionIndicator> createState() => _WearPositionIndicatorState();
}

class _WearPositionIndicatorState extends State<WearPositionIndicator> {
  Timer? _hide;
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(covariant WearPositionIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onScroll);
      widget.controller.addListener(_onScroll);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onScroll);
    _hide?.cancel();
    super.dispose();
  }

  void _onScroll() {
    if (!mounted) return;
    if (!widget.controller.hasClients) return;

    final ScrollPosition pos = widget.controller.position;
    final bool scrollable = pos.maxScrollExtent > 0;
    if (!scrollable) {
      if (_visible) setState(() => _visible = false);
      return;
    }

    if (!_visible) setState(() => _visible = true);

    _hide?.cancel();
    _hide = Timer(widget.autoHide, () {
      if (mounted) setState(() => _visible = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.controller.hasClients) return const SizedBox.shrink();

    return AnimatedOpacity(
      opacity: _visible ? 1 : 0,
      duration: const Duration(milliseconds: 150),
      child: CustomPaint(
        painter: _WearPositionIndicatorPainter(
          controller: widget.controller,
          trackFraction: widget.trackFraction,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _WearPositionIndicatorPainter extends CustomPainter {
  _WearPositionIndicatorPainter({
    required this.controller,
    required this.trackFraction,
  }) : super(repaint: controller);

  final ScrollController controller;
  final double trackFraction;

  @override
  void paint(Canvas canvas, Size size) {
    if (!controller.hasClients) return;
    final ScrollPosition pos = controller.position;
    if (pos.maxScrollExtent <= 0) return;

    final double shortest = math.min(size.width, size.height);
    const double pad = 4.5;
    final double radius = shortest / 2 - pad;

    final double trackHeight =
        (shortest * trackFraction).clamp(18.0, radius * 2);
    final double halfAngle = _halfAngleForHeight(radius, trackHeight);

    final double trackStart = -halfAngle;
    final double trackSweep = halfAngle * 2;

    final Offset center = Offset(size.width / 2, size.height / 2);
    final Rect rect = Rect.fromCircle(center: center, radius: radius);

    final Paint trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..color = WearColors.textSecondary.withOpacity(0.22);

    final Paint thumbPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..color = WearColors.textSecondary.withOpacity(0.72);

    canvas.drawArc(rect, trackStart, trackSweep, false, trackPaint);

    final double viewport = pos.viewportDimension;
    final double content = pos.maxScrollExtent + viewport;
    final double visibleFraction = (viewport / content).clamp(0.0, 1.0);

    final double thumbHeight =
        _clamp(trackHeight * visibleFraction, 10, trackHeight);
    final double thumbHalfAngle = _halfAngleForHeight(radius, thumbHeight);

    final double progress = (pos.pixels / pos.maxScrollExtent).clamp(0.0, 1.0);

    final double minCenter = -halfAngle + thumbHalfAngle;
    final double maxCenter = halfAngle - thumbHalfAngle;
    final double centerAngle = _lerp(minCenter, maxCenter, progress);

    final double thumbStart = centerAngle - thumbHalfAngle;
    final double thumbSweep = thumbHalfAngle * 2;

    canvas.drawArc(rect, thumbStart, thumbSweep, false, thumbPaint);
  }

  double _halfAngleForHeight(double radius, double height) {
    if (radius <= 0) return 0;
    final double v = (height / (2 * radius)).clamp(0.0, 1.0);
    return math.asin(v);
  }

  double _lerp(double a, double b, double t) => a + (b - a) * t;
  double _clamp(double v, double min, double max) =>
      v < min ? min : (v > max ? max : v);

  @override
  bool shouldRepaint(covariant _WearPositionIndicatorPainter oldDelegate) {
    return oldDelegate.controller != controller ||
        oldDelegate.trackFraction != trackFraction;
  }
}
