import 'package:flutter/material.dart';
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

  // Create dependencies
  final dependencies = await DependenciesContainer.create();

  runApp(
    AppScope(
      dependencies: dependencies,
      child: const MyApp(),
    ),
  );
}
