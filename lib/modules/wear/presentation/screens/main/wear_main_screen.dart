import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_glasses/modules/wear/config/wear_dependencies.dart';
import 'package:smart_glasses/modules/wear/config/wear_session.dart';
import 'package:smart_glasses/modules/wear/presentation/glasses/wear_glasses_payload.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/main/cubit/wear_auth_cubit.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/menu/wear_menu_screen.dart';
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
      if (WearSession.isAuthorized) {
        context.go(WearMenuScreen.route);
        return;
      }
      WearStatusIconReporter.I.show(WearGlassesPayload.authWaitingBarcode());
    });
  }

  @override
  void dispose() {
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

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        print(
          '[BACK-DEBUG] WearMainScreen.PopScope: '
          'didPop=$didPop, result=$result',
        );
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        body: _buildBody(state),
      ),
    );
  }

  Widget _buildBody(WearAuthState state) {
    return Stack(
      children: _getStackChildren(state),
    );
  }

  List<Widget> _getStackChildren(WearAuthState state) {
    final List<Widget> children = [];

    children.add(
      Center(
        child: Padding(
          padding: const EdgeInsets.all(4.5),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: _getCenterColumnChildren(state),
          ),
        ),
      ),
    );

    if (state.isLoading) {
      children.add(
        Positioned.fill(
          child: ColoredBox(
            color: const Color(0x66FFFFFF),
            child: Center(
              child: WearLoading(size: 44),
            ),
          ),
        ),
      );
    }

    children.add(
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
    );

    children.add(
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
    );

    return children;
  }

  List<Widget> _getCenterColumnChildren(WearAuthState state) {
    return [
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
      InkWell(
        onTap: () {
          if (!WearSession.isAuthorized && !state.isLoading) {
            ref.read(wearAuthNotifierProvider.notifier).handleLogoLongPress();
          }
        },
        child: Text(
          'Для входа используйте\nштрихкод вашего бейджа',
          style: WearTypography.lable,
          textAlign: TextAlign.center,
        ),
      ),
      const SizedBox(height: 28),
      GestureDetector(
        onTap: () =>
            ref.read(wearAuthNotifierProvider.notifier).handleLogoTap(),
        onLongPress: () =>
            ref.read(wearAuthNotifierProvider.notifier).handleLogoLongPress(),
        child: SvgPicture.asset(WearImages.logo),
      ),
    ];
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
    print(
      '[BACK-DEBUG] MainScreen._openOrReplaceStatus: pushing status, '
      'kind=${args.kind}, title=${args.title}',
    );
    await context.push(WearStatusScreen.route, extra: args);
    print(
      '[BACK-DEBUG] MainScreen._openOrReplaceStatus: status popped back, '
      'session=$session, _statusRouteSession=$_statusRouteSession, '
      'kind=${args.kind}, isAuthorized=${WearSession.isAuthorized}',
    );

    if (!mounted) return;
    if (session == _statusRouteSession) {
      _isStatusRouteOpen = false;
    }
    if (args.kind == WearStatusKind.success && WearSession.isAuthorized) {
      if (!mounted) return;
      print('[BACK-DEBUG] MainScreen: opening WearMenuScreen');
      context.go(WearMenuScreen.route);
    } else if (args.kind == WearStatusKind.error && !WearSession.isAuthorized) {
      await WearStatusIconReporter.I.send(
        WearGlassesPayload.authWaitingBarcode(),
      );
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
