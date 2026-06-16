import 'package:go_router/go_router.dart';
import 'package:smart_glasses/modules/wear/application/ports/wear_navigation_output.dart';
import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/presentation/input/wear_print_code_input_screen.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/availability/wear_availability_check_screen.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/availability/wear_availability_direct_scan_screen.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/availability/wear_availability_fill_screen.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/availability/wear_availability_group_screen.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/availability/wear_availability_interaction_screen.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/availability/wear_availability_product_screen.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/continue_scan/wear_continue_scan_screen.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/help/wear_help_screen.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/main/wear_main_screen.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/main/wear_scanner_connect_screen.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/menu/wear_menu_screen.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/printers/wear_printer_select_screen.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/scan/wear_product_select_screen.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/scan/wear_scan_idle_screen.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/settings/db_settings_screen.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/settings/wear_settings_screen.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/status/wear_status_screen.dart';

class FlutterWearNavigationOutput implements WearNavigationOutput {
  FlutterWearNavigationOutput({required GoRouter router}) : _router = router;

  final GoRouter _router;

  @override
  Future<void> goTo(WearScreenId screen, {Object? extra}) async {
    final String route = _routeFor(screen);
    print(
      '[FlutterWearNavigationOutput] goTo screen=$screen route=$route extra=$extra',
    );
    if (_shouldReplace(screen)) {
      _router.go(route, extra: extra);
    } else {
      await _router.push(route, extra: extra);
    }
  }

  @override
  Future<void> back() async {
    if (_router.canPop()) {
      _router.pop();
    }
  }

  @override
  Future<void> home() async {
    _router.go(WearMenuScreen.route);
  }

  bool _shouldReplace(WearScreenId screen) {
    return switch (screen) {
      WearScreenId.scannerConnect ||
      WearScreenId.main ||
      WearScreenId.menu =>
        true,
      _ => false,
    };
  }

  String _routeFor(WearScreenId screen) {
    return switch (screen) {
      WearScreenId.scannerConnect => WearScannerConnectScreen.route,
      WearScreenId.main => WearMainScreen.route,
      WearScreenId.status => WearStatusScreen.route,
      WearScreenId.menu => WearMenuScreen.route,
      WearScreenId.printerSelect => WearPrinterSelectScreen.route,
      WearScreenId.scanIdle => WearScanIdleScreen.route,
      WearScreenId.productSelect => WearProductSelectScreen.route,
      WearScreenId.printCodeInput => WearPrintCodeInputScreen.route,
      WearScreenId.availabilityInteraction =>
        WearAvailabilityInteractionScreen.route,
      WearScreenId.availabilityGroup => WearAvailabilityGroupScreen.route,
      WearScreenId.availabilityProduct => WearAvailabilityProductScreen.route,
      WearScreenId.availabilityDirectScan =>
        WearAvailabilityDirectScanScreen.route,
      WearScreenId.availabilityCheck => WearAvailabilityCheckScreen.route,
      WearScreenId.availabilityFill => WearAvailabilityFillScreen.route,
      WearScreenId.continueScan => WearContinueScanScreen.route,
      WearScreenId.help => WearHelpScreen.route,
      WearScreenId.settings => WearSettingsScreen.route,
      WearScreenId.dbSettings => DBSettingsScreen.route,
    };
  }
}
