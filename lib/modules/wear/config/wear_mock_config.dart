import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';

class WearMockConfig {
  WearMockConfig._();

  static const String _keyUseMocks = 'WEAR_USE_MOCKS';
  static SharedPreferences? _prefs;

  static Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  static bool get isEnabled => _envFlag('WEAR_USE_MOCKS');

  static bool _envFlag(String key) {
    if (_prefs != null) {
      final bool? prefsValue = _prefs!.getBool(key);
      if (prefsValue != null) {
        if (kDebugMode) {
          debugPrint('[ENV DEBUG] WearMockConfig.$key from prefs=$prefsValue');
        }
        return prefsValue;
      }
    }

    final String? value = dotenv.env[key];
    if (value == null) {
      if (kDebugMode) {
        debugPrint('[ENV DEBUG] WearMockConfig.$key missing -> false');
      }
      return false;
    }
    final String normalized = value.trim().toLowerCase();
    final bool result = normalized == 'true';
    if (kDebugMode) {
      debugPrint(
        '[ENV DEBUG] WearMockConfig.$key raw="$value" normalized="$normalized" -> $result',
      );
    }
    return result;
  }
}
