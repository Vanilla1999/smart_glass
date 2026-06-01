import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:multi_scanner/multi_scanner.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/main/wear_main_screen.dart';
import 'package:smart_glasses/modules/wear/presentation/widgets/wear_loading.dart';
import 'package:smart_glasses/modules/wear/presentation/widgets/wear_screen_scaffold.dart';
import 'package:smart_glasses/modules/wear/theme/wear_colors.dart';
import 'package:smart_glasses/modules/wear/theme/wear_typography.dart';

class WearScannerConnectScreen extends ConsumerStatefulWidget {
  const WearScannerConnectScreen({super.key});

  static const String route = '/wear_scanner_connect';

  @override
  ConsumerState<WearScannerConnectScreen> createState() =>
      _WearScannerConnectScreenState();
}

class _WearScannerConnectScreenState
    extends ConsumerState<WearScannerConnectScreen> {
  bool _isConnecting = false;
  bool _didRedirect = false;

  @override
  void initState() {
    super.initState();
  }

  Future<void> _connectScanner() async {
    // TODO: remove stub dep
    // ref.read(bluetoothNotifierProvider.notifier).showBluetoothDialog();
  }

  @override
  Widget build(BuildContext context) {
    // final bool alreadyConnected =
    //     ref.watch(connectedBTStateProvider).value != null;

    // if (alreadyConnected && !_didRedirect) {
    //   _didRedirect = true;
    //   WidgetsBinding.instance.addPostFrameCallback((_) {
    //     if (mounted) {
    //       context.go(WearMainScreen.route);
    //     }
    //   });
    // }

    // ref.listen(connectedBTStateProvider, (previous, next) {
    //   final bool isConnected = next.value != null;
    //   if (isConnected && !_didRedirect) {
    //     _didRedirect = true;
    //     context.go(WearMainScreen.route);
    //   }
    // });

    return WearScreenScaffold(
      child: Stack(
        children: <Widget>[
          Center(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Text(
                    'Подключите сканнер!',
                    style: WearTypography.lable,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  _PillButton(
                    title: 'Подключить',
                    onTap: _isConnecting ? null : _connectScanner,
                  ),
                ],
              ),
            ),
          ),
          if (_isConnecting)
            const Positioned.fill(
              child: ColoredBox(
                color: Color(0x66FFFFFF),
                child: Center(
                  child: WearLoading(size: 40),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PillButton extends StatelessWidget {
  const _PillButton({
    required this.title,
    required this.onTap,
  });

  final String title;
  final VoidCallback? onTap;

  static const double _radius = 33.0;
  static const double _height = 34.0;

  @override
  Widget build(BuildContext context) {
    final bool isEnabled = onTap != null;
    final Color color = isEnabled
        ? WearColors.buttonSecondaryDefault
        : WearColors.buttonSecondaryDefault.withOpacity(0.6);

    return Material(
      color: color,
      borderRadius: BorderRadius.circular(_radius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 123,
          height: _height,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Center(
              child: Text(
                title,
                style: WearTypography.lable.copyWith(fontSize: 15),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
