import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_glasses/core/services/method_channel_service.dart';
import 'package:smart_glasses/modules/wear/application/wear_flow_controller.dart';
import 'package:smart_glasses/modules/wear/application/wear_flow_state.dart';
import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/application/wear_ui_lifecycle.dart';
import 'package:smart_glasses/modules/wear/application/wear_voice_application_dispatcher.dart';
import 'package:smart_glasses/modules/wear/config/wear_dependencies.dart';
import 'package:smart_glasses/modules/wear/config/wear_session.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/wear_voice_command.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/wear_voice_command_event.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/wear_voice_phrase_event.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/wear_voice_preview_event.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/wear_voice_delay_event.dart';
import 'package:smart_glasses/modules/wear/infrastructure/flutter_wear_navigation_output.dart';
import 'package:smart_glasses/modules/wear/infrastructure/noop_wear_navigation_output.dart';
import 'package:smart_glasses/modules/wear/navigation/wear_routes.dart';
import 'package:smart_glasses/modules/wear/presentation/widgets/wear_loading.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_authority.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_control_adapter.dart';
import 'package:smart_glasses/modules/wear/services/wear_scanner_runtime_policy.dart';
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
    this.voiceCommandEventStream,
    this.voicePhraseStream,
    this.voicePhraseEventStream,
    this.voicePreviewEventStream,
    this.voiceDelayEventStream,
    this.routes,
    this.initialLocation,
    this.onStartVoice,
    this.onStopVoice,
    this.onRestartVoice,
    this.voiceReconnectingStream,
    this.voiceReconnectErrorStream,
    this.voiceStateStream,
  });

  final ValueChanged<GoRouter>? onRouterReady;
  final WearFlowController? flowController;
  final Stream<WearVoiceCommand>? voiceCommandStream;
  final Stream<WearVoiceCommandEvent>? voiceCommandEventStream;
  final Stream<String>? voicePhraseStream;
  final Stream<WearVoicePhraseEvent>? voicePhraseEventStream;
  final Stream<WearVoicePreviewEvent>? voicePreviewEventStream;
  final Stream<WearVoiceDelayEvent>? voiceDelayEventStream;
  final List<RouteBase>? routes;
  final String? initialLocation;
  final Future<void> Function()? onStartVoice;
  final Future<void> Function()? onStopVoice;
  final Future<void> Function(String reason)? onRestartVoice;
  final Stream<bool>? voiceReconnectingStream;
  final Stream<String?>? voiceReconnectErrorStream;
  final Stream<VoiceState>? voiceStateStream;

  @override
  State<WearModuleApp> createState() => _WearModuleAppState();
}

class _WearModuleAppState extends State<WearModuleApp>
    with WidgetsBindingObserver {
  late final GoRouter _router;
  late final WearVoiceApplicationDispatcher _voiceDispatcher;
  StreamSubscription<_VoiceCommandInput>? _voiceSub;
  StreamSubscription<_VoicePhraseInput>? _voicePhraseSub;
  StreamSubscription<WearVoicePreviewEvent>? _voicePreviewSub;
  StreamSubscription<WearVoiceDelayEvent>? _voiceDelaySub;
  StreamSubscription<WearScreenId>? _screenActionsSub;
  StreamSubscription<WearFlowState>? _flowStateSub;
  StreamSubscription<dynamic>? _authorizedSub;
  StreamSubscription<void>? _clearedSub;
  StreamSubscription<bool>? _voiceReconnectingSub;
  StreamSubscription<String?>? _voiceReconnectErrorSub;
  StreamSubscription<VoiceState>? _voiceStateSub;
  StreamSubscription<WearRuntimeState>? _controlStateSub;
  Timer? _voiceHealthTimer;
  VoiceState _voiceState = const VoiceState.disabled();
  bool _voiceStartRequested = false;
  late WearRuntimeControlAdapter _controlAdapter;
  int? _voiceStartupToken;
  bool _restartVoiceAfterInterruption = false;
  bool _wasActuallyBackgrounded = false;
  WearScreenId? _actualRouteScreen;
  int _routerObservationRevision = 0;
  int _scannerSyncGeneration = 0;
  int _wearControlServiceRequestGeneration = 0;
  bool _wearControlServiceEnabled = false;
  bool _runtimeTerminated = false;
  static int _nextVoiceOverlayRevision = 0;

  WearFlowController get _flow =>
      widget.flowController ?? WearDependencies.I.wearFlowController;

  Stream<_VoiceCommandInput> get _voiceCommands {
    final Stream<WearVoiceCommand>? stream = widget.voiceCommandStream;
    if (stream != null) {
      return stream.map(_VoiceCommandInput.withoutTrace);
    }
    final Stream<WearVoiceCommandEvent>? eventStream =
        widget.voiceCommandEventStream;
    if (eventStream != null) {
      return eventStream.map(_VoiceCommandInput.withTrace);
    }
    if (widget.onStartVoice != null) {
      return const Stream<_VoiceCommandInput>.empty();
    }
    return WearDependencies.I.voiceControlService.commandEventStream.map(
      _VoiceCommandInput.withTrace,
    );
  }

  Stream<_VoicePhraseInput> get _voicePhrases {
    final Stream<String>? stream = widget.voicePhraseStream;
    if (stream != null) return stream.map(_VoicePhraseInput.withoutContext);
    final eventStream = widget.voicePhraseEventStream;
    if (eventStream != null) {
      return eventStream.map(_VoicePhraseInput.withContext);
    }
    if (widget.onStartVoice != null) {
      return const Stream<_VoicePhraseInput>.empty();
    }
    return WearDependencies.I.voiceControlService.phraseEventStream
        .map(_VoicePhraseInput.withContext);
  }

  Stream<WearVoicePreviewEvent> get _voicePreviews {
    final Stream<WearVoicePreviewEvent>? stream =
        widget.voicePreviewEventStream;
    if (stream != null) return stream;
    if (widget.onStartVoice != null) {
      return const Stream<WearVoicePreviewEvent>.empty();
    }
    return WearDependencies.I.voiceControlService.previewEventStream;
  }

  Stream<WearVoiceDelayEvent> get _voiceDelays {
    final Stream<WearVoiceDelayEvent>? stream = widget.voiceDelayEventStream;
    if (stream != null) return stream;
    if (widget.onStartVoice != null) {
      return const Stream<WearVoiceDelayEvent>.empty();
    }
    return WearDependencies.I.voiceControlService.delayEventStream;
  }

  @override
  void initState() {
    super.initState();
    print('[VOICE-LIFECYCLE] WearModuleApp initState');
    MethodChannelService().setAppMethodCallHandler(_handleAppMethodCall);
    WidgetsBinding.instance.addObserver(this);
    final String initialLocation =
        widget.initialLocation ?? WearRoute.initialRoute;
    _router = GoRouter(
      initialLocation: initialLocation,
      routes: widget.routes ?? WearRoute.goRouteWear,
      observers: <NavigatorObserver>[
        _WearNavigatorObserver(),
      ],
    );
    _actualRouteScreen = FlutterWearNavigationOutput.screenIdForRoute(
      initialLocation,
    );
    widget.onRouterReady?.call(_router);
    final flow = _flow;
    _bindControlAdapter();
    _voiceDispatcher = WearVoiceApplicationDispatcher(
      flowController: flow,
      revisionSnapshotProvider: () {
        final speech = WearDependencies.I.speechRecognitionService;
        return (
          captureEpoch: speech.captureEpoch,
          recognitionContextId: speech.recognitionContextId,
          routeRevision: speech.routeRevision,
          grammarRevision: speech.grammarRevision,
          freeTextEpoch: speech.freeTextEpoch,
          commandUtteranceId: speech.commandUtteranceId,
          commandPartialRevision: speech.commandPartialRevision,
          freeTextPartialRevision: speech.freeTextPartialRevision,
        );
      },
      commandsEnabledProvider: () =>
          flow.authority.controls.voice.commandsEnabled,
      commandsEnabledSetter: _setVoiceCommandsEnabled,
      acceptsCommandsProvider: () =>
          flow.authority.controls.voice.acceptsCommands,
      onCommandAccepted: WearStatusIconReporter.I.beginPerformanceTrace,
      onPreviewUseful:
          widget.voicePreviewEventStream == null && widget.onStartVoice == null
              ? WearDependencies.I.voiceControlService.markPreviewUseful
              : null,
      log: print,
    );
    WearStatusIconReporter.I.start();
    WearStatusIconReporter.I.setVoiceCommandsEnabled(
      flow.authority.controls.voice.commandsEnabled,
    );
    _controlStateSub = flow.authority.states.listen((WearRuntimeState state) {
      final controls = state
          .payloadAs<WearAggregatePayload>()
          .controls as WearRuntimeControlPayload;
      WearStatusIconReporter.I.setVoiceCommandsEnabled(
        controls.voice.commandsEnabled,
      );
    });
    flow.setNavigationOutput(FlutterWearNavigationOutput(router: _router));
    flow.setRuntimeActive(true);
    flow.setUiLifecycle(WearUiLifecycle.active);
    if (widget.flowController == null) {
      if (WearSession.isAuthorized) {
        _startWearControlService('initial_authorized');
      }
      WearDependencies.I.barcodeDispatcher.start();
      _syncScannerForCurrentScreen();
    }
    _screenActionsSub =
        flow.screenActionsChanged.listen((WearScreenId screen) {
      if (screen == flow.state.screen) {
        _syncScannerForCurrentScreen();
        if (widget.onStartVoice == null) {
          _configureVoiceForScreen(screen, force: true);
        }
      }
    });
    WearScreenId logicalScreen = flow.state.screen;
    _flowStateSub = flow.stateStream.listen((WearFlowState state) {
      if (state.screen == logicalScreen) return;
      logicalScreen = state.screen;
      _syncScannerForCurrentScreen();
      if (widget.onStartVoice == null) {
        _configureVoiceForScreen(state.screen);
      }
    });
    _voiceSub = _voiceCommands.listen(
      (_VoiceCommandInput input) {
        if (_runtimeTerminated) return;
        _observeVoiceDispatch(
          _voiceDispatcher.dispatchCommand(
            input.command,
            event: input.event,
          ),
          'command',
        );
      },
      onError: (Object error, StackTrace stackTrace) {
        print('[WearModuleApp] voice command stream error=$error\n$stackTrace');
      },
    );
    _voicePhraseSub = _voicePhrases.listen(
      (_VoicePhraseInput input) {
        if (_runtimeTerminated) return;
        _observeVoiceDispatch(
          _voiceDispatcher.dispatchPhrase(
            input.phrase,
            event: input.event,
          ),
          'phrase',
        );
      },
      onError: (Object error, StackTrace stackTrace) {
        print('[WearModuleApp] voice phrase stream error=$error\n$stackTrace');
      },
    );
    _voicePreviewSub = _voicePreviews.listen(
      (WearVoicePreviewEvent event) {
        if (_runtimeTerminated) return;
        _observeVoiceDispatch(
          _voiceDispatcher.dispatchPreview(event),
          'preview',
        );
      },
      onError: (Object error, StackTrace stackTrace) {
        print('[WearModuleApp] voice preview stream error=$error\n$stackTrace');
      },
    );
    _voiceDelaySub = _voiceDelays.listen((WearVoiceDelayEvent event) {
      if (_runtimeTerminated) return;
      _observeVoiceDispatch(
        _voiceDispatcher.dispatchDelay(event),
        'delay',
      );
    });
    _voiceReconnectingSub = widget.voiceReconnectingStream?.listen(
      (bool reconnecting) {
        if (_runtimeTerminated) return;
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
        if (_runtimeTerminated) return;
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
    _authorizedSub = WearSession.authorizedStream.listen((_) {
      if (_runtimeTerminated) return;
      _bindControlAdapter();
      flow.setRuntimeActive(true);
      if (widget.flowController == null) {
        _startWearControlService('authorized');
        WearDependencies.I.barcodeDispatcher.start();
        _syncScannerForCurrentScreen();
      }
      if (_voiceState.phase == VoicePhase.disabled) {
        _startVoice('authorized');
      }
    });
    _clearedSub = WearSession.clearedStream.listen((_) {
      if (_runtimeTerminated) return;
      _bindControlAdapter();
      _voiceDispatcher.resetAdmission();
      flow.resetSessionState();
      if (widget.flowController == null) {
        WearDependencies.I.barcodeDispatcher.stop();
        WearDependencies.I.barcodeDispatcher.start();
        _syncScannerForCurrentScreen();
      }
      _stopVoiceForLogout();
    });
    _router.routerDelegate.addListener(_onRouterChange);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_runtimeTerminated || !WearSession.isAuthorized) {
        print('[WearModuleApp] post-frame voice start skipped');
        return;
      }
      _startVoice('post-frame');
    });
  }

  void _syncScannerForCurrentScreen({WearScreenId? routeScreen}) {
    if (widget.flowController != null) return;
    if (routeScreen != null) _actualRouteScreen = routeScreen;
    WearDependencies.I.barcodeDispatcher.resetPending();
    final WearRuntimeControlAdapter callback = _controlAdapter;
    final int generation = ++_scannerSyncGeneration;
    final WearScreenId logicalScreen = _flow.state.screen;
    final WearScannerRuntimeDecision decision =
        resolveWearScannerDecisionFromState(
      _flow.authority.state,
      currentScreenAcceptsBarcode: _flow.currentScreenAcceptsBarcode,
    );
    unawaited(_applyScannerDecision(
      callback: callback,
      generation: generation,
      logicalScreen: logicalScreen,
      screenAcceptsBarcode: _flow.currentScreenAcceptsBarcode,
      decision: decision,
    ));
  }

  Future<void> _applyScannerDecision({
    required WearRuntimeControlAdapter callback,
    required int generation,
    required WearScreenId logicalScreen,
    required bool screenAcceptsBarcode,
    required WearScannerRuntimeDecision decision,
  }) async {
    try {
      if (decision.hardwarePrepared) {
        await callback.observeScannerPreparing();
        await WearDependencies.I.scannerRuntime.start();
        if (generation != _scannerSyncGeneration) return;
        await callback.observeScannerPrepared();
      } else {
        await callback.observeScannerPausing();
        await WearDependencies.I.scannerRuntime.pause();
        if (generation != _scannerSyncGeneration) return;
        await callback.observeScannerReleased();
      }
      if (generation != _scannerSyncGeneration) return;
      await callback.evaluateScannerAdmission(
        logicalScreen: logicalScreen,
        screenAcceptsBarcode: screenAcceptsBarcode,
      );
    } catch (error, stackTrace) {
      if (generation != _scannerSyncGeneration) return;
      await callback.observeScannerError(error);
      print(
        '[WearModuleApp] scanner runtime sync failed '
        'screen=$logicalScreen admission=${decision.barcodeAdmissionEnabled} '
        'prepare=${decision.hardwarePrepared}: $error\n$stackTrace',
      );
    }
  }

  void _observeVoiceDispatch<T>(Future<T> operation, String kind) {
    if (_runtimeTerminated) return;
    unawaited(operation.then<void>(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {
        print(
          '[WearModuleApp] voice $kind dispatch error='
          '$error\n$stackTrace',
        );
      },
    ));
  }

  Future<void> _handleAppMethodCall(MethodCall call) async {
    if (call.method != 'wearButtonCommand' ||
        _runtimeTerminated ||
        !mounted ||
        !WearSession.isAuthorized ||
        (widget.flowController == null && !_wearControlServiceEnabled)) {
      return;
    }
    final WearVoiceCommand? command = switch (call.arguments) {
      'up' => WearVoiceCommand.up,
      'down' => WearVoiceCommand.down,
      'enter' => WearVoiceCommand.select,
      _ => null,
    };
    if (command != null) {
      await _flow.handleControllerCommand(command);
    }
  }

  void _onRouterChange() {
    if (_runtimeTerminated) return;
    final int observationRevision = ++_routerObservationRevision;
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
    if (screenId != null) {
      _syncScannerForCurrentScreen(routeScreen: screenId);
      if (widget.onStartVoice == null) {
        unawaited(WearDependencies.I.actualScreenStore.confirm(screenId));
      }
      if (screenId == flow.state.screen) {
        _configureVoiceForScreen(screenId);
      } else {
        print(
          '[VOICE-ROUTE] skip stale route configuration '
          'routeScreen=$screenId logicalScreen=${flow.state.screen}',
        );
      }
    }
    final pendingNavigation = flow.state.pendingNavigation;
    if (screenId != null &&
        pendingNavigation != null &&
        pendingNavigation.screen == screenId) {
      flow.acknowledgeNavigation(
        requestId: pendingNavigation.requestId,
        screen: screenId,
      );
    }
    if (screenId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_runtimeTerminated ||
            !mounted ||
            observationRevision != _routerObservationRevision) {
          return;
        }
        final WearScreenId? confirmedScreen =
            FlutterWearNavigationOutput.screenIdForRoute(
          _router.state.matchedLocation,
        );
        if (confirmedScreen == null) return;
        print('[ROUTER-CHANGE] observeRoute $confirmedScreen');
        flow.observeRoute(
          confirmedScreen,
          extra: _router.state.extra,
          canPop: _router.canPop(),
        );
      });
    }
  }

  void _configureVoiceForScreen(
    WearScreenId screen, {
    bool force = false,
  }) {
    if (_runtimeTerminated || widget.onStartVoice != null) return;
    WearVoiceSession.I.configureForScreen(screen, force: force).catchError(
      (Object error, StackTrace stackTrace) {
        print(
          '[WearModuleApp] configure voice failed screen=$screen '
          'error=$error\n$stackTrace',
        );
      },
    );
  }

  void _startVoice(String source) {
    if (_runtimeTerminated ||
        _voiceState.phase != VoicePhase.disabled ||
        _voiceStartRequested) {
      print(
        '[WearModuleApp] voice start skipped source=$source '
        'phase=${_voiceState.phase.name} requested=$_voiceStartRequested',
      );
      return;
    }
    _voiceStartRequested = true;
    void start() {
      if (_runtimeTerminated || !mounted || !WearSession.isAuthorized) {
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
    if (_runtimeTerminated || widget.onStartVoice != null) return;
    _voiceHealthTimer?.cancel();
    _voiceHealthTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (_runtimeTerminated ||
          !mounted ||
          !WearSession.isAuthorized ||
          _voiceState.phase != VoicePhase.ready) {
        return;
      }
      _ensureVoiceHealthy('periodic_voice_health');
    });
  }

  void _ensureVoiceHealthy(String reason) {
    if (_runtimeTerminated) return;
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
    if (_runtimeTerminated) return;
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
    if (_runtimeTerminated) return;
    _setVoiceState(state);
  }

  void _setVoiceState(VoiceState state) {
    if (!mounted) return;
    setState(() => _voiceState = state);
    final WearRuntimeControlAdapter callback = _controlAdapter;
    _observeVoiceDispatch(callback.observeVoiceState(state), 'state');
    _updateGlassesVoiceOverlay(
      visible: !state.acceptsCommands && state.phase != VoicePhase.disabled,
      message: switch (state.phase) {
        VoicePhase.loadingModel => 'Подготовка\nголосового управления',
        VoicePhase.startingRecorder => 'Настраиваем\nмикрофон очков',
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

  void _setVoiceCommandsEnabled(bool enabled) {
    if (_runtimeTerminated ||
        _flow.authority.controls.voice.commandsEnabled == enabled) {
      return;
    }
    final WearRuntimeControlAdapter callback = _controlAdapter;
    _observeVoiceDispatch(
      callback.observeVoiceState(_voiceState, commandsEnabled: enabled),
      'admission',
    );
    print('[WearModuleApp] voice commands enabled=$enabled');
  }

  void _bindControlAdapter() {
    final WearRuntimeControlAdapter callback =
        WearRuntimeControlAdapter(_flow.authority);
    _controlAdapter = callback;
    WearStatusIconReporter.I.setConnectivityObserver((status) async {
      await callback.observeConnectivity(
        status.isAvailable
            ? WearConnectivityPhase.online
            : WearConnectivityPhase.offline,
      );
    });
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

  Future<void> _restartVoice(
    Future<void> Function(String reason) restart,
    String reason,
  ) async {
    if (_runtimeTerminated) return;
    _setVoiceState(VoiceState(
      phase: VoicePhase.reconnecting,
      captureEpoch: _voiceState.captureEpoch + 1,
      attempt: _voiceState.attempt,
      reason: reason,
      lastTransitionAt: DateTime.now().millisecondsSinceEpoch,
    ));
    try {
      await restart(reason);
      if (_runtimeTerminated) return;
      _setVoiceState(VoiceState(
        phase: VoicePhase.ready,
        captureEpoch: _voiceState.captureEpoch,
        attempt: 0,
        reason: reason,
        lastTransitionAt: DateTime.now().millisecondsSinceEpoch,
      ));
    } catch (error) {
      if (_runtimeTerminated) return;
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

  void _startWearControlService(String reason) {
    if (_runtimeTerminated ||
        widget.flowController != null ||
        !mounted ||
        !WearSession.isAuthorized) {
      return;
    }
    _wearControlServiceEnabled = true;
    final int generation = ++_wearControlServiceRequestGeneration;
    unawaited(
      MethodChannelService().startWearControlService().catchError(
        (Object error, StackTrace stackTrace) {
          if (generation == _wearControlServiceRequestGeneration) {
            _wearControlServiceEnabled = false;
          }
          print(
            '[WearModuleApp] foreground service start failed '
            'reason=$reason: $error\n$stackTrace',
          );
        },
      ),
    );
  }

  void _stopWearControlService(String reason) {
    if (widget.flowController != null) return;
    _wearControlServiceEnabled = false;
    _wearControlServiceRequestGeneration += 1;
    unawaited(
      MethodChannelService().stopWearControlService().catchError(
            (Object error, StackTrace stackTrace) => print(
              '[WearModuleApp] foreground service stop failed '
              'reason=$reason: $error\n$stackTrace',
            ),
          ),
    );
  }

  void _stopVoiceForLogout() {
    _stopWearControlService('logout');
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
    WearStatusIconReporter.I.setConnectivityObserver(null);
    final Future<void> Function()? stopVoice = widget.onStopVoice;
    if (stopVoice != null) {
      unawaited(stopVoice());
    } else {
      unawaited(WearVoiceSession.I.stop());
    }
  }

  bool _isCurrentVoiceStartup(int? token) {
    return !_runtimeTerminated &&
        mounted &&
        token != null &&
        token == _voiceStartupToken;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_runtimeTerminated) return;
    print('[WearModuleApp] lifecycle state=$state');
    if (state == AppLifecycleState.detached) {
      _runtimeTerminated = true;
      _routerObservationRevision += 1;
      _stopWearControlService('app_lifecycle_detached');
      _wasActuallyBackgrounded = false;
      _voiceStartRequested = false;
      _voiceHealthTimer?.cancel();
      _voiceHealthTimer = null;
      WearStatusIconReporter.I.endVoiceStartup(_voiceStartupToken);
      _voiceStartupToken = null;
      _flow.setUiLifecycle(
        WearUiLifecycle.inactive,
      );
      _flow.setRuntimeActive(false);
      unawaited(_flow.authority.terminate());
      if (widget.flowController == null) {
        WearDependencies.I.barcodeDispatcher.stop();
        unawaited(WearDependencies.I.scannerRuntime.release());
      }
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
      _wasActuallyBackgrounded = false;
      _flow.setUiLifecycle(
        WearUiLifecycle.active,
      );
      _syncScannerForCurrentScreen();
      if (WearSession.isAuthorized) {
        _startWearControlService('resumed');
        final Future<void> Function(String reason)? restartVoice =
            widget.onRestartVoice;
        if (resumeRecoveryRequired && restartVoice != null) {
          final String reason = _restartVoiceAfterInterruption
              ? 'app_lifecycle_resumed_after_interruption'
              : 'app_lifecycle_resumed';
          _restartVoiceAfterInterruption = false;
          unawaited(_restartVoice(restartVoice, reason));
        } else if (resumeRecoveryRequired &&
            WearVoiceSession.I.forceHardRestartOnResume) {
          _restartVoiceAfterInterruption = false;
          unawaited(
            WearVoiceSession.I.restart(
              reason: 'app_lifecycle_resumed_after_interruption',
            ),
          );
        } else {
          _restartVoiceAfterInterruption = false;
          if (resumeRecoveryRequired) {
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
      _wasActuallyBackgrounded = true;
      _restartVoiceAfterInterruption = false;
    }
    _flow.setUiLifecycle(
      WearUiLifecycle.inactive,
    );
    _syncScannerForCurrentScreen();
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
    _runtimeTerminated = true;
    _routerObservationRevision += 1;
    _stopWearControlService('dispose');
    _flow.setRuntimeActive(false);
    if (widget.flowController == null) {
      WearDependencies.I.barcodeDispatcher.stop();
      unawaited(
        WearDependencies.I.scannerRuntime.pause().catchError(
              (Object error, StackTrace stackTrace) => print(
                '[WearModuleApp] scanner runtime pause failed: '
                '$error\n$stackTrace',
              ),
            ),
      );
    }
    MethodChannelService().setAppMethodCallHandler(null);
    _updateGlassesVoiceOverlay(visible: false);
    WearStatusIconReporter.I.endVoiceStartup(_voiceStartupToken);
    _voiceStartupToken = null;
    WearStatusIconReporter.I.setConnectivityObserver(null);
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
    _voicePreviewSub?.cancel();
    _voiceDelaySub?.cancel();
    _voiceReconnectingSub?.cancel();
    _voiceReconnectErrorSub?.cancel();
    _voiceStateSub?.cancel();
    _controlStateSub?.cancel();
    _screenActionsSub?.cancel();
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
        if (!_flow.authority.controls.voice.acceptsCommands) {
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

class _VoiceCommandInput {
  const _VoiceCommandInput(this.command, this.event);

  factory _VoiceCommandInput.withoutTrace(WearVoiceCommand command) {
    return _VoiceCommandInput(command, null);
  }

  factory _VoiceCommandInput.withTrace(WearVoiceCommandEvent event) {
    return _VoiceCommandInput(event.command, event);
  }

  final WearVoiceCommand command;
  final WearVoiceCommandEvent? event;
}

class _VoicePhraseInput {
  const _VoicePhraseInput(this.phrase, this.event);

  factory _VoicePhraseInput.withoutContext(String phrase) {
    return _VoicePhraseInput(phrase, null);
  }

  factory _VoicePhraseInput.withContext(WearVoicePhraseEvent event) {
    return _VoicePhraseInput(event.phrase, event);
  }

  final String phrase;
  final WearVoicePhraseEvent? event;
}
