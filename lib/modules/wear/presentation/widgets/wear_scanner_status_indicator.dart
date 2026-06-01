import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:multi_scanner/src/bluetooth/bt_device.dart';
import 'package:smart_glasses/modules/wear/theme/wear_colors.dart';

class WearScannerStatusIndicator extends ConsumerWidget {
  const WearScannerStatusIndicator({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // TODO: remove stub dep
    // final AsyncValue<BTDevice?> ringConnected =
    //     ref.watch(connectedBTStateProvider);
    //
    // final bool isRingOnline = ringConnected.value != null;
    // final Color color =
    //     isRingOnline ? WearColors.green : WearColors.buttonPrimary;

    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        color: WearColors.buttonPrimary,
        shape: BoxShape.circle,
      ),
    );
  }
}
