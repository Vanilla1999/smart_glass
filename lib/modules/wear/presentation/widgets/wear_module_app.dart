import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_glasses/modules/wear/navigation/wear_routes.dart';
import 'package:smart_glasses/modules/wear/presentation/widgets/glasses_preview/wear_glasses_preview_overlay.dart';

class WearModuleApp extends StatelessWidget {
  const WearModuleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      routerConfig: GoRouter(
        initialLocation: WearRoute.initialRoute,
        routes: WearRoute.goRouteWear,
      ),
      builder: (context, child) {
        return Stack(
          children: [
            child ?? const SizedBox(),
            const Positioned.fill(
              child: WearGlassesPreviewOverlay(),
            ),
          ],
        );
      },
    );
  }
}
