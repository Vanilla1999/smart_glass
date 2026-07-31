import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';

class WearMockConfig {
  WearMockConfig._();

  static const String _keyUseMocks = 'WEAR_USE_MOCKS';
  static SharedPreferences? _prefs;

  static Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  static bool get isEnabled => _envFlag(_keyUseMocks);

  static bool _envFlag(String key) {
    if (_prefs != null) {
      final bool? prefsValue = _prefs!.getBool(key);
      if (prefsValue != null) {
        return prefsValue;
      }
    }

    final String? value = dotenv.env[key];
    if (value == null) {
      return false;
    }
    final String normalized = value.trim().toLowerCase();
    return normalized == 'true';
  }
}
