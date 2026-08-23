import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_glasses/modules/wear/application/wear_flow_controller.dart';
import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/application/wear_status_state.dart';
import 'package:smart_glasses/modules/wear/config/wear_dependencies.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/main/cubit/wear_auth_cubit.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/menu/wear_menu_screen.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/settings/db_settings_screen.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/status/wear_status_args.dart';
import 'package:smart_glasses/modules/wear/presentation/widgets/wear_loading.dart';
import 'package:smart_glasses/modules/wear/presentation/widgets/wear_scanner_status_indicator.dart';
import 'package:smart_glasses/modules/wear/presentation/widgets/wear_status_bar.dart';
import 'package:smart_glasses/modules/wear/presentation/widgets/wear_svg_icon.dart';
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
  late final WearScreenActionRegistration _screenActionsRegistration;

  @override
  void initState() {
    super.initState();
    final WearFlowController flow = WearDependencies.I.wearFlowController;
    _screenActionsRegistration = flow.registerScreenActions(
      WearScreenId.main,
      WearScreenActionHandler(
        onBarcode: (String barcode) =>
            ref.read(wearAuthNotifierProvider.notifier).handleBarcode(barcode),
        barcodeEnabled: () =>
            !flow.authority.isAuthorized &&
            !ref.read(wearAuthNotifierProvider).isLoading,
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (flow.authority.isAuthorized) {
        context.go(WearMenuScreen.route);
      }
    });
  }

  @override
  void dispose() {
    WearDependencies.I.wearFlowController
        .unregisterScreenActions(_screenActionsRegistration);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<WearAuthState>(wearAuthNotifierProvider,
        (WearAuthState? previous, WearAuthState next) {
      if (previous?.phase != next.phase) {
        WearDependencies.I.wearFlowController
            .refreshScreenActions(WearScreenId.main);
      }
      if (previous?.nav != next.nav && next.nav != null) {
        final WearStatusScreenArgs nav = next.nav!;
        ref.read(wearAuthNotifierProvider.notifier).consumeNavigation();
        WearDependencies.I.wearFlowController.showStatus(
          nav,
          completion: nav.kind == WearStatusKind.success
              ? const WearStatusCompletion.goTo(WearScreenId.menu)
              : const WearStatusCompletion.goTo(WearScreenId.main),
        );
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
          if (!WearDependencies.I.authority.isAuthorized && !state.isLoading) {
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
}
