import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:smart_glasses/features/glasses/presentation/cubit/wear/wear_scan_overlay_cubit.dart';
import 'package:smart_glasses/features/glasses/presentation/widgets/wear/wear_glasses_scaffold.dart';

class WearScanOverlay extends StatelessWidget {
  const WearScanOverlay({required this.visible, super.key});

  final bool visible;

  static const Size _reticleSize = Size(220, 120);

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<WearScanOverlayCubit, WearScanOverlayState>(
      builder: (BuildContext context, WearScanOverlayState state) {
        if (!visible) return const SizedBox.shrink();
        return IgnorePointer(
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final double left = (state.centerX * constraints.maxWidth -
                      _reticleSize.width / 2)
                  .clamp(0, constraints.maxWidth - _reticleSize.width);
              final double top = (state.centerY * constraints.maxHeight -
                      _reticleSize.height / 2)
                  .clamp(0, constraints.maxHeight - _reticleSize.height);
              return Stack(
                children: <Widget>[
                  Positioned(
                    left: 0,
                    top: 0,
                    width: _reticleSize.width,
                    height: _reticleSize.height,
                    child: AnimatedSlide(
                      offset: Offset(
                        left / _reticleSize.width,
                        top / _reticleSize.height,
                      ),
                      duration: const Duration(milliseconds: 70),
                      curve: Curves.linear,
                      child: RepaintBoundary(
                        child: CustomPaint(
                          key: const Key('wear-scan-reticle'),
                          painter: _ReticlePainter(
                            locked: state.phase == WearScanOverlayPhase.locked,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

class _ReticlePainter extends CustomPainter {
  const _ReticlePainter({required this.locked});

  final bool locked;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = WearGlassesScaffold.accentColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = locked ? 7 : 4
      ..strokeCap = StrokeCap.square;
    const double corner = 28;
    final Path path = Path()
      ..moveTo(0, corner)
      ..lineTo(0, 0)
      ..lineTo(corner, 0)
      ..moveTo(size.width - corner, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, corner)
      ..moveTo(size.width, size.height - corner)
      ..lineTo(size.width, size.height)
      ..lineTo(size.width - corner, size.height)
      ..moveTo(corner, size.height)
      ..lineTo(0, size.height)
      ..lineTo(0, size.height - corner);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_ReticlePainter oldDelegate) =>
      oldDelegate.locked != locked;
}
