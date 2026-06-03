import 'dart:async';

import 'package:flutter/material.dart';
import 'package:smart_glasses/modules/wear/config/wear_session.dart';
import 'package:smart_glasses/modules/wear/presentation/widgets/wear_svg_icon.dart';
import 'package:smart_glasses/modules/wear/services/wear_printer_status_service.dart';
import 'package:smart_glasses/modules/wear/services/wear_wifi_status_service.dart';
import 'package:smart_glasses/modules/wear/theme/wear_colors.dart';
import 'package:smart_glasses/modules/wear/theme/wear_images.dart';

class WearStatusBar extends StatefulWidget {
  const WearStatusBar({
    super.key,
    this.refreshInterval = const Duration(seconds: 10),
    this.wifiStatusService = const WearWifiStatusService(),
    this.printerStatusService = const WearPrinterStatusService(),
  });

  final Duration refreshInterval;
  final WearWifiStatusService wifiStatusService;
  final WearPrinterStatusService printerStatusService;

  static const Color _online = WearColors.green;
  // Очки нормально воспринимают только один цвет, поэтому offline-состояние
  // показываем не цветом, а перечёркиванием иконки.
  static const Color _offline = WearColors.green;

  @override
  State<WearStatusBar> createState() => _WearStatusBarState();
}

class _WearStatusBarState extends State<WearStatusBar> {
  WearWifiStatus _wifi = const WearWifiStatus(isAvailable: false, level: 0);
  bool _printerAvailable = false;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _startRefreshTimer();
  }

  @override
  void didUpdateWidget(covariant WearStatusBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshInterval != widget.refreshInterval) {
      _startRefreshTimer();
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _startRefreshTimer() {
    _refreshTimer?.cancel();
    _refresh();
    _refreshTimer = Timer.periodic(widget.refreshInterval, (_) => _refresh());
  }

  Future<void> _refresh() async {
    final WearWifiStatus wifi = await widget.wifiStatusService.getStatus();
    final bool printerAvailable = WearSession.hasPrinterSelection &&
        await widget.printerStatusService.isSelectedPrinterAvailable();
    if (!mounted) return;
    setState(() {
      _wifi = wifi;
      _printerAvailable = printerAvailable;
    });
  }

  @override
  Widget build(BuildContext context) {
    final bool showPrinter = WearSession.hasPrinterSelection;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _WifiStatusIcon(
          available: _wifi.isAvailable,
          level: _wifi.level,
        ),
        if (showPrinter) ...<Widget>[
          const SizedBox(width: 12),
          _CrossableIcon(
            available: _printerAvailable,
            child: WearSvgIcon(
              WearImages.printer,
              size: 20,
              color: _printerAvailable
                  ? WearStatusBar._online
                  : WearStatusBar._offline,
            ),
          ),
        ],
      ],
    );
  }
}

class _WifiStatusIcon extends StatelessWidget {
  const _WifiStatusIcon({
    required this.available,
    required this.level,
  });

  final bool available;
  final int level;

  @override
  Widget build(BuildContext context) {
    return _CrossableIcon(
      available: available,
      child: SizedBox(
        width: 20,
        height: 20,
        child: CustomPaint(
          painter: _WifiPainter(
            color: WearStatusBar._online,
            // Если Wi-Fi недоступен, рисуем полноценную иконку и перечёркиваем
            // её. На очках цвет не помогает, поэтому состояние должно быть
            // видно именно формой.
            level: available ? level.clamp(1, 3) : 3,
          ),
        ),
      ),
    );
  }
}

class _CrossableIcon extends StatelessWidget {
  const _CrossableIcon({
    required this.available,
    required this.child,
  });

  final bool available;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 20,
      height: 20,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          child,
          if (!available)
            Transform.rotate(
              angle: -0.75,
              child: Container(
                width: 24,
                height: 2.2,
                decoration: BoxDecoration(
                  color: WearStatusBar._offline,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _WifiPainter extends CustomPainter {
  const _WifiPainter({
    required this.color,
    required this.level,
  });

  final Color color;
  final int level;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final Offset center = Offset(size.width / 2, size.height * 0.82);

    if (level >= 3) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: 12),
        -2.38,
        1.62,
        false,
        paint,
      );
    }
    if (level >= 2) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: 8),
        -2.28,
        1.42,
        false,
        paint,
      );
    }
    if (level >= 1) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: 4),
        -2.08,
        1.02,
        false,
        paint,
      );
    }

    canvas.drawCircle(center, 1.7, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_WifiPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.level != level;
  }
}
