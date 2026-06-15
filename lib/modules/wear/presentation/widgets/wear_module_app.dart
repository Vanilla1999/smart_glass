import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_glasses/modules/wear/navigation/wear_routes.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/menu/wear_menu_screen.dart';
import 'package:smart_glasses/modules/wear/services/wear_voice_session.dart';
import 'package:smart_glasses/modules/wear/presentation/widgets/wear_voice_command_listener.dart';

class WearModuleApp extends StatefulWidget {
  const WearModuleApp({super.key});

  @override
  State<WearModuleApp> createState() => _WearModuleAppState();
}

class _WearModuleAppState extends State<WearModuleApp>
    with WidgetsBindingObserver {
  late final GoRouter _router;

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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      print('[WearModuleApp] post-frame voice start');
      WearVoiceSession.I.start();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    print('[WearModuleApp] lifecycle state=$state');
    if (state == AppLifecycleState.detached) {
      WearVoiceSession.I.stop();
      return;
    }
    if (state == AppLifecycleState.resumed) {
      WearVoiceSession.I.restart(reason: 'app_lifecycle_resumed');
      return;
    }
    WearVoiceSession.I.diagnostics().then(
          (String diagnostics) => print(
            '[WearModuleApp] lifecycle diagnostics state=$state $diagnostics',
          ),
        );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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
        builder: (BuildContext context, Widget? child) {
          return WearVoiceCommandOrchestrator(
            onBack: _handleVoiceBack,
            onHome: _handleVoiceHome,
            child: child ?? const SizedBox.shrink(),
          );
        },
      ),
    );
  }

  void _handleVoiceBack() {
    if (_router.canPop()) {
      print('[VoiceCommandOrchestrator] popping inner GoRouter');
      _router.pop();
      return;
    }
    print('[VoiceCommandOrchestrator] cannot pop, no back history');
  }

  void _handleVoiceHome() {
    print('[VoiceCommandOrchestrator] going home');
    _router.go(WearMenuScreen.route);
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
