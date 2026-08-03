import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_glasses/modules/wear/application/wear_navigation_entry.dart';
import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/infrastructure/flutter_wear_navigation_output.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/menu/wear_menu_screen.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/printers/wear_printer_select_screen.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/scan/wear_product_select_screen.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/scan/wear_scan_idle_screen.dart';

void main() {
  testWidgets('synchronizes a multi-entry router stack without blocking',
      (WidgetTester tester) async {
    final GoRouter router = _router();
    addTearDown(router.dispose);
    final FlutterWearNavigationOutput output =
        FlutterWearNavigationOutput(router: router);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    await output.synchronize(const <WearNavigationEntry>[
      WearNavigationEntry(screen: WearScreenId.menu),
      WearNavigationEntry(screen: WearScreenId.printerSelect),
      WearNavigationEntry(screen: WearScreenId.scanIdle),
    ]);
    await tester.pumpAndSettle();

    expect(router.state.matchedLocation, WearScanIdleScreen.route);
    router.pop();
    await tester.pumpAndSettle();
    expect(router.state.matchedLocation, WearPrinterSelectScreen.route);
    router.pop();
    await tester.pumpAndSettle();
    expect(router.state.matchedLocation, WearMenuScreen.route);
  });

  testWidgets('replace preserves the parent stack for back navigation',
      (WidgetTester tester) async {
    final GoRouter router = _router();
    addTearDown(router.dispose);
    final FlutterWearNavigationOutput output =
        FlutterWearNavigationOutput(router: router);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    unawaited(router.push(WearPrinterSelectScreen.route));
    await tester.pumpAndSettle();

    await output.replace(WearScreenId.productSelect);
    await tester.pumpAndSettle();
    expect(router.state.matchedLocation, WearProductSelectScreen.route);

    router.pop();
    await tester.pumpAndSettle();
    expect(router.state.matchedLocation, WearMenuScreen.route);
  });

  testWidgets('replace to ancestor completes and collapses descendants',
      (WidgetTester tester) async {
    final GoRouter router = _router();
    addTearDown(router.dispose);
    final FlutterWearNavigationOutput output =
        FlutterWearNavigationOutput(router: router);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    unawaited(router.push(WearPrinterSelectScreen.route));
    await tester.pumpAndSettle();
    final Future<Object?> descendant = router.push(WearScanIdleScreen.route);
    await tester.pumpAndSettle();

    await output.replace(WearScreenId.printerSelect);
    await tester.pumpAndSettle();

    expect(await descendant, isNull);
    expect(router.state.matchedLocation, WearPrinterSelectScreen.route);
    router.pop();
    await tester.pumpAndSettle();
    expect(router.state.matchedLocation, WearMenuScreen.route);
  });
}

GoRouter _router() {
  return GoRouter(
    initialLocation: WearMenuScreen.route,
    routes: <RouteBase>[
      GoRoute(
        path: WearMenuScreen.route,
        builder: (_, __) => const SizedBox(key: Key('menu')),
      ),
      GoRoute(
        path: WearPrinterSelectScreen.route,
        builder: (_, __) => const SizedBox(key: Key('printerSelect')),
      ),
      GoRoute(
        path: WearScanIdleScreen.route,
        builder: (_, __) => const SizedBox(key: Key('scanIdle')),
      ),
      GoRoute(
        path: WearProductSelectScreen.route,
        builder: (_, __) => const SizedBox(key: Key('productSelect')),
      ),
    ],
  );
}
