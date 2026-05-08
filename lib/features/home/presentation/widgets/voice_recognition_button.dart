import 'package:flutter/material.dart';

/// Widget for voice recognition button
class VoiceRecognitionButton extends StatelessWidget {
  const VoiceRecognitionButton({
    required this.isReady,
    required this.isListening,
    required this.onPressed,
    super.key,
  });

  final bool isReady;
  final bool isListening;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton(
      onPressed: isReady ? onPressed : null,
      tooltip: isReady
          ? (isListening ? 'Стоп' : 'Голосовой ввод')
          : 'Модель загружается',
      backgroundColor: isListening ? Colors.red : null,
      child: Icon(isListening ? Icons.stop : Icons.mic),
    );
  }
}
