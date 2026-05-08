import 'package:flutter/material.dart';

/// Initialization screen for glasses
class GlassesInitializationScreen extends StatelessWidget {
  const GlassesInitializationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Text(
          'Начальная загрузка',
          style: TextStyle(
            color: Color(0xFF00FF00),
            fontSize: 32,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
