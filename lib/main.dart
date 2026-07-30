import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:smart_glasses/app/app.dart';
import 'package:smart_glasses/app/di/app_scope.dart';
import 'package:smart_glasses/app/di/dependencies_container.dart';
import 'package:smart_glasses/app/glasses/glasses_runtime_app.dart';
import 'package:smart_glasses/modules/wear/config/wear_mock_config.dart';

const String _gitSha =
    String.fromEnvironment('GIT_SHA', defaultValue: 'unknown');
const String _buildTimestamp =
    String.fromEnvironment('BUILD_TIMESTAMP', defaultValue: 'unknown');
const String _gitDirty =
    String.fromEnvironment('GIT_DIRTY', defaultValue: 'unknown');
const String _sourcePatchSha =
    String.fromEnvironment('SOURCE_PATCH_SHA', defaultValue: 'unknown');
const String _freeTextPipelineModeOverride = String.fromEnvironment(
  'WEAR_FREE_TEXT_PIPELINE_MODE',
  defaultValue: '',
);

@pragma('vm:entry-point')
void glassesMain() {
  _runGuarded(
    entryPointName: 'glassesMain',
    body: () async {
      WidgetsFlutterBinding.ensureInitialized();
      _logBuildFingerprint('glassesMain');
      runApp(const GlassesRuntimeApp());
    },
  );
}

void main() {
  _runGuarded(
    entryPointName: 'main',
    body: _main,
  );
}

Future<void> _main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _logBuildFingerprint('main');

  if (kDebugMode) {
    await _debugLogDevelopEnvAsset();
  }

  await dotenv.load(
    fileName: 'assets/develop.env',
    isOptional: true,
  );

  await WearMockConfig.init();

  _applyDefaultEnvValues();
  _applyBuildEnvOverrides();

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

void _logBuildFingerprint(String entryPoint) {
  final String mode = kReleaseMode
      ? 'release'
      : kProfileMode
          ? 'profile'
          : 'debug';
  print(
    '[VoiceBuild] entry=$entryPoint gitSha=$_gitSha '
    'buildTimestamp=$_buildTimestamp gitDirty=$_gitDirty '
    'sourcePatchSha=$_sourcePatchSha mode=$mode '
    'freeTextPipelineModeOverride=${_freeTextPipelineModeOverride.isEmpty ? 'none' : _freeTextPipelineModeOverride} '
    'platform=${defaultTargetPlatform.name}',
  );
}

void _runGuarded({
  required String entryPointName,
  required Future<void> Function() body,
}) {
  runZonedGuarded<void>(
    () async {
      FlutterError.onError = (FlutterErrorDetails details) {
        FlutterError.presentError(details);
        _logUnhandledError(
          '$entryPointName FlutterError',
          details.exception,
          details.stack,
        );
      };

      PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
        _logUnhandledError('$entryPointName PlatformDispatcher', error, stack);
        return true;
      };

      await body();
    },
    (Object error, StackTrace stack) {
      _logUnhandledError('$entryPointName runZonedGuarded', error, stack);
    },
  );
}

void _logUnhandledError(String source, Object error, StackTrace? stackTrace) {
  print('[APP-ERROR][$source] $error');
  if (stackTrace != null) {
    print('[APP-ERROR][$source] stackTrace=$stackTrace');
  }
}

void _applyDefaultEnvValues() {
  const Map<String, String> defaults = <String, String>{
    'WEAR_GLASSES_ENABLED': 'true',
    'WEAR_USE_MOCKS': 'false',
    'WEAR_MOCK_AUTH_ON_LOGO': 'false',
    'WEAR_MOCK_SKIP_AUTH_ON_LOGO': 'false',
    'WEAR_SKIP_SCANNER_CONNECT_SCREEN': 'false',
    'WEAR_FREE_TEXT_PIPELINE_MODE': 'replayOnly',
  };

  defaults.forEach((String key, String value) {
    final bool alreadyDefined = dotenv.env.containsKey(key);
    dotenv.env.putIfAbsent(key, () => value);
    debugPrint(
      '[ENV DEBUG] default $key=$value ${alreadyDefined ? 'skipped, env has ${dotenv.env[key]}' : 'applied'}',
    );
  });
}

void _applyBuildEnvOverrides() {
  if (_freeTextPipelineModeOverride.isEmpty) return;
  dotenv.env['WEAR_FREE_TEXT_PIPELINE_MODE'] = _freeTextPipelineModeOverride;
  debugPrint(
    '[ENV] build override WEAR_FREE_TEXT_PIPELINE_MODE='
    '$_freeTextPipelineModeOverride',
  );
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
