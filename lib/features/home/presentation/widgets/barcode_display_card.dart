import 'package:flutter/material.dart';

/// Widget for displaying barcode scan result
class BarcodeDisplayCard extends StatelessWidget {
  const BarcodeDisplayCard({
    required this.barcode,
    super.key,
  });

  final String barcode;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.green),
      ),
      child: Column(
        children: [
          const Text(
            'Последний штрихкод:',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            barcode.isEmpty ? '—' : barcode,
            style: const TextStyle(fontSize: 18),
          ),
        ],
      ),
    );
  }
}
