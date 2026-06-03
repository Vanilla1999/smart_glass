import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class WearMockConfig {
  WearMockConfig._();

  static bool get isEnabled => _envFlag('WEAR_USE_MOCKS');

  static bool _envFlag(String key) {
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
