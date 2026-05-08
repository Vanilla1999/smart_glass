import 'package:flutter/material.dart';
import 'package:smart_glasses/features/initialization/presentation/screens/initialization_screen.dart';

/// Main application widget
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart Wear Test',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: const InitializationScreen(),
    );
  }
}
