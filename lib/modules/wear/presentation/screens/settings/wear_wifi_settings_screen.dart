import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_glasses/modules/wear/application/wear_flow_controller.dart';
import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/config/wear_dependencies.dart';
import 'package:smart_glasses/modules/wear/services/wear_wifi_status_service.dart';

class WearWifiSettingsScreen extends StatefulWidget {
  const WearWifiSettingsScreen({super.key});

  static const String route = '/wear_wifi_settings';

  @override
  State<WearWifiSettingsScreen> createState() => _WearWifiSettingsScreenState();
}

class _WearWifiSettingsScreenState extends State<WearWifiSettingsScreen> {
  final WearWifiStatusService _statusService = const WearWifiStatusService();
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    WearDependencies.I.wearFlowController
        .enterScreen(WearScreenId.wifiSettings);
    WearDependencies.I.wearFlowController.registerScreenActions(
      WearScreenId.wifiSettings,
      WearScreenActionHandler(onSelect: _refresh),
    );
    _refresh();
  }

  @override
  void dispose() {
    WearDependencies.I.wearFlowController.unregisterScreenActions(
      WearScreenId.wifiSettings,
    );
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_checking) return;
    setState(() => _checking = true);
    final WearWifiStatus status = await _statusService.getStatus();
    if (!mounted) return;
    setState(() => _checking = false);
    if (status.isAvailable && context.canPop()) {
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
                      'Нет подключения к сети\nВключите Wi-Fi на телефоне',
                ),
                const SizedBox(height: 56),
                const _WifiIcon(size: 40),
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

class _WifiIcon extends StatelessWidget {
  const _WifiIcon({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _WifiPainter()),
    );
  }
}

class _WifiPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    final Offset center = Offset(size.width / 2, size.height * 0.82);

    canvas.drawArc(Rect.fromCircle(center: center, radius: size.width * 0.6),
        -2.38, 1.62, false, paint);
    canvas.drawArc(Rect.fromCircle(center: center, radius: size.width * 0.4),
        -2.28, 1.42, false, paint);
    canvas.drawArc(Rect.fromCircle(center: center, radius: size.width * 0.2),
        -2.08, 1.02, false, paint);
    canvas.drawCircle(center, 2, Paint()..color = Colors.black);
    canvas.drawLine(
      Offset(size.width * 0.08, size.height * 0.08),
      Offset(size.width * 0.92, size.height * 0.92),
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
