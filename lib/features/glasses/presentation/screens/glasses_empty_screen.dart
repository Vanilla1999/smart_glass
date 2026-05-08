import 'package:flutter/material.dart';

/// Empty screen for glasses after initialization
class GlassesEmptyScreen extends StatelessWidget {
  const GlassesEmptyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: SizedBox.shrink(),
      ),
    );
  }
}
