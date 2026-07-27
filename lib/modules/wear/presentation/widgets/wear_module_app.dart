import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_glasses/core/services/method_channel_service.dart';
import 'package:smart_glasses/modules/wear/application/wear_flow_controller.dart';
import 'package:smart_glasses/modules/wear/application/wear_flow_state.dart';
import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/application/wear_ui_lifecycle.dart';
import 'package:smart_glasses/modules/wear/config/wear_dependencies.dart';
import 'package:smart_glasses/modules/wear/config/wear_session.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/wear_voice_command.dart';
import 'package:smart_glasses/modules/wear/infrastructure/flutter_wear_navigation_output.dart';
import 'package:smart_glasses/modules/wear/infrastructure/noop_wear_navigation_output.dart';
import 'package:smart_glasses/modules/wear/navigation/wear_routes.dart';
import 'package:smart_glasses/modules/wear/presentation/widgets/wear_loading.dart';
import 'package:smart_glasses/modules/wear/services/wear_voice_session.dart';
import 'package:smart_glasses/modules/wear/services/voice_state.dart';
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
    this.routes,
    this.initialLocation,
    this.onStartVoice,
    this.onStopVoice,
    this.onRestartVoice,
    this.audioCaptureSilencedStream,
    this.voiceReconnectingStream,
    this.voiceReconnectErrorStream,
    this.voiceStateStream,
  });

  final ValueChanged<GoRouter>? onRouterReady;
  final WearFlowController? flowController;
  final Stream<WearVoiceCommand>? voiceCommandStream;
  final Stream<String>? voicePhraseStream;
  final List<RouteBase>? routes;
  final String? initialLocation;
  final Future<void> Function()? onStartVoice;
  final Future<void> Function()? onStopVoice;
  final Future<void> Function(String reason)? onRestartVoice;
  final Stream<bool>? audioCaptureSilencedStream;
  final Stream<bool>? voiceReconnectingStream;
  final Stream<String?>? voiceReconnectErrorStream;
  final Stream<VoiceState>? voiceStateStream;

  @override
  State<WearModuleApp> createState() => _WearModuleAppState();
}

class _WearModuleAppState extends State<WearModuleApp>
    with WidgetsBindingObserver {
  late final GoRouter _router;
  StreamSubscription<WearVoiceCommand>? _voiceSub;
  StreamSubscription<String>? _voicePhraseSub;
  StreamSubscription<WearFlowState>? _flowStateSub;
  StreamSubscription<dynamic>? _authorizedSub;
  StreamSubscription<void>? _clearedSub;
  StreamSubscription<bool>? _audioCaptureSilencedSub;
  StreamSubscription<Map<String, dynamic>>? _audioInputDeviceSub;
  StreamSubscription<Map<String, dynamic>>? _voiceCaptureDiagnosticsSub;
  StreamSubscription<bool>? _voiceReconnectingSub;
  StreamSubscription<String?>? _voiceReconnectErrorSub;
  StreamSubscription<VoiceState>? _voiceStateSub;
  Timer? _voiceHealthTimer;
  VoiceState _voiceState = const VoiceState.disabled();
  bool _voiceStartRequested = false;
  int? _voiceStartupToken;
  bool? _audioCaptureSilenced;
  bool _restartVoiceAfterInterruption = false;
  bool _appResumed = true;
  bool _wasActuallyBackgrounded = false;
  static int _nextVoiceOverlayRevision = 0;

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

  @override
  void initState() {
    super.initState();
    print('[VOICE-LIFECYCLE] WearModuleApp initState');
    WidgetsBinding.instance.addObserver(this);
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
        if (!_voiceState.acceptsCommands) {
          print(
            '[WearModuleApp] suppress voice command during reconnect '
            'command=$command',
          );
          return;
        }
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
        if (!_voiceState.acceptsCommands) {
          print('[WearModuleApp] suppress voice phrase during reconnect');
          return;
        }
        final int startedAt = DateTime.now().millisecondsSinceEpoch;
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
    _audioCaptureSilencedSub = (widget.audioCaptureSilencedStream ??
            MethodChannelService().audioCaptureSilencedStream)
        .listen(_onAudioCaptureSilencedChanged);
    _audioInputDeviceSub = MethodChannelService().audioInputDeviceStream.listen(
      (Map<String, dynamic> event) {
        final int? deviceId = event['deviceId'] as int?;
        final String? deviceName = event['deviceName'] as String?;
        final int? routeRevision = event['routeRevision'] as int?;
        if (deviceId == null || deviceName == null || routeRevision == null) {
          print('[WearModuleApp] ignored incomplete USB audio event=$event');
          return;
        }
        if (event['action'] == 'removed') {
          unawaited(WearVoiceSession.I.handleUsbInputRemoved(
            deviceId: deviceId,
            deviceName: deviceName,
            routeRevision: routeRevision,
          ));
        } else if (event['action'] == 'added') {
          unawaited(WearVoiceSession.I.handleUsbInputAdded(
            deviceId: deviceId,
            deviceName: deviceName,
            routeRevision: routeRevision,
          ));
        }
      },
    );
    _voiceCaptureDiagnosticsSub =
        MethodChannelService().voiceCaptureDiagnosticsStream.listen(
              WearVoiceSession.I.handleNativeCaptureDiagnostics,
            );
    _voiceReconnectingSub = widget.voiceReconnectingStream?.listen(
      (bool reconnecting) {
        _setVoiceState(_voiceState.copyWith(
          phase: reconnecting ? VoicePhase.reconnecting : VoicePhase.ready,
          reason: 'legacy_reconnecting_stream',
          lastTransitionAt: DateTime.now().millisecondsSinceEpoch,
          clearError: reconnecting,
        ));
      },
    );
    _voiceReconnectErrorSub = widget.voiceReconnectErrorStream?.listen(
      (String? error) {
        _setVoiceState(_voiceState.copyWith(
          phase: error == null ? VoicePhase.ready : VoicePhase.unavailable,
          reason: 'legacy_error_stream',
          lastTransitionAt: DateTime.now().millisecondsSinceEpoch,
          lastError: error,
          clearError: error == null,
        ));
      },
    );
    _voiceStateSub = (widget.voiceStateStream ??
            (widget.onStartVoice == null
                ? WearVoiceSession.I.stateStream
                : null))
        ?.listen(_onVoiceStateChanged);
    _flowStateSub = flow.stateStream.listen((WearFlowState state) {
      _configureVoiceForScreen(state.screen);
    });
    _configureVoiceForScreen(flow.state.screen);
    _authorizedSub = WearSession.authorizedStream.listen((_) {
      if (_voiceState.phase == VoicePhase.disabled) {
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
    if (_voiceState.phase == VoicePhase.disabled && WearSession.isAuthorized) {
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
    final pendingNavigation = flow.state.pendingNavigation;
    if (screenId != null &&
        pendingNavigation != null &&
        pendingNavigation.screen == screenId) {
      flow.acknowledgeNavigation(
        requestId: pendingNavigation.requestId,
        screen: screenId,
      );
    }
    if (screenId != null && screenId != flow.state.screen) {
      print('[ROUTER-CHANGE] enterScreen $screenId');
      flow.enterScreen(screenId, extra: _router.state.extra);
    }
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
    if (_voiceState.phase != VoicePhase.disabled || _voiceStartRequested) {
      print(
        '[WearModuleApp] voice start skipped source=$source '
        'phase=${_voiceState.phase.name} requested=$_voiceStartRequested',
      );
      return;
    }
    _voiceStartRequested = true;
    void start() {
      if (!mounted || !WearSession.isAuthorized) {
        _voiceStartRequested = false;
        return;
      }
      _voiceStartRequested = false;
      if (widget.onStartVoice != null) {
        _setVoiceState(VoiceState(
          phase: VoicePhase.loadingModel,
          captureEpoch: _voiceState.captureEpoch,
          attempt: _voiceState.attempt,
          reason: source,
          lastTransitionAt: DateTime.now().millisecondsSinceEpoch,
        ));
      }
      _voiceStartupToken = WearStatusIconReporter.I.beginVoiceStartup();
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

  Future<void> _runVoiceStart(String source) async {
    final Future<void> Function()? startVoice = widget.onStartVoice;
    final int? startupToken = _voiceStartupToken;
    try {
      if (startVoice != null) {
        await startVoice();
      } else {
        await WearVoiceSession.I.start();
      }
      if (!_isCurrentVoiceStartup(startupToken)) return;
      WearStatusIconReporter.I.endVoiceStartup(startupToken);
      if (startVoice != null) {
        _setVoiceState(VoiceState(
          phase: VoicePhase.ready,
          captureEpoch: _voiceState.captureEpoch,
          attempt: 0,
          reason: 'startup_complete',
          lastTransitionAt: DateTime.now().millisecondsSinceEpoch,
        ));
      }
      if (!WearSession.isAuthorized) {
        return;
      }
      _startVoiceHealthTimer();
      unawaited(_flow.renderCurrentGlasses());
    } catch (error, stackTrace) {
      print(
          '[WearModuleApp] voice start failed source=$source: $error\n$stackTrace');
      if (!_isCurrentVoiceStartup(startupToken)) return;
      WearStatusIconReporter.I.endVoiceStartup(startupToken);
      if (startVoice != null) {
        _setVoiceState(VoiceState(
          phase: VoicePhase.unavailable,
          captureEpoch: _voiceState.captureEpoch,
          attempt: _voiceState.attempt + 1,
          reason: 'startup_failed',
          lastError: error.toString(),
          lastTransitionAt: DateTime.now().millisecondsSinceEpoch,
        ));
      }
    }
  }

  void _startVoiceHealthTimer() {
    if (widget.onStartVoice != null) return;
    _voiceHealthTimer?.cancel();
    _voiceHealthTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!mounted ||
          !WearSession.isAuthorized ||
          !_appResumed ||
          _voiceState.phase != VoicePhase.ready) {
        return;
      }
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

  void _retryMicrophoneAfterReconnect() {
    unawaited(
      WearVoiceSession.I
          .start()
          .catchError((Object error, StackTrace stackTrace) {
        print(
          '[WearModuleApp] microphone retry failed: $error\n$stackTrace',
        );
      }),
    );
  }

  void _onVoiceStateChanged(VoiceState state) {
    _setVoiceState(state);
  }

  void _setVoiceState(VoiceState state) {
    if (!mounted) return;
    setState(() => _voiceState = state);
    _updateGlassesVoiceOverlay(
      visible: !state.acceptsCommands && state.phase != VoicePhase.disabled,
      message: switch (state.phase) {
        VoicePhase.loadingModel => 'Подготовка\nголосового управления',
        VoicePhase.startingRecorder => 'Запускаем\nмикрофон очков',
        VoicePhase.waitingForAudioRoute => 'Подключаем\nмикрофон очков',
        VoicePhase.reconnecting ||
        VoicePhase.suspendedBySystem =>
          'Переподключаем\nголосовое управление',
        VoicePhase.unavailable => 'Голосовое управление недоступно',
        VoicePhase.microphoneReconnectRequired =>
          'Переподключите\nочки или микрофон',
        VoicePhase.disabled || VoicePhase.ready => null,
      },
      phase: state.phase.name,
      reason: state.reason,
      attempt: state.attempt,
    );
  }

  void _updateGlassesVoiceOverlay({
    required bool visible,
    String? message,
    String phase = 'preparing',
    String reason = 'ui',
    int attempt = 0,
  }) {
    unawaited(
      MethodChannelService()
          .updateWearVoiceOverlay(
        visible: visible,
        phase: phase,
        reason: reason,
        attempt: attempt,
        revision: ++_nextVoiceOverlayRevision,
        message: message,
      )
          .catchError((Object error, StackTrace stackTrace) {
        print(
          '[WearModuleApp] update glasses voice overlay failed: '
          '$error\n$stackTrace',
        );
      }),
    );
  }

  void _onAudioCaptureSilencedChanged(bool silenced) {
    if (_audioCaptureSilenced == silenced) return;
    final bool wasSilenced = _audioCaptureSilenced == true;
    _audioCaptureSilenced = silenced;
    print('[WearModuleApp] audio capture silenced=$silenced');
    if (widget.onStartVoice == null) {
      WearVoiceSession.I.setCaptureSilenced(silenced);
      return;
    }
    if (silenced ||
        !wasSilenced ||
        _voiceState.phase == VoicePhase.disabled ||
        !WearSession.isAuthorized) {
      return;
    }

    Future<void>.delayed(const Duration(seconds: 1), () {
      if (!mounted ||
          !WearSession.isAuthorized ||
          _audioCaptureSilenced == true) {
        return;
      }
      _restartVoiceAfterInterruption = false;
      final Future<void> Function(String reason)? restartVoice =
          widget.onRestartVoice;
      if (restartVoice != null) {
        unawaited(
            _restartVoice(restartVoice, 'android_audio_capture_unsilenced'));
        return;
      }
      if (widget.onStartVoice != null) return;
      unawaited(
        WearVoiceSession.I.restart(
          reason: 'android_audio_capture_unsilenced',
        ),
      );
    });
  }

  Future<void> _restartVoice(
    Future<void> Function(String reason) restart,
    String reason,
  ) async {
    _setVoiceState(VoiceState(
      phase: VoicePhase.reconnecting,
      captureEpoch: _voiceState.captureEpoch + 1,
      attempt: _voiceState.attempt,
      reason: reason,
      lastTransitionAt: DateTime.now().millisecondsSinceEpoch,
    ));
    try {
      await restart(reason);
      _setVoiceState(VoiceState(
        phase: VoicePhase.ready,
        captureEpoch: _voiceState.captureEpoch,
        attempt: 0,
        reason: reason,
        lastTransitionAt: DateTime.now().millisecondsSinceEpoch,
      ));
    } catch (error) {
      _setVoiceState(VoiceState(
        phase: VoicePhase.unavailable,
        captureEpoch: _voiceState.captureEpoch,
        attempt: _voiceState.attempt + 1,
        reason: reason,
        lastError: error.toString(),
        lastTransitionAt: DateTime.now().millisecondsSinceEpoch,
      ));
    }
  }

  void _stopVoiceForLogout() {
    _voiceStartRequested = false;
    _setVoiceState(VoiceState(
      phase: VoicePhase.disabled,
      captureEpoch: _voiceState.captureEpoch,
      attempt: 0,
      reason: 'logout',
      lastTransitionAt: DateTime.now().millisecondsSinceEpoch,
    ));
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
      _appResumed = false;
      _wasActuallyBackgrounded = false;
      _voiceHealthTimer?.cancel();
      _voiceHealthTimer = null;
      _flow.setUiLifecycle(
        WearUiLifecycle.inactive,
      );
      _setVoiceState(VoiceState(
        phase: VoicePhase.disabled,
        captureEpoch: _voiceState.captureEpoch,
        attempt: 0,
        reason: 'app_lifecycle_detached',
        lastTransitionAt: DateTime.now().millisecondsSinceEpoch,
      ));
      final Future<void> Function()? stopVoice = widget.onStopVoice;
      if (stopVoice != null) {
        unawaited(stopVoice());
      } else {
        unawaited(WearVoiceSession.I.stop());
      }
      return;
    }
    if (state == AppLifecycleState.inactive) {
      // Temporary focus loss (dialogs, notification shade) is not background.
      return;
    }
    if (state == AppLifecycleState.resumed) {
      final bool resumeRecoveryRequired = _wasActuallyBackgrounded;
      _appResumed = true;
      _wasActuallyBackgrounded = false;
      _flow.setUiLifecycle(
        WearUiLifecycle.active,
      );
      if (WearSession.isAuthorized) {
        final Future<void> Function(String reason)? restartVoice =
            widget.onRestartVoice;
        if (resumeRecoveryRequired && restartVoice != null) {
          final String reason = _restartVoiceAfterInterruption
              ? 'app_lifecycle_resumed_after_interruption'
              : 'app_lifecycle_resumed';
          _restartVoiceAfterInterruption = false;
          unawaited(_restartVoice(restartVoice, reason));
        } else if (resumeRecoveryRequired &&
            WearVoiceSession.I.forceHardRestartOnResume &&
            _audioCaptureSilenced != true) {
          _restartVoiceAfterInterruption = false;
          unawaited(
            WearVoiceSession.I.restart(
              reason: 'app_lifecycle_resumed_after_interruption',
            ),
          );
        } else {
          _restartVoiceAfterInterruption = false;
          if (resumeRecoveryRequired && _audioCaptureSilenced != true) {
            unawaited(
              WearVoiceSession.I.ensureHealthy(
                reason: 'app_lifecycle_resumed',
              ),
            );
          }
          if (_voiceState.phase == VoicePhase.ready) {
            _startVoiceHealthTimer();
          }
        }
      }
      return;
    }
    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      _appResumed = false;
      _wasActuallyBackgrounded = true;
      _restartVoiceAfterInterruption = false;
      _voiceHealthTimer?.cancel();
      _voiceHealthTimer = null;
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
    _updateGlassesVoiceOverlay(visible: false);
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
    _audioCaptureSilencedSub?.cancel();
    _audioInputDeviceSub?.cancel();
    _voiceCaptureDiagnosticsSub?.cancel();
    _voiceReconnectingSub?.cancel();
    _voiceReconnectErrorSub?.cancel();
    _voiceStateSub?.cancel();
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
        if (!_voiceState.acceptsCommands) {
          print('[WearModuleApp] suppress system back during voice reconnect');
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
            (_voiceState.phase == VoicePhase.loadingModel ||
                _voiceState.phase == VoicePhase.startingRecorder ||
                _voiceState.phase == VoicePhase.waitingForAudioRoute ||
                _voiceState.phase == VoicePhase.unavailable ||
                _voiceState.phase == VoicePhase.microphoneReconnectRequired))
          Positioned.fill(
            child: _VoiceStartupOverlay(
              isError: _voiceState.phase == VoicePhase.unavailable ||
                  _voiceState.phase == VoicePhase.microphoneReconnectRequired,
              message: _voiceState.phase ==
                      VoicePhase.microphoneReconnectRequired
                  ? 'Переподключите очки или микрофон.\nПосле этого проверьте голос снова.'
                  : _voiceState.lastError,
              onRetry:
                  _voiceState.phase == VoicePhase.microphoneReconnectRequired
                      ? _retryMicrophoneAfterReconnect
                      : null,
            ),
          ),
        if (WearSession.isAuthorized &&
            (_voiceState.phase == VoicePhase.reconnecting ||
                _voiceState.phase == VoicePhase.suspendedBySystem))
          Positioned.fill(
            child: _VoiceStartupOverlay(
              isReconnecting: true,
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
    this.isError = false,
    this.message,
    this.isReconnecting = false,
    this.onRetry,
  });

  final bool isError;
  final String? message;
  final bool isReconnecting;
  final VoidCallback? onRetry;

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
                isError
                    ? message ?? 'Голосовое управление недоступно'
                    : isReconnecting
                        ? 'Переподключаем голосовое\nуправление'
                        : 'Подготовка голосового\nуправления',
                style: WearTypography.lable,
                textAlign: TextAlign.center,
              ),
              if (onRetry != null) ...<Widget>[
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: onRetry,
                  child: const Text('Проверить снова'),
                ),
              ],
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
