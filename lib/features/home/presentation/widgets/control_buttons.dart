import 'package:flutter/material.dart';

/// Widget for control buttons (glasses, logs, counter)
class ControlButtons extends StatelessWidget {
  const ControlButtons({
    required this.onShowGlasses,
    required this.onShowGlassesScreen2,
    required this.onSaveLogs,
    required this.onClearLogs,
    required this.onIncrementCounter,
    super.key,
  });

  final VoidCallback onShowGlasses;
  final VoidCallback onShowGlassesScreen2;
  final VoidCallback onSaveLogs;
  final VoidCallback onClearLogs;
  final VoidCallback onIncrementCounter;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ElevatedButton(
          onPressed: onShowGlasses,
          child: const Text('Показать прогрессбар'),
        ),
        const SizedBox(height: 10),
        ElevatedButton(
          onPressed: onShowGlassesScreen2,
          child: const Text('Показать экран 2'),
        ),
        const SizedBox(height: 40),
        ElevatedButton(
          onPressed: onSaveLogs,
          child: const Text('Сохранить все логи ADB'),
        ),
        const SizedBox(height: 10),
        ElevatedButton(
          onPressed: onClearLogs,
          child: const Text('Очистить логи'),
        ),
        const SizedBox(height: 10),
        ElevatedButton(
          onPressed: onIncrementCounter,
          child: const Text('+'),
        ),
      ],
    );
  }
}
