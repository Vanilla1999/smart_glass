import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_glasses/modules/wear/application/wear_ui_lifecycle.dart';
import 'package:smart_glasses/modules/wear/config/wear_dependencies.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/wear_voice_command.dart';
import 'package:smart_glasses/modules/wear/infrastructure/flutter_wear_navigation_output.dart';
import 'package:smart_glasses/modules/wear/infrastructure/noop_wear_navigation_output.dart';
import 'package:smart_glasses/modules/wear/navigation/wear_routes.dart';
import 'package:smart_glasses/modules/wear/services/wear_voice_session.dart';

class WearModuleApp extends StatefulWidget {
  const WearModuleApp({super.key});

  @override
  State<WearModuleApp> createState() => _WearModuleAppState();
}

class _WearModuleAppState extends State<WearModuleApp>
    with WidgetsBindingObserver {
  late final GoRouter _router;
  StreamSubscription<WearVoiceCommand>? _voiceSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _router = GoRouter(
      initialLocation: WearRoute.initialRoute,
      routes: WearRoute.goRouteWear,
      observers: <NavigatorObserver>[
        _WearNavigatorObserver(),
      ],
    );
    final flow = WearDependencies.I.wearFlowController;
    flow.setNavigationOutput(FlutterWearNavigationOutput(router: _router));
    flow.setUiLifecycle(WearUiLifecycle.active);
    _voiceSub = WearDependencies.I.voiceControlService.commandStream.listen(
      flow.handleVoiceCommand,
      onError: (Object error, StackTrace stackTrace) {
        print('[WearModuleApp] voice command stream error=$error\n$stackTrace');
      },
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      print('[WearModuleApp] post-frame voice start');
      WearVoiceSession.I.start();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    print('[WearModuleApp] lifecycle state=$state');
    if (state == AppLifecycleState.detached) {
      WearDependencies.I.wearFlowController.setUiLifecycle(
        WearUiLifecycle.inactive,
      );
      WearVoiceSession.I.stop();
      return;
    }
    if (state == AppLifecycleState.resumed) {
      WearDependencies.I.wearFlowController.setUiLifecycle(
        WearUiLifecycle.active,
      );
      WearVoiceSession.I.restart(reason: 'app_lifecycle_resumed');
      return;
    }
    WearDependencies.I.wearFlowController.setUiLifecycle(
      WearUiLifecycle.inactive,
    );
    WearVoiceSession.I.diagnostics().then(
          (String diagnostics) => print(
            '[WearModuleApp] lifecycle diagnostics state=$state $diagnostics',
          ),
        );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _voiceSub?.cancel();
    WearDependencies.I.wearFlowController.setNavigationOutput(
      NoopWearNavigationOutput(),
    );
    WearDependencies.I.wearFlowController.setUiLifecycle(
      WearUiLifecycle.inactive,
    );
    WearVoiceSession.I.stop();
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        print(
          '[STACK-DEBUG] WearModuleApp.outer PopScope: '
          'didPop=$didPop, result=$result, innerCanPop=${_router.canPop()}',
        );
        if (didPop) {
          return;
        }
        if (_router.canPop()) {
          print(
              '[STACK-DEBUG] WearModuleApp: delegating system back to inner GoRouter.pop()');
          _router.pop();
          return;
        }
        print(
            '[STACK-DEBUG] WearModuleApp: inner router cannot pop, staying in module');
      },
      child: MaterialApp.router(
        routerConfig: _router,
      ),
    );
  }
}

class _WearNavigatorObserver extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    print(
      '[STACK-DEBUG] didPush: route=${route.settings.name}, '
      'previousRoute=${previousRoute?.settings.name}',
    );
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    print(
      '[STACK-DEBUG] didPop: route=${route.settings.name}, '
      'previousRoute=${previousRoute?.settings.name}',
    );
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    print(
      '[STACK-DEBUG] didReplace: newRoute=${newRoute?.settings.name}, '
      'oldRoute=${oldRoute?.settings.name}',
    );
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    print(
      '[STACK-DEBUG] didRemove: route=${route.settings.name}, '
      'previousRoute=${previousRoute?.settings.name}',
    );
  }
}
