import 'package:flutter/material.dart';

/// Widget for control buttons (glasses, logs, counter)
class ControlButtons extends StatelessWidget {
  const ControlButtons({
    required this.onSaveLogs,
    required this.onClearLogs,
    required this.onIncrementCounter,
    required this.onPrintTags,
    required this.onPrintTagsReal,
    required this.onPrintTagsTest,
    super.key,
  });

  final VoidCallback onSaveLogs;
  final VoidCallback onClearLogs;
  final VoidCallback onIncrementCounter;
  final VoidCallback onPrintTags;
  final VoidCallback onPrintTagsReal;
  final VoidCallback onPrintTagsTest;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ElevatedButton(
          onPressed: onSaveLogs,
          child: const Text('Сохранить все логи ADB'),
        ),
        const SizedBox(height: 10),
        ElevatedButton(
          onPressed: onClearLogs,
          child: const Text('Очистить логи'),
        ),
        const SizedBox(height: 40),
        ElevatedButton(
          onPressed: onPrintTags,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green,
            foregroundColor: Colors.white,
          ),
          child: const Text('Печать ценников (МОК)'),
        ),
        const SizedBox(height: 10),
        ElevatedButton(
          onPressed: onPrintTagsReal,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red,
            foregroundColor: Colors.white,
          ),
          child: const Text('Печать ценников (РЕАЛ)'),
        ),
        const SizedBox(height: 10),
        ElevatedButton(
          onPressed: onPrintTagsTest,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.orange,
            foregroundColor: Colors.white,
          ),
          child: const Text('Печать ценников (ТЕСТ)'),
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
