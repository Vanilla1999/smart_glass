import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:smart_glasses/modules/wear/presentation/input/cubit/ear_print_code_input_cubit.dart';
import 'package:smart_glasses/modules/wear/theme/wear_colors.dart';
import 'package:smart_glasses/modules/wear/theme/wear_typography.dart';

class WearVoiceIndicator extends StatefulWidget {
  const WearVoiceIndicator({
    super.key,
    required this.phase,
    required this.level01,
    this.errorText,
    this.compact = false,
  });
  final bool compact;

  final WearVoicePhase phase;
  final ValueListenable<double> level01;
  final String? errorText;

  @override
  State<WearVoiceIndicator> createState() => _WearVoiceIndicatorState();
}

class _WearVoiceIndicatorState extends State<WearVoiceIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  bool get _active =>
      widget.phase == WearVoicePhase.listening ||
      widget.phase == WearVoicePhase.starting ||
      widget.phase == WearVoicePhase.restarting;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    _sync();
  }

  @override
  void didUpdateWidget(covariant WearVoiceIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.phase != widget.phase) _sync();
  }

  void _sync() {
    if (_active) {
      if (!_c.isAnimating) _c.repeat();
    } else {
      _c.stop();
      _c.value = 0;
    }
    setState(() {});
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  String get _status {
    switch (widget.phase) {
      case WearVoicePhase.listening:
        return 'Слушаю…';
      case WearVoicePhase.starting:
        return 'Запуск…';
      case WearVoicePhase.restarting:
        return 'Запуск…';
      case WearVoicePhase.error:
        return widget.errorText?.isNotEmpty == true
            ? widget.errorText!
            : 'Ошибка';
      case WearVoicePhase.idle:
        return 'Пауза';
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isError = widget.phase == WearVoicePhase.error;
    final bool showMic = !_active || isError;

    final double boxW = widget.compact ? 80 : 86;
    final double boxH = widget.compact ? 44 : 56;
    final double gap = widget.compact ? 6 : 8;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        SizedBox(
          width: boxW,
          height: boxH,
          child: ValueListenableBuilder<double>(
            valueListenable: widget.level01,
            builder: (_, double amp, __) {
              final double a = amp.clamp(0.0, 1.0);

              return AnimatedBuilder(
                animation: _c,
                builder: (_, __) {
                  return CustomPaint(
                    painter: _PulsePainter(
                      t: _c.value,
                      amp01: a,
                      active: _active && !isError,
                      color: WearColors.buttonPrimary,
                      idleColor: WearColors.buttonSecondaryDefault,
                    ),
                    child: showMic
                        ? Center(
                            child: Icon(
                              Icons.mic,
                              size: 18,
                              color: isError
                                  ? WearColors.textDefault
                                  : (_active
                                      ? WearColors.white
                                      : WearColors.textDefault),
                            ),
                          )
                        : const SizedBox.shrink(),
                  );
                },
              );
            },
          ),
        ),
        SizedBox(height: gap),
        Text(
          _status,
          style: WearTypography.bodyxsm,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _PulsePainter extends CustomPainter {
  _PulsePainter({
    required this.t,
    required this.amp01,
    required this.active,
    required this.color,
    required this.idleColor,
  });

  final double t;
  final double amp01;
  final bool active;

  final Color color;
  final Color idleColor;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset c = size.center(Offset.zero);
    final double s = size.shortestSide;

    final RRect bg = RRect.fromRectAndRadius(
      Rect.fromCenter(center: c, width: s * 1.45, height: s * 0.72),
      const Radius.circular(999),
    );
    final Paint bgPaint = Paint()..color = idleColor;
    canvas.drawRRect(bg, bgPaint);

    if (!active) return;

    final double ampBoost = 0.35 + 0.65 * math.sqrt(amp01);

    final Paint ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    for (int i = 0; i < 2; i++) {
      final double p = (t + i * 0.5) % 1.0;
      final double r = (s * 0.12) + p * (s * 0.30) * ampBoost;
      final double alpha = (1.0 - p) * 0.35;

      ring
        ..strokeWidth = (2.0 + 1.0 * (1.0 - p)) * ampBoost
        ..color = color.withValues(alpha: alpha);

      canvas.drawCircle(c, r, ring);
    }

    final Rect coreRect =
        Rect.fromCenter(center: c, width: s * 0.52, height: s * 0.52);
    final RRect core = RRect.fromRectAndRadius(
      coreRect,
      const Radius.circular(999),
    );
    canvas.drawRRect(core, Paint()..color = color);

    _paintWaveform(canvas, coreRect, ampBoost);
  }

  void _paintWaveform(Canvas canvas, Rect rect, double ampBoost) {
    if (!active) return;

    final int bars = 5;
    final double waveWidth = rect.width * 0.62;
    final double barWidth = rect.width * 0.08;
    final double gap =
        bars > 1 ? (waveWidth - bars * barWidth) / (bars - 1) : 0;

    final double centerX = rect.center.dx;
    final double centerY = rect.center.dy;
    final double base = rect.height * 0.18;
    final double amp = rect.height * 0.62 * ampBoost;

    final double startX = centerX - waveWidth / 2;
    final Paint barPaint = Paint()
      ..color = WearColors.white.withValues(alpha: 0.92)
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke
      ..strokeWidth = barWidth;

    for (int i = 0; i < bars; i++) {
      final double phase = (t * 2 * math.pi) + i * 0.7;
      final double pulse = (math.sin(phase) + 1) * 0.5;
      final double h = base + amp * (0.35 + 0.65 * pulse);
      final double x = startX + i * (barWidth + gap) + barWidth / 2;
      canvas.drawLine(
        Offset(x, centerY - h / 2),
        Offset(x, centerY + h / 2),
        barPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _PulsePainter oldDelegate) {
    return oldDelegate.t != t ||
        oldDelegate.amp01 != amp01 ||
        oldDelegate.active != active ||
        oldDelegate.color != color ||
        oldDelegate.idleColor != idleColor;
  }
}
