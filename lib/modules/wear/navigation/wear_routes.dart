import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_glasses/modules/wear/models/wear_printer_selection.dart';
import 'package:smart_glasses/modules/wear/presentation/input/wear_print_code_input_screen.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/main/wear_main_screen.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/main/wear_scanner_connect_screen.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/menu/wear_menu_screen.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/printers/wear_printer_select_screen.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/scan/wear_product_select_screen.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/scan/wear_scan_idle_screen.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/settings/db_settings_screen.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/settings/wear_settings_screen.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/status/wear_status_args.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/status/wear_status_screen.dart';

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
          path: WearMenuScreen.route,
          builder: (BuildContext context, GoRouterState state) {
            return const WearMenuScreen();
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
          path: WearPrinterSelectScreen.route,
          builder: (BuildContext context, GoRouterState state) {
            return const WearPrinterSelectScreen();
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
          path: WearPrintCodeInputScreen.route,
          builder: (BuildContext context, GoRouterState state) {
            return WearPrintCodeInputScreen(args: state.extra);
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
