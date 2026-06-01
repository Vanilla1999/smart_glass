import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:smart_glasses/app/app.dart';
import 'package:smart_glasses/app/di/app_scope.dart';
import 'package:smart_glasses/app/di/dependencies_container.dart';
import 'package:smart_glasses/app/glasses/glasses_runtime_app.dart';

@pragma('vm:entry-point')
void glassesMain() {
  runApp(const GlassesRuntimeApp());
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await dotenv.load(
    fileName: 'assets/develop.env',
    isOptional: true,
    mergeWith: const <String, String>{
      'WEAR_GLASSES_ENABLED': 'true',
      'WEAR_MOCK_AUTH_ON_LOGO': 'false',
      'WEAR_MOCK_SKIP_AUTH_ON_LOGO': 'false',
      'WEAR_SKIP_SCANNER_CONNECT_SCREEN': 'false',
    },
  );

  // Create dependencies
  final dependencies = await DependenciesContainer.create();

  runApp(
    AppScope(
      dependencies: dependencies,
      child: const MyApp(),
    ),
  );
}
