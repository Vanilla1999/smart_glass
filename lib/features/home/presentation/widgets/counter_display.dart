import 'package:flutter/material.dart';

/// Widget for displaying counter
class CounterDisplay extends StatelessWidget {
  const CounterDisplay({
    required this.counter,
    super.key,
  });

  final int counter;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Text('Счетчик:'),
        Text(
          '$counter',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
      ],
    );
  }
}
