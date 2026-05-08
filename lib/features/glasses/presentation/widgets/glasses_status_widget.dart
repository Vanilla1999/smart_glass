import 'package:flutter/material.dart';

/// Widget for displaying status on glasses
class GlassesStatusWidget extends StatelessWidget {
  const GlassesStatusWidget({
    required this.counter,
    required this.recognizedText,
    super.key,
  });

  final int counter;
  final String recognizedText;

  @override
  Widget build(BuildContext context) {
    final statusColor = counter > 0 ? const Color(0xFF00AA00) : Colors.grey;
    
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          counter > 0 ? 'АКТИВНО' : 'ОЖИДАНИЕ',
          style: TextStyle(
            color: statusColor,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 20),
        Text(
          '$counter',
          style: const TextStyle(
            color: Color(0xFF00FF00),
            fontSize: 80,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 40,
          child: Text(
            recognizedText,
            style: const TextStyle(
              color: Color(0xFF00FF00),
              fontSize: 24,
              fontWeight: FontWeight.normal,
            ),
          ),
        ),
      ],
    );
  }
}
