import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/config/wear_dependencies.dart';
import 'package:smart_glasses/modules/wear/config/wear_session.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/main/wear_main_screen.dart';
import 'package:smart_glasses/modules/wear/presentation/widgets/wear_pill.dart';
import 'package:smart_glasses/modules/wear/presentation/widgets/wear_scaling_list_view.dart';
import 'package:smart_glasses/modules/wear/presentation/widgets/wear_screen_scaffold.dart';
import 'package:smart_glasses/modules/wear/theme/wear_images.dart';
import 'package:smart_glasses/modules/wear/theme/wear_typography.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DBSettingsField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final bool obscureText;
  final bool isNumber;

  const DBSettingsField({
    super.key,
    required this.label,
    required this.controller,
    this.obscureText = false,
    this.isNumber = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Colors.black,
            ),
          ),
          const SizedBox(height: 4),
          TextFormField(
            controller: controller,
            obscureText: obscureText,
            keyboardType: isNumber ? TextInputType.number : TextInputType.text,
            style: const TextStyle(color: Colors.black, fontSize: 16),
            decoration: InputDecoration(
              filled: true,
              fillColor: Colors.black.withOpacity(0.1),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
          ),
        ],
      ),
    );
  }
}

class DBSaveButton extends StatelessWidget {
  final VoidCallback onPressed;

  const DBSaveButton({super.key, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        minimumSize: const Size(double.infinity, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: const Text('Сохранить', style: TextStyle(fontSize: 18)),
    );
  }
}

// ===================== ОСНОВНОЙ ЭКРАН =====================
class DBSettingsScreen extends ConsumerStatefulWidget {
  const DBSettingsScreen({super.key});

  static const String route = '/db_settings';

  @override
  ConsumerState<DBSettingsScreen> createState() => _WearSettingsScreenState();
}

class _WearSettingsScreenState extends ConsumerState<DBSettingsScreen> {
  final ScrollController _scroll = ScrollController();

  // Контроллеры для полей ввода
  late final TextEditingController _hostController;
  late final TextEditingController _portController;
  late final TextEditingController _pathController;

  // Ключи для SharedPreferences
  static const String _keyHost = 'DBTO_HOST';
  static const String _keyPort = 'DBTO_PORT';
  static const String _keyPath = 'DBTO_PATH';

  @override
  void initState() {
    super.initState();
    WearDependencies.I.wearFlowController.enterScreen(WearScreenId.dbSettings);
    _initControllers();
    _loadSavedSettings();
  }

  void _initControllers() {
    _hostController = TextEditingController();
    _portController = TextEditingController();
    _pathController = TextEditingController();
  }

  Future<void> _loadSavedSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _hostController.text =
          prefs.getString(_keyHost) ?? dotenv.env['DBTO_HOST'] ?? '';
      _portController.text =
          prefs.getString(_keyPort) ?? dotenv.env['DBTO_PORT'] ?? '';
      _pathController.text =
          prefs.getString(_keyPath) ?? dotenv.env['DBTO_PATH'] ?? '';
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyHost, _hostController.text);
    await prefs.setString(_keyPort, _portController.text);
    await prefs.setString(_keyPath, _pathController.text);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Настройки сохранены')),
      );
    }
  }

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    _pathController.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> items = <Widget>[
      DBSettingsField(label: 'Хост (DBTO_HOST)', controller: _hostController),
      DBSettingsField(
        label: 'Порт (DBTO_PORT)',
        controller: _portController,
        isNumber: true,
      ),
      DBSettingsField(
        label: 'Путь к БД (DBTO_PATH)',
        controller: _pathController,
      ),
      DBSaveButton(onPressed: _saveSettings),
      const SizedBox(height: 20),
    ];

    return WearScreenScaffold(
      showHomeButton: true,
      scrollController: _scroll,
      child: WearScalingListView(
        controller: _scroll,
        itemCount: items.length,
        itemExtent: 90,
        padding: const EdgeInsets.fromLTRB(0, 40, 0, 4.5),
        edgeFractionTop: 0.0,
        edgeFractionBottom: 0.14,
        baseSideInset: 10,
        extraSideInset: 34,
        itemBuilder: (BuildContext context, int i) => items[i],
      ),
    );
  }
}
