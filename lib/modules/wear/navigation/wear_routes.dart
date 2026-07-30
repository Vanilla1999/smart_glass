import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_glasses/modules/wear/models/wear_printer_selection.dart';
import 'package:smart_glasses/modules/wear/domain/availability/model/wear_availability_group.dart';
import 'package:smart_glasses/modules/wear/domain/availability/model/wear_availability_product.dart';
import 'package:smart_glasses/modules/wear/application/voice_clarification_args.dart';
import 'package:smart_glasses/modules/wear/presentation/input/wear_print_code_input_screen.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/continue_scan/wear_continue_scan_screen.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/availability/wear_availability_check_screen.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/availability/wear_availability_direct_scan_screen.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/availability/wear_availability_fill_screen.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/availability/wear_availability_group_screen.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/availability/wear_availability_interaction_screen.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/availability/wear_availability_product_screen.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/help/wear_help_screen.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/home/wear_home_confirm_screen.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/main/wear_main_screen.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/main/wear_scanner_connect_screen.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/menu/wear_menu_screen.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/photo/wear_latest_photo_screen.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/printers/wear_printer_select_screen.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/scan/wear_product_select_screen.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/scan/wear_scan_idle_screen.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/settings/db_settings_screen.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/settings/wear_printer_settings_screen.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/settings/wear_settings_screen.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/settings/wear_wifi_settings_screen.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/status/wear_status_args.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/status/wear_status_screen.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/voice/wear_voice_clarification_screen.dart';

class WearRoute {
  static String get initialRoute => _shouldSkipScannerConnect()
      ? WearMainScreen.route
      : WearScannerConnectScreen.route;

  static List<RouteBase> get goRouteWear => <RouteBase>[
        GoRoute(
          path: WearScannerConnectScreen.route,
          builder: (BuildContext context, GoRouterState state) {
            return const WearScannerConnectScreen();
          },
        ),
        GoRoute(
          path: WearMainScreen.route,
          builder: (BuildContext context, GoRouterState state) {
            return const WearMainScreen();
          },
        ),
        GoRoute(
          path: WearHomeConfirmScreen.route,
          builder: (BuildContext context, GoRouterState state) {
            return const WearHomeConfirmScreen();
          },
        ),
        GoRoute(
          path: WearMenuScreen.route,
          builder: (BuildContext context, GoRouterState state) {
            return const WearMenuScreen();
          },
        ),
        GoRoute(
          path: WearLatestPhotoScreen.route,
          builder: (BuildContext context, GoRouterState state) {
            return const WearLatestPhotoScreen();
          },
        ),
        GoRoute(
          path: WearSettingsScreen.route,
          builder: (BuildContext context, GoRouterState state) {
            return const WearSettingsScreen();
          },
        ),
        GoRoute(
          path: DBSettingsScreen.route,
          builder: (BuildContext context, GoRouterState state) {
            return const DBSettingsScreen();
          },
        ),
        GoRoute(
          path: WearWifiSettingsScreen.route,
          builder: (BuildContext context, GoRouterState state) {
            return const WearWifiSettingsScreen();
          },
        ),
        GoRoute(
          path: WearPrinterSettingsScreen.route,
          builder: (BuildContext context, GoRouterState state) {
            return const WearPrinterSettingsScreen();
          },
        ),
        GoRoute(
          path: WearPrinterSelectScreen.route,
          builder: (BuildContext context, GoRouterState state) {
            return WearPrinterSelectScreen(
              returnSelection: state.extra == true,
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
            return WearScanIdleScreen(printers: selection);
          },
        ),
        GoRoute(
          path: WearProductSelectScreen.route,
          builder: (BuildContext context, GoRouterState state) {
            final WearProductSelectArgs? args =
                state.extra is WearProductSelectArgs
                    ? state.extra! as WearProductSelectArgs
                    : null;
            return WearProductSelectScreen(args: args);
          },
        ),
        GoRoute(
          path: WearVoiceClarificationScreen.route,
          builder: (BuildContext context, GoRouterState state) {
            final VoiceClarificationArgs? args =
                state.extra is VoiceClarificationArgs
                    ? state.extra! as VoiceClarificationArgs
                    : null;
            return WearVoiceClarificationScreen(args: args);
          },
        ),
        GoRoute(
          path: WearPrintCodeInputScreen.route,
          builder: (BuildContext context, GoRouterState state) {
            return WearPrintCodeInputScreen(args: state.extra);
          },
        ),
        GoRoute(
          path: WearAvailabilityInteractionScreen.route,
          builder: (BuildContext context, GoRouterState state) {
            return const WearAvailabilityInteractionScreen();
          },
        ),
        GoRoute(
          path: WearAvailabilityGroupScreen.route,
          builder: (BuildContext context, GoRouterState state) {
            return const WearAvailabilityGroupScreen();
          },
        ),
        GoRoute(
          path: WearAvailabilityDirectScanScreen.route,
          builder: (BuildContext context, GoRouterState state) {
            return const WearAvailabilityDirectScanScreen();
          },
        ),
        GoRoute(
          path: WearAvailabilityProductScreen.route,
          builder: (BuildContext context, GoRouterState state) {
            final WearAvailabilityGroup? group =
                state.extra is WearAvailabilityGroup
                    ? state.extra! as WearAvailabilityGroup
                    : null;
            return WearAvailabilityProductScreen(group: group);
          },
        ),
        GoRoute(
          path: WearAvailabilityCheckScreen.route,
          builder: (BuildContext context, GoRouterState state) {
            final WearAvailabilityProduct? product =
                state.extra is WearAvailabilityProduct
                    ? state.extra! as WearAvailabilityProduct
                    : null;
            return WearAvailabilityCheckScreen(product: product);
          },
        ),
        GoRoute(
          path: WearAvailabilityFillScreen.route,
          builder: (BuildContext context, GoRouterState state) {
            return const WearAvailabilityFillScreen();
          },
        ),
        GoRoute(
          path: WearHelpScreen.route,
          builder: (BuildContext context, GoRouterState state) {
            return const WearHelpScreen();
          },
        ),
        GoRoute(
          path: WearContinueScanScreen.route,
          builder: (BuildContext context, GoRouterState state) {
            return const WearContinueScanScreen();
          },
        ),
        GoRoute(
          path: WearStatusScreen.route,
          builder: (BuildContext context, GoRouterState state) {
            final WearStatusScreenArgs? args =
                state.extra is WearStatusScreenArgs
                    ? state.extra! as WearStatusScreenArgs
                    : null;
            return WearStatusScreen(args: args);
          },
        ),
      ];

  static bool _shouldSkipScannerConnect() {
    return dotenv.env['WEAR_SKIP_SCANNER_CONNECT_SCREEN'] == 'true';
  }
}
