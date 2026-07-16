import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_glasses/modules/wear/application/wear_flow_controller.dart';
import 'package:smart_glasses/modules/wear/application/wear_flow_state.dart';
import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/application/wear_ui_lifecycle.dart';
import 'package:smart_glasses/modules/wear/config/wear_dependencies.dart';
import 'package:smart_glasses/modules/wear/config/wear_session.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/voice_list_matcher.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/wear_voice_command.dart';
import 'package:smart_glasses/modules/wear/infrastructure/flutter_wear_navigation_output.dart';
import 'package:smart_glasses/modules/wear/infrastructure/noop_wear_navigation_output.dart';
import 'package:smart_glasses/modules/wear/navigation/wear_routes.dart';
import 'package:smart_glasses/modules/wear/presentation/glasses/wear_glasses_payload.dart';
import 'package:smart_glasses/modules/wear/presentation/widgets/wear_loading.dart';
import 'package:smart_glasses/modules/wear/services/wear_voice_session.dart';
import 'package:smart_glasses/modules/wear/services/wear_status_icon_reporter.dart';
import 'package:smart_glasses/modules/wear/theme/wear_colors.dart';
import 'package:smart_glasses/modules/wear/theme/wear_typography.dart';

class WearModuleApp extends StatefulWidget {
  const WearModuleApp({
    super.key,
    this.onRouterReady,
    this.flowController,
    this.voiceCommandStream,
    this.voicePhraseStream,
    this.voicePartialPhraseStream,
    this.routes,
    this.initialLocation,
    this.onStartVoice,
    this.onStopVoice,
    this.onRestartVoice,
  });

  final ValueChanged<GoRouter>? onRouterReady;
  final WearFlowController? flowController;
  final Stream<WearVoiceCommand>? voiceCommandStream;
  final Stream<String>? voicePhraseStream;
  final Stream<String>? voicePartialPhraseStream;
  final List<RouteBase>? routes;
  final String? initialLocation;
  final Future<void> Function()? onStartVoice;
  final Future<void> Function()? onStopVoice;
  final Future<void> Function(String reason)? onRestartVoice;

  @override
  State<WearModuleApp> createState() => _WearModuleAppState();
}

class _WearModuleAppState extends State<WearModuleApp>
    with WidgetsBindingObserver {
  late final GoRouter _router;
  StreamSubscription<WearVoiceCommand>? _voiceSub;
  StreamSubscription<String>? _voicePhraseSub;
  StreamSubscription<String>? _voicePartialPhraseSub;
  StreamSubscription<WearFlowState>? _flowStateSub;
  StreamSubscription<dynamic>? _authorizedSub;
  StreamSubscription<void>? _clearedSub;
  Timer? _voiceHealthTimer;
  bool _voiceStarted = false;
  bool _voiceStarting = false;
  String? _voiceStartError;
  String? _consumedPartialPhrase;
  int _consumedPartialPhraseAt = 0;
  int? _voiceStartupToken;

  static const int _finalPhraseSuppressMs = 1500;

  WearFlowController get _flow =>
      widget.flowController ?? WearDependencies.I.wearFlowController;

  Stream<WearVoiceCommand> get _voiceCommands {
    final Stream<WearVoiceCommand>? stream = widget.voiceCommandStream;
    if (stream != null) return stream;
    if (widget.onStartVoice != null) {
      return const Stream<WearVoiceCommand>.empty();
    }
    return WearDependencies.I.voiceControlService.commandStream;
  }

  Stream<String> get _voicePhrases {
    final Stream<String>? stream = widget.voicePhraseStream;
    if (stream != null) return stream;
    if (widget.onStartVoice != null) return const Stream<String>.empty();
    return WearDependencies.I.voiceControlService.phraseStream;
  }

  Stream<String> get _voicePartialPhrases {
    final Stream<String>? stream = widget.voicePartialPhraseStream;
    if (stream != null) return stream;
    if (widget.onStartVoice != null) return const Stream<String>.empty();
    return WearDependencies.I.voiceControlService.partialPhraseStream;
  }

  @override
  void initState() {
    super.initState();
    print('[VOICE-LIFECYCLE] WearModuleApp initState');
    WidgetsBinding.instance.addObserver(this);
    if (widget.onStartVoice == null) {
      WearDependencies.I.warmupVoiceTypingInBackground();
    }
    _router = GoRouter(
      initialLocation: widget.initialLocation ?? WearRoute.initialRoute,
      routes: widget.routes ?? WearRoute.goRouteWear,
      observers: <NavigatorObserver>[
        _WearNavigatorObserver(),
      ],
    );
    widget.onRouterReady?.call(_router);
    final flow = _flow;
    flow.setNavigationOutput(FlutterWearNavigationOutput(router: _router));
    flow.setUiLifecycle(WearUiLifecycle.active);
    _voiceSub = _voiceCommands.listen(
      (WearVoiceCommand command) async {
        final int startedAt = DateTime.now().millisecondsSinceEpoch;
        print(
          '[WearModuleApp] voice command received command=$command '
          'screen=${flow.state.screen} at=$startedAt',
        );
        await flow.handleVoiceCommand(command);
        final int finishedAt = DateTime.now().millisecondsSinceEpoch;
        print(
          '[WearModuleApp] voice command handled command=$command '
          'screen=${flow.state.screen} durationMs=${finishedAt - startedAt}',
        );
      },
      onError: (Object error, StackTrace stackTrace) {
        print('[WearModuleApp] voice command stream error=$error\n$stackTrace');
      },
    );
    _voicePhraseSub = _voicePhrases.listen(
      (String phrase) async {
        final int startedAt = DateTime.now().millisecondsSinceEpoch;
        if (_shouldSuppressFinalPhrase(phrase, startedAt)) {
          print(
            '[WearModuleApp] suppress final phrase after consumed partial '
            'phrase="$phrase" screen=${flow.state.screen}',
          );
          return;
        }
        print(
          '[WearModuleApp] voice phrase received phrase="$phrase" '
          'screen=${flow.state.screen} at=$startedAt',
        );
        await flow.handleVoicePhrase(phrase);
        final int finishedAt = DateTime.now().millisecondsSinceEpoch;
        print(
          '[WearModuleApp] voice phrase handled phrase="$phrase" '
          'screen=${flow.state.screen} durationMs=${finishedAt - startedAt}',
        );
      },
      onError: (Object error, StackTrace stackTrace) {
        print('[WearModuleApp] voice phrase stream error=$error\n$stackTrace');
      },
    );
    _voicePartialPhraseSub = _voicePartialPhrases.listen(
      (String phrase) async {
        final int startedAt = DateTime.now().millisecondsSinceEpoch;
        if (_shouldSuppressConsumedPartialPhrase(phrase, startedAt)) {
          print(
            '[WearModuleApp] suppress partial phrase after consumed partial '
            'phrase="$phrase" screen=${flow.state.screen}',
          );
          return;
        }
        print(
          '[WearModuleApp] voice partial phrase received phrase="$phrase" '
          'screen=${flow.state.screen} at=$startedAt',
        );
        final bool consumed = await flow.handleVoicePartialPhrase(phrase);
        if (consumed) {
          _consumedPartialPhrase = VoiceListMatcher.normalize(phrase);
          _consumedPartialPhraseAt = startedAt;
        }
        final int finishedAt = DateTime.now().millisecondsSinceEpoch;
        print(
          '[WearModuleApp] voice partial phrase handled phrase="$phrase" '
          'screen=${flow.state.screen} consumed=$consumed '
          'durationMs=${finishedAt - startedAt}',
        );
      },
      onError: (Object error, StackTrace stackTrace) {
        print(
          '[WearModuleApp] voice partial phrase stream error=$error\n$stackTrace',
        );
      },
    );
    _flowStateSub = flow.stateStream.listen((WearFlowState state) {
      _configureVoiceForScreen(state.screen);
    });
    _configureVoiceForScreen(flow.state.screen);
    _authorizedSub = WearSession.authorizedStream.listen((_) {
      if (!_voiceStarted) {
        _startVoice('authorized');
      }
    });
    _clearedSub = WearSession.clearedStream.listen((_) {
      _stopVoiceForLogout();
    });
    _router.routerDelegate.addListener(_onRouterChange);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!WearSession.isAuthorized) {
        print('[WearModuleApp] post-frame voice start skipped: not authorized');
        return;
      }
      _startVoice('post-frame');
    });
  }

  void _onRouterChange() {
    final flow = _flow;
    if (!_voiceStarted && WearSession.isAuthorized) {
      _startVoice('router');
    }
    // Use _router.state.matchedLocation instead of
    // routeInformationProvider.value.uri.path — the provider is NOT
    // updated synchronously during GoRouterDelegate pop (go_router 14.x
    // bug/design). The delegate's currentConfiguration IS updated before
    // notifyListeners(), so routerDelegate.state is always current.
    final String location = _router.state.matchedLocation;
    print(
      '[ROUTER-CHANGE] matchedLocation=$location '
      'currentScreen=${flow.state.screen}',
    );
    if (widget.onStartVoice == null) {
      WearVoiceSession.I.diagnostics().then(
            (String diagnostics) => print(
              '[VOICE-ROUTE] route changed location=$location '
              'screen=${flow.state.screen} diagnostics=$diagnostics',
            ),
          );
    }
    final WearScreenId? screenId =
        FlutterWearNavigationOutput.screenIdForRoute(location);
    if (screenId != null && screenId != flow.state.screen) {
      print('[ROUTER-CHANGE] enterScreen $screenId');
      flow.enterScreen(screenId, extra: _router.state.extra);
    }
  }

  bool _shouldSuppressFinalPhrase(String phrase, int now) {
    return _shouldSuppressConsumedPartialPhrase(phrase, now);
  }

  bool _shouldSuppressConsumedPartialPhrase(String phrase, int now) {
    final String normalized = VoiceListMatcher.normalize(phrase);
    if (normalized.isEmpty || _consumedPartialPhrase == null) {
      return false;
    }
    if (now - _consumedPartialPhraseAt > _finalPhraseSuppressMs) {
      return false;
    }
    return normalized == _consumedPartialPhrase ||
        normalized.contains(_consumedPartialPhrase!) ||
        _consumedPartialPhrase!.contains(normalized);
  }

  void _configureVoiceForScreen(WearScreenId screen) {
    if (widget.onStartVoice != null) return;
    WearVoiceSession.I.configureForScreen(screen).catchError(
      (Object error, StackTrace stackTrace) {
        print(
          '[WearModuleApp] configure voice failed screen=$screen '
          'error=$error\n$stackTrace',
        );
      },
    );
  }

  void _startVoice(String source) {
    if (_voiceStarted) {
      print(
          '[WearModuleApp] voice start skipped source=$source: already started');
      return;
    }
    _voiceStarted = true;
    void start() {
      if (!mounted) return;
      _setVoiceStarting();
      print('[WearModuleApp] voice start source=$source');
      unawaited(_runVoiceStart(source));
    }

    final SchedulerPhase phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.idle ||
        phase == SchedulerPhase.postFrameCallbacks) {
      start();
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => start());
  }

  void _setVoiceStarting() {
    if (!mounted) return;
    setState(() {
      _voiceStarting = true;
      _voiceStartError = null;
    });
    _voiceStartupToken = WearStatusIconReporter.I.beginVoiceStartup();
    unawaited(
      WearStatusIconReporter.I.sendFast(
        WearGlassesPayload.loading(
          screenType: WearGlassesScreenType.status,
          title: 'Голосовое управление',
          statusText: 'Запускаем голос...',
          subtitle: 'Пожалуйста, подождите',
        ),
      ),
    );
  }

  Future<void> _runVoiceStart(String source) async {
    final Future<void> Function()? startVoice = widget.onStartVoice;
    final int? startupToken = _voiceStartupToken;
    try {
      if (startVoice != null) {
        await startVoice();
      } else {
        await WearVoiceSession.I.start();
      }
      WearStatusIconReporter.I.endVoiceStartup(startupToken);
      if (!_isCurrentVoiceStartup(startupToken)) return;
      if (!WearSession.isAuthorized) {
        setState(() {
          _voiceStarting = false;
          _voiceStartError = null;
        });
        return;
      }
      setState(() {
        _voiceStarting = false;
        _voiceStartError = null;
      });
      _startVoiceHealthTimer();
      unawaited(_flow.renderCurrentGlasses());
    } catch (error, stackTrace) {
      print(
          '[WearModuleApp] voice start failed source=$source: $error\n$stackTrace');
      WearStatusIconReporter.I.endVoiceStartup(startupToken);
      if (!_isCurrentVoiceStartup(startupToken)) return;
      setState(() {
        _voiceStarting = false;
        _voiceStartError = 'Голосовое управление не запустилось';
      });
      unawaited(
        WearStatusIconReporter.I.sendFast(
          WearGlassesPayload.status(
            isError: true,
            title: 'Голосовое управление',
            subtitle: 'Попробуйте перезапустить модуль',
            statusText: 'Ошибка',
          ),
        ),
      );
    }
  }

  void _startVoiceHealthTimer() {
    if (widget.onStartVoice != null) return;
    _voiceHealthTimer?.cancel();
    _voiceHealthTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (!mounted || !WearSession.isAuthorized || _voiceStarting) return;
      _ensureVoiceHealthy('periodic_voice_health');
    });
  }

  void _ensureVoiceHealthy(String reason) {
    unawaited(
      WearVoiceSession.I.ensureHealthy(reason: reason).catchError(
        (Object error, StackTrace stackTrace) {
          print(
            '[WearModuleApp] voice health-check failed reason=$reason '
            'error=$error\n$stackTrace',
          );
        },
      ),
    );
  }

  void _stopVoiceForLogout() {
    _voiceStarted = false;
    _voiceHealthTimer?.cancel();
    _voiceHealthTimer = null;
    WearStatusIconReporter.I.endVoiceStartup(_voiceStartupToken);
    _voiceStartupToken = null;
    final Future<void> Function()? stopVoice = widget.onStopVoice;
    if (stopVoice != null) {
      unawaited(stopVoice());
    } else {
      unawaited(WearVoiceSession.I.stop());
    }
  }

  bool _isCurrentVoiceStartup(int? token) {
    return mounted && token != null && token == _voiceStartupToken;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    print('[WearModuleApp] lifecycle state=$state');
    if (state == AppLifecycleState.detached) {
      _flow.setUiLifecycle(
        WearUiLifecycle.inactive,
      );
      final Future<void> Function()? stopVoice = widget.onStopVoice;
      if (stopVoice != null) {
        unawaited(stopVoice());
      } else {
        unawaited(WearVoiceSession.I.stop());
      }
      return;
    }
    if (state == AppLifecycleState.resumed) {
      _flow.setUiLifecycle(
        WearUiLifecycle.active,
      );
      if (WearSession.isAuthorized) {
        final Future<void> Function(String reason)? restartVoice =
            widget.onRestartVoice;
        if (restartVoice != null) {
          unawaited(restartVoice('app_lifecycle_resumed'));
        } else {
          _ensureVoiceHealthy('app_lifecycle_resumed');
          Future<void>.delayed(const Duration(seconds: 1), () {
            if (!mounted || !WearSession.isAuthorized) return;
            _ensureVoiceHealthy('app_lifecycle_resumed_delayed');
          });
        }
      }
      return;
    }
    _flow.setUiLifecycle(
      WearUiLifecycle.inactive,
    );
    if (widget.onStopVoice == null) {
      WearVoiceSession.I.diagnostics().then(
            (String diagnostics) => print(
              '[WearModuleApp] lifecycle diagnostics state=$state $diagnostics',
            ),
          );
    }
  }

  @override
  void dispose() {
    print('[VOICE-LIFECYCLE] WearModuleApp dispose');
    WearStatusIconReporter.I.endVoiceStartup(_voiceStartupToken);
    unawaited(
      WearStatusIconReporter.I.stop().catchError(
        (Object error, StackTrace stackTrace) {
          print(
            '[WearModuleApp] stop glasses projection failed: '
            '$error\n$stackTrace',
          );
        },
      ),
    );
    _voiceHealthTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _router.routerDelegate.removeListener(_onRouterChange);
    _voiceSub?.cancel();
    _voicePhraseSub?.cancel();
    _voicePartialPhraseSub?.cancel();
    _flowStateSub?.cancel();
    _authorizedSub?.cancel();
    _clearedSub?.cancel();
    _flow.setNavigationOutput(
      NoopWearNavigationOutput(),
    );
    _flow.setUiLifecycle(
      WearUiLifecycle.inactive,
    );
    final Future<void> Function()? stopVoice = widget.onStopVoice;
    if (stopVoice != null) {
      unawaited(stopVoice());
    } else {
      unawaited(WearVoiceSession.I.stop());
    }
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Widget app = PopScope(
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
    final Widget voiceAwareApp = Stack(
      textDirection: TextDirection.ltr,
      children: <Widget>[
        app,
        if (WearSession.isAuthorized &&
            (_voiceStarting || _voiceStartError != null))
          Positioned.fill(
            child: _VoiceStartupOverlay(
              isError: _voiceStartError != null,
              message: _voiceStartError,
            ),
          ),
      ],
    );

    if (kDebugMode) {
      return Stack(
        textDirection: TextDirection.ltr,
        children: <Widget>[
          voiceAwareApp,
          StreamBuilder<WearFlowState>(
            stream: _flow.stateStream,
            builder: (BuildContext context, AsyncSnapshot<WearFlowState> snap) {
              final WearScreenId screen =
                  snap.data?.screen ?? _flow.state.screen;
              final String location = _router.state.matchedLocation;
              return Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Directionality(
                  textDirection: TextDirection.ltr,
                  child: Container(
                    color: const Color(0xCC000000),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    child: Text(
                      'Screen: $screen | Route: $location',
                      style:
                          const TextStyle(color: Colors.yellow, fontSize: 10),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      );
    }
    return voiceAwareApp;
  }
}

class _VoiceStartupOverlay extends StatelessWidget {
  const _VoiceStartupOverlay({
    required this.isError,
    required this.message,
  });

  final bool isError;
  final String? message;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: ColoredBox(
        color: const Color(0xEFFFFFFF),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (!isError) const WearLoading(size: 44),
              if (isError)
                const Icon(
                  Icons.error_outline,
                  color: WearColors.red1,
                  size: 44,
                ),
              const SizedBox(height: 16),
              Text(
                isError ? message! : 'Подготовка голосового\nуправления',
                style: WearTypography.lable,
                textAlign: TextAlign.center,
              ),
              if (!isError) ...<Widget>[
                const SizedBox(height: 8),
                Text(
                  'Пожалуйста, подождите',
                  style: WearTypography.lable.copyWith(
                    color: WearColors.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
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
