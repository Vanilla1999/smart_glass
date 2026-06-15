import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:smart_glasses/app/app.dart';
import 'package:smart_glasses/app/di/app_scope.dart';
import 'package:smart_glasses/app/di/dependencies_container.dart';
import 'package:smart_glasses/app/glasses/glasses_runtime_app.dart';
import 'package:smart_glasses/modules/wear/config/wear_mock_config.dart';

@pragma('vm:entry-point')
void glassesMain() {
  runApp(const GlassesRuntimeApp());
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (kDebugMode) {
    await _debugLogDevelopEnvAsset();
  }

  await dotenv.load(
    fileName: 'assets/develop.env',
    isOptional: true,
  );

  await WearMockConfig.init();

  _applyDefaultEnvValues();

  if (kDebugMode) {
    _debugLogLoadedEnv();
  }

  final dependencies = await DependenciesContainer.create();

  runApp(
    AppScope(
      dependencies: dependencies,
      child: const MyApp(),
    ),
  );
}

void _applyDefaultEnvValues() {
  const Map<String, String> defaults = <String, String>{
    'WEAR_GLASSES_ENABLED': 'true',
    'WEAR_USE_MOCKS': 'false',
    'WEAR_MOCK_AUTH_ON_LOGO': 'false',
    'WEAR_MOCK_SKIP_AUTH_ON_LOGO': 'false',
    'WEAR_SKIP_SCANNER_CONNECT_SCREEN': 'false',
  };

  defaults.forEach((String key, String value) {
    final bool alreadyDefined = dotenv.env.containsKey(key);
    dotenv.env.putIfAbsent(key, () => value);
    debugPrint(
      '[ENV DEBUG] default $key=$value ${alreadyDefined ? 'skipped, env has ${dotenv.env[key]}' : 'applied'}',
    );
  });
}

Future<void> _debugLogDevelopEnvAsset() async {
  const String fileName = 'assets/develop.env';
  try {
    final String rawEnv = await rootBundle.loadString(fileName);
    final List<String> lines = rawEnv.split('\n');
    final String? rawWearUseMocks = _findRawEnvLine(lines, 'WEAR_USE_MOCKS');

    debugPrint('[ENV DEBUG] $fileName asset loaded');
    debugPrint('[ENV DEBUG] $fileName length=${rawEnv.length}');
    debugPrint(
      '[ENV DEBUG] $fileName raw WEAR_USE_MOCKS line=${rawWearUseMocks ?? '<missing>'}',
    );
  } catch (error, stackTrace) {
    debugPrint('[ENV DEBUG] failed to read $fileName asset: $error');
    debugPrint('[ENV DEBUG] stackTrace: $stackTrace');
  }
}

String? _findRawEnvLine(List<String> lines, String key) {
  for (final String line in lines) {
    final String trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) {
      continue;
    }
    if (trimmed.startsWith('$key=')) {
      return trimmed;
    }
  }
  return null;
}

void _debugLogLoadedEnv() {
  const List<String> keys = <String>[
    'WEAR_GLASSES_ENABLED',
    'WEAR_USE_MOCKS',
    'WEAR_MOCK_AUTH_ON_LOGO',
    'WEAR_MOCK_SKIP_AUTH_ON_LOGO',
    'WEAR_SKIP_SCANNER_CONNECT_SCREEN',
  ];

  debugPrint('[ENV DEBUG] dotenv.isInitialized=${dotenv.isInitialized}');
  for (final String key in keys) {
    final String? value = dotenv.env[key];
    debugPrint('[ENV DEBUG] dotenv.env[$key]=${value ?? '<missing>'}');
  }
}
