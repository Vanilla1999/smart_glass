import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_glasses/modules/wear/config/wear_dependencies.dart';
import 'package:smart_glasses/modules/wear/presentation/glasses/wear_glasses_payload.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/main/cubit/wear_auth_cubit.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/settings/db_settings_screen.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/status/wear_status_args.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/status/wear_status_screen.dart';
import 'package:smart_glasses/modules/wear/presentation/widgets/wear_loading.dart';
import 'package:smart_glasses/modules/wear/presentation/widgets/wear_scanner_status_indicator.dart';
import 'package:smart_glasses/modules/wear/presentation/widgets/wear_status_bar.dart';
import 'package:smart_glasses/modules/wear/presentation/widgets/wear_svg_icon.dart';
import 'package:smart_glasses/modules/wear/services/wear_status_icon_reporter.dart';
import 'package:smart_glasses/modules/wear/theme/wear_colors.dart';
import 'package:smart_glasses/modules/wear/theme/wear_images.dart';
import 'package:smart_glasses/modules/wear/theme/wear_typography.dart';
import 'package:flutter_svg/flutter_svg.dart';

class WearMainScreen extends ConsumerStatefulWidget {
  const WearMainScreen({super.key});

  static const String route = '/wear_main_screen';

  @override
  ConsumerState<WearMainScreen> createState() => _WearMainScreenState();
}

class _WearMainScreenState extends ConsumerState<WearMainScreen> {
  @override
  void initState() {
    super.initState();
    WearDependencies.I.warmupVoiceTypingInBackground();
    WearStatusIconReporter.I.start();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WearStatusIconReporter.I.show(WearGlassesPayload.authWaitingBarcode());
    });
  }

  @override
  void dispose() {
    // Do not hide glasses projection here: this screen can be disposed during
    // a normal transition to the next wear screen (for example after auth).
    // Hide the projection only from explicit wear-flow exit actions.
    super.dispose();
  }

  bool _isStatusRouteOpen = false;
  int _statusRouteSession = 0;

  @override
  Widget build(BuildContext context) {
    ref.listen<WearAuthState>(wearAuthNotifierProvider,
        (WearAuthState? previous, WearAuthState next) {
      if (previous?.phase != next.phase &&
          next.phase == WearAuthPhase.loading) {
        WearStatusIconReporter.I.send(WearGlassesPayload.authLoading());
        _dismissStatusIfOpen();
      }
      if (previous?.nav != next.nav && next.nav != null) {
        final WearStatusScreenArgs nav = next.nav!;
        WearStatusIconReporter.I.send(
          WearGlassesPayload.status(
            isError: nav.kind == WearStatusKind.error,
            title: nav.title,
            subtitle: nav.message,
            statusText: nav.kind == WearStatusKind.error ? 'Ошибка' : 'Успешно',
          ),
        );
        ref.read(wearAuthNotifierProvider.notifier).consumeNavigation();
        _openOrReplaceStatus(nav);
      }
    });

    final WearAuthState state = ref.watch(wearAuthNotifierProvider);
    // TODO: remove stub dep
    // final bool isScannerConnected =
    //     ref.watch(connectedBTStateProvider).value != null;

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: Stack(
          children: <Widget>[
            Center(
              child: Padding(
                padding: const EdgeInsets.all(4.5),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    // if (!isScannerConnected) ...<Widget>[
                    //   InkWell(
                    //     borderRadius: BorderRadius.circular(999),
                    //     onTap: () => context.go(WearScannerConnectScreen.route),
                    //     child: Container(
                    //       width: 32,
                    //       height: 32,
                    //       decoration: const BoxDecoration(
                    //         color: WearColors.buttonSecondaryDefault,
                    //         shape: BoxShape.circle,
                    //       ),
                    //       child: const Center(
                    //         child: WearSvgIcon(
                    //           WearImages.gear,
                    //           size: 18,
                    //           color: WearColors.textDefault,
                    //         ),
                    //       ),
                    //     ),
                    //   ),
                    //   const SizedBox(height: 8),
                    // ],
                    InkWell(
                      borderRadius: BorderRadius.circular(999),
                      onTap: () => context.go(DBSettingsScreen.route),
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: const BoxDecoration(
                          color: WearColors.buttonSecondaryDefault,
                          shape: BoxShape.circle,
                        ),
                        child: const Center(
                          child: WearSvgIcon(
                            WearImages.database,
                            size: 18,
                            color: WearColors.textDefault,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Для входа используйте\nштрихкод вашего бейджа',
                      style: WearTypography.lable,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 28),
                    GestureDetector(
                      onTap: () => ref
                          .read(wearAuthNotifierProvider.notifier)
                          .handleLogoTap(),
                      onLongPress: () => ref
                          .read(wearAuthNotifierProvider.notifier)
                          .handleLogoLongPress(),
                      child: SvgPicture.asset(WearImages.logo),
                    ),
                  ],
                ),
              ),
            ),
            if (state.isLoading)
              const Positioned.fill(
                child: ColoredBox(
                  color: Color(0x66FFFFFF),
                  child: Center(
                    child: WearLoading(size: 44),
                  ),
                ),
              ),
            Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.all(4.5),
                child: IgnorePointer(
                  child: Transform.translate(
                    offset: const Offset(-60, 20),
                    child: const WearScannerStatusIndicator(),
                  ),
                ),
              ),
            ),
            Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.all(4.5),
                child: IgnorePointer(
                  child: Transform.translate(
                    offset: const Offset(78, 20),
                    child: const WearStatusBar(),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openOrReplaceStatus(WearStatusScreenArgs args) async {
    final int session = ++_statusRouteSession;
    final bool isCurrent = ModalRoute.of(context)?.isCurrent ?? true;

    if (_isStatusRouteOpen && !isCurrent) {
      if (mounted && Navigator.of(context).canPop()) {
        context.pop();
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }

    if (!mounted) return;

    _isStatusRouteOpen = true;
    await context.push(WearStatusScreen.route, extra: args);

    if (!mounted) return;
    if (session == _statusRouteSession) {
      _isStatusRouteOpen = false;
    }
  }

  void _dismissStatusIfOpen() {
    final bool isCurrent = ModalRoute.of(context)?.isCurrent ?? true;
    if (!_isStatusRouteOpen || isCurrent) {
      return;
    }
    if (Navigator.of(context).canPop()) {
      context.pop();
    }
    _isStatusRouteOpen = false;
  }
}
