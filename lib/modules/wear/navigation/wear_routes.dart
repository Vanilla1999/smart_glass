import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_glasses/modules/wear/models/wear_printer_selection.dart';
import 'package:smart_glasses/modules/wear/domain/availability/model/wear_availability_group.dart';
import 'package:smart_glasses/modules/wear/domain/availability/model/wear_availability_product.dart';
import 'package:smart_glasses/modules/wear/presentation/input/wear_print_code_input_screen.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/continue_scan/wear_continue_scan_screen.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/availability/wear_availability_check_screen.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/availability/wear_availability_direct_scan_screen.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/availability/wear_availability_fill_screen.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/availability/wear_availability_group_screen.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/availability/wear_availability_interaction_screen.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/availability/wear_availability_product_screen.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/help/wear_help_screen.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/main/wear_main_screen.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/main/wear_scanner_connect_screen.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/menu/wear_menu_screen.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/printers/wear_printer_select_screen.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/scan/wear_product_select_screen.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/scan/wear_scan_idle_screen.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/settings/db_settings_screen.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/settings/wear_glasses_preview_screen.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/settings/wear_settings_screen.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/status/wear_status_args.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/status/wear_status_screen.dart';
import 'package:smart_glasses/modules/wear/presentation/widgets/wear_voice_command_listener.dart';

class WearRoute {
  static String get initialRoute => _shouldSkipScannerConnect()
      ? WearMainScreen.route
      : WearScannerConnectScreen.route;

  static List<RouteBase> get goRouteWear => <RouteBase>[
        GoRoute(
          path: WearScannerConnectScreen.route,
          builder: (BuildContext context, GoRouterState state) {
            return const WearVoiceCommandOrchestrator(
              child: WearScannerConnectScreen(),
            );
          },
        ),
        GoRoute(
          path: WearMainScreen.route,
          builder: (BuildContext context, GoRouterState state) {
            return const WearVoiceCommandOrchestrator(
              child: WearMainScreen(),
            );
          },
        ),
        GoRoute(
          path: WearMenuScreen.route,
          builder: (BuildContext context, GoRouterState state) {
            return const WearVoiceCommandOrchestrator(
              child: WearMenuScreen(),
            );
          },
        ),
        GoRoute(
          path: WearSettingsScreen.route,
          builder: (BuildContext context, GoRouterState state) {
            return const WearVoiceCommandOrchestrator(
              child: WearSettingsScreen(),
            );
          },
        ),
        GoRoute(
          path: DBSettingsScreen.route,
          builder: (BuildContext context, GoRouterState state) {
            return const WearVoiceCommandOrchestrator(
              child: DBSettingsScreen(),
            );
          },
        ),
        GoRoute(
          path: WearGlassesPreviewScreen.route,
          builder: (BuildContext context, GoRouterState state) {
            return const WearGlassesPreviewScreen();
          },
        ),
        GoRoute(
          path: WearPrinterSelectScreen.route,
          builder: (BuildContext context, GoRouterState state) {
            return const WearVoiceCommandOrchestrator(
              child: WearPrinterSelectScreen(),
            );
          },
        ),
        GoRoute(
          path: WearScanIdleScreen.route,
          builder: (BuildContext context, GoRouterState state) {
            final WearPrinterSelection? selection =
                state.extra is WearPrinterSelection
                    ? state.extra! as WearPrinterSelection
                    : null;
            return WearVoiceCommandOrchestrator(
              child: WearScanIdleScreen(printers: selection),
            );
          },
        ),
        GoRoute(
          path: WearProductSelectScreen.route,
          builder: (BuildContext context, GoRouterState state) {
            final WearProductSelectArgs? args =
                state.extra is WearProductSelectArgs
                    ? state.extra! as WearProductSelectArgs
                    : null;
            return WearVoiceCommandOrchestrator(
              child: WearProductSelectScreen(args: args),
            );
          },
        ),
        GoRoute(
          path: WearPrintCodeInputScreen.route,
          builder: (BuildContext context, GoRouterState state) {
            return WearVoiceCommandOrchestrator(
              child: WearPrintCodeInputScreen(args: state.extra),
            );
          },
        ),
        GoRoute(
          path: WearAvailabilityInteractionScreen.route,
          builder: (BuildContext context, GoRouterState state) {
            return const WearVoiceCommandOrchestrator(
              child: WearAvailabilityInteractionScreen(),
            );
          },
        ),
        GoRoute(
          path: WearAvailabilityGroupScreen.route,
          builder: (BuildContext context, GoRouterState state) {
            return const WearVoiceCommandOrchestrator(
              child: WearAvailabilityGroupScreen(),
            );
          },
        ),
        GoRoute(
          path: WearAvailabilityDirectScanScreen.route,
          builder: (BuildContext context, GoRouterState state) {
            return const WearVoiceCommandOrchestrator(
              child: WearAvailabilityDirectScanScreen(),
            );
          },
        ),
        GoRoute(
          path: WearAvailabilityProductScreen.route,
          builder: (BuildContext context, GoRouterState state) {
            final WearAvailabilityGroup? group =
                state.extra is WearAvailabilityGroup
                    ? state.extra! as WearAvailabilityGroup
                    : null;
            return WearVoiceCommandOrchestrator(
              child: WearAvailabilityProductScreen(group: group),
            );
          },
        ),
        GoRoute(
          path: WearAvailabilityCheckScreen.route,
          builder: (BuildContext context, GoRouterState state) {
            final WearAvailabilityProduct? product =
                state.extra is WearAvailabilityProduct
                    ? state.extra! as WearAvailabilityProduct
                    : null;
            return WearVoiceCommandOrchestrator(
              child: WearAvailabilityCheckScreen(product: product),
            );
          },
        ),
        GoRoute(
          path: WearAvailabilityFillScreen.route,
          builder: (BuildContext context, GoRouterState state) {
            return const WearVoiceCommandOrchestrator(
              child: WearAvailabilityFillScreen(),
            );
          },
        ),
        GoRoute(
          path: WearHelpScreen.route,
          builder: (BuildContext context, GoRouterState state) {
            return const WearVoiceCommandOrchestrator(
              child: WearHelpScreen(),
            );
          },
        ),
        GoRoute(
          path: WearContinueScanScreen.route,
          builder: (BuildContext context, GoRouterState state) {
            return const WearVoiceCommandOrchestrator(
              child: WearContinueScanScreen(),
            );
          },
        ),
        GoRoute(
          path: WearStatusScreen.route,
          builder: (BuildContext context, GoRouterState state) {
            final WearStatusScreenArgs? args =
                state.extra is WearStatusScreenArgs
                    ? state.extra! as WearStatusScreenArgs
                    : null;
            return WearVoiceCommandOrchestrator(
              child: WearStatusScreen(args: args),
            );
          },
        ),
      ];

  static bool _shouldSkipScannerConnect() {
    return dotenv.env['WEAR_SKIP_SCANNER_CONNECT_SCREEN'] == 'true';
  }
}
