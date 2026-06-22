import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_glasses/modules/wear/application/wear_flow_controller.dart';
import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/config/wear_dependencies.dart';
import 'package:smart_glasses/modules/wear/services/wear_printer_status_service.dart';

class WearPrinterSettingsScreen extends StatefulWidget {
  const WearPrinterSettingsScreen({super.key});

  static const String route = '/wear_printer_settings';

  @override
  State<WearPrinterSettingsScreen> createState() =>
      _WearPrinterSettingsScreenState();
}

class _WearPrinterSettingsScreenState extends State<WearPrinterSettingsScreen> {
  final WearPrinterStatusService _statusService =
      const WearPrinterStatusService();
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    WearDependencies.I.wearFlowController.enterScreen(
      WearScreenId.printerSettings,
    );
    WearDependencies.I.wearFlowController.registerScreenActions(
      WearScreenId.printerSettings,
      WearScreenActionHandler(onSelect: _refresh),
    );
    _refresh();
  }

  @override
  void dispose() {
    WearDependencies.I.wearFlowController.unregisterScreenActions(
      WearScreenId.printerSettings,
    );
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_checking) return;
    setState(() => _checking = true);
    final bool available = await _statusService.isSelectedPrinterAvailable();
    if (!mounted) return;
    setState(() => _checking = false);
    if (available && context.canPop()) {
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Center(
        child: SizedBox(
          width: 640,
          height: 480,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(30, 20, 30, 80),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                const _SettingsTitle(
                  subtitle:
                      'Не обнаружены активные принтеры,\nпроверьте их подключение к питанию или сети',
                ),
                const SizedBox(height: 56),
                const _PrinterIcon(size: 40),
                const SizedBox(height: 56),
                _RefreshButton(
                  title: _checking ? 'Проверяем...' : 'Обновить',
                  onTap: _checking ? null : _refresh,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PrinterIcon extends StatelessWidget {
  const _PrinterIcon({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _PrinterPainter()),
    );
  }
}

class _PrinterPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final double unit = size.width / 40;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(3 * unit, 15 * unit, 34 * unit, 15 * unit),
        Radius.circular(2 * unit),
      ),
      paint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(10 * unit, 3 * unit, 20 * unit, 12 * unit),
        Radius.circular(1 * unit),
      ),
      paint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(10 * unit, 23 * unit, 13 * unit, 13 * unit),
        Radius.circular(1 * unit),
      ),
      paint,
    );
    canvas.drawLine(
      Offset(27.5 * unit, 27.5 * unit),
      Offset(35 * unit, 35 * unit),
      paint,
    );
    canvas.drawLine(
      Offset(35 * unit, 27.5 * unit),
      Offset(27.5 * unit, 35 * unit),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _SettingsTitle extends StatelessWidget {
  const _SettingsTitle({required this.subtitle});

  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        const Text(
          'Настройка',
          style: TextStyle(
            color: _WearSettingsStyle.accent,
            fontSize: 40,
            height: 1.4,
            fontWeight: FontWeight.w500,
            fontFamily: 'Inter',
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          subtitle,
          style: const TextStyle(
            color: _WearSettingsStyle.accent,
            fontSize: 20,
            height: 1.4,
            fontWeight: FontWeight.w400,
            fontFamily: 'Inter',
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _RefreshButton extends StatelessWidget {
  const _RefreshButton({required this.title, required this.onTap});

  final String title;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _WearSettingsStyle.buttonFill,
      borderRadius: BorderRadius.circular(4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: _WearSettingsStyle.accent),
          ),
          child: Text(
            title,
            style: const TextStyle(
              color: _WearSettingsStyle.accent,
              fontSize: 16,
              height: 1.5,
              fontWeight: FontWeight.w500,
              fontFamily: 'Inter',
            ),
          ),
        ),
      ),
    );
  }
}

abstract class _WearSettingsStyle {
  static const Color accent = Color(0xFF26BC00);
  static const Color buttonFill = Color(0x0D26BC00);
}
