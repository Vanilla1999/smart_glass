import 'package:flutter/material.dart';

class WearGlassesScaffold extends StatelessWidget {
  const WearGlassesScaffold({
    super.key,
    required this.child,
  });

  final Widget child;

  static const double designWidth = 640;
  static const double designHeight = 480;
  static const Color designBackgroundColor = Color(0xFF2A2828);
  static const Color backgroundColor = designBackgroundColor;
  static const Color accentColor = Color(0xFF26BC00);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      body: Center(
        child: SizedBox(
          width: designWidth,
          height: designHeight,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(30, 20, 30, 80),
            child: child,
          ),
        ),
      ),
    );
  }
}
