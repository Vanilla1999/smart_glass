import 'dart:async';

import 'package:smart_glasses/modules/wear/config/wear_session.dart';
import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/config/wear_dependencies.dart';
import 'package:smart_glasses/modules/wear/presentation/glasses/wear_glasses_bridge.dart';
import 'package:smart_glasses/modules/wear/presentation/glasses/wear_glasses_payload.dart';
import 'package:smart_glasses/modules/wear/services/wear_printer_status_service.dart';
import 'package:smart_glasses/modules/wear/services/wear_wifi_status_service.dart';

class WearStatusIconSnapshot {
  const WearStatusIconSnapshot({
    required this.wifi,
    required this.showPrinter,
    required this.printerAvailable,
  });

  final WearWifiStatus wifi;
  final bool showPrinter;
  final bool printerAvailable;
}

class WearStatusIconReporter {
  WearStatusIconReporter._();

  static final WearStatusIconReporter I = WearStatusIconReporter._();
  static const Duration _projectionTimeout = Duration(seconds: 6);

  final WearWifiStatusService _wifiStatusService =
      const WearWifiStatusService();
  final WearPrinterStatusService _printerStatusService =
      const WearPrinterStatusService();

  WearStatusIconSnapshot _snapshot = const WearStatusIconSnapshot(
    wifi: WearWifiStatus(isAvailable: false, level: 3),
    showPrinter: false,
    printerAvailable: false,
  );
  WearGlassesPayload? _lastPayload;
  Timer? _timer;
  Timer? _transientTimer;
  int _payloadGeneration = 0;
  int _lifecycleGeneration = 0;
  int _voiceStartupGeneration = 0;
  Future<void> _projectionOperation = Future<void>.value();
  bool _wasWifiAvailable = true;
  bool _wasPrinterAvailable = true;
  bool _voiceStartupActive = false;
  bool _projectionVisible = false;
  WearScreenId Function()? _currentScreenForTesting;
  Future<WearStatusIconSnapshot> Function()? _refreshForTesting;

  WearStatusIconSnapshot get snapshot => _snapshot;
  WearGlassesPayload? get lastPayload => _lastPayload;

  void debugSetCurrentScreenProviderForTesting(
    WearScreenId Function()? currentScreen,
  ) {
    _currentScreenForTesting = currentScreen;
  }

  void debugSetRefreshForTesting(
    Future<WearStatusIconSnapshot> Function()? refresh,
  ) {
    _refreshForTesting = refresh;
  }

  int beginVoiceStartup() {
    _voiceStartupActive = true;
    return ++_voiceStartupGeneration;
  }

  void endVoiceStartup([int? generation]) {
    if (generation != null && generation != _voiceStartupGeneration) return;
    _voiceStartupActive = false;
    if (generation == null) {
      _voiceStartupGeneration++;
    }
  }

  void start() {
    _lifecycleGeneration++;
    _timer ??= Timer.periodic(
      const Duration(seconds: 2),
      (_) => unawaited(
        refreshAndResend().catchError((Object error, StackTrace stackTrace) {
          print(
            '[WearStatusIconReporter] periodic refresh failed: '
            '$error\n$stackTrace',
          );
        }),
      ),
    );
    unawaited(
      refreshAndResend().catchError((Object error, StackTrace stackTrace) {
        print(
            '[WearStatusIconReporter] initial refresh failed: $error\n$stackTrace');
      }),
    );
  }

  Future<void> stop() async {
    _lifecycleGeneration++;
    _timer?.cancel();
    _timer = null;
    _transientTimer?.cancel();
    _transientTimer = null;
    _voiceStartupActive = false;
    _projectionVisible = false;
    _lastPayload = null;
    _payloadGeneration++;
    _wasWifiAvailable = true;
    _wasPrinterAvailable = true;
    if (!wearGlassesBridge.isEnabled) {
      _projectionOperation = Future<void>.value();
      return;
    }
    final Future<void> hideOperation = _projectionOperation.then((_) async {
      try {
        await wearGlassesBridge.hide().timeout(_projectionTimeout);
      } catch (error, stackTrace) {
        print('[WearStatusIconReporter] hide failed: $error\n$stackTrace');
      }
    });
    _projectionOperation = hideOperation;
    await hideOperation;
  }

  Future<WearStatusIconSnapshot> refresh({int? expectedGeneration}) async {
    final Future<WearStatusIconSnapshot> Function()? refreshForTesting =
        _refreshForTesting;
    final WearStatusIconSnapshot next;
    if (refreshForTesting != null) {
      next = await refreshForTesting();
    } else {
      final WearWifiStatus wifi = await _wifiStatusService.getStatus();
      final bool showPrinter = WearSession.hasPrinterSelection;
      final bool printerAvailable = showPrinter &&
          WearSession.isAuthorized &&
          await _printerStatusService.isSelectedPrinterAvailable();
      next = WearStatusIconSnapshot(
        wifi: wifi,
        showPrinter: showPrinter,
        printerAvailable: printerAvailable,
      );
    }
    if (expectedGeneration != null &&
        expectedGeneration != _lifecycleGeneration) {
      return _snapshot;
    }
    _snapshot = next;
    _openSettingsIfNeeded(_snapshot);
    return _snapshot;
  }

  void _openSettingsIfNeeded(WearStatusIconSnapshot snapshot) {
    final WearScreenId Function()? currentScreenForTesting =
        _currentScreenForTesting;
    final WearScreenId current = currentScreenForTesting?.call() ??
        WearDependencies.I.wearFlowController.state.screen;
    final bool onWifiSettingsScreen = current == WearScreenId.wifiSettings;
    final bool onPrinterSettingsScreen =
        current == WearScreenId.printerSettings;

    if (currentScreenForTesting == null &&
        !snapshot.wifi.isAvailable &&
        _wasWifiAvailable &&
        !onWifiSettingsScreen) {
      unawaited(
        WearDependencies.I.wearFlowController.requestNavigation(
          WearScreenId.wifiSettings,
        ),
      );
    }

    if (currentScreenForTesting == null &&
        snapshot.showPrinter &&
        !snapshot.printerAvailable &&
        _wasPrinterAvailable &&
        snapshot.wifi.isAvailable &&
        !onWifiSettingsScreen &&
        !onPrinterSettingsScreen) {
      unawaited(
        WearDependencies.I.wearFlowController.requestNavigation(
          WearScreenId.printerSettings,
        ),
      );
    }

    _wasWifiAvailable = snapshot.wifi.isAvailable;
    _wasPrinterAvailable = !snapshot.showPrinter || snapshot.printerAvailable;
  }

  Future<void> send(WearGlassesPayload payload) async {
    final int lifecycleGeneration = _lifecycleGeneration;
    if (_shouldDeferForVoiceStartup(payload)) return;
    final int payloadGeneration = _beginPayloadUpdate();
    final WearStatusIconSnapshot snapshot = await refresh(
      expectedGeneration: lifecycleGeneration,
    );
    if (!_isCurrentOperation(lifecycleGeneration, payloadGeneration)) return;
    if (_shouldDeferForVoiceStartup(payload)) return;
    final WearGlassesPayload next = _withSnapshot(payload, snapshot);
    _commitPayload(next, payloadGeneration);
    await _sendToProjection(next, lifecycleGeneration, payloadGeneration);
  }

  Future<void> sendForScreen(
    WearScreenId screen,
    WearGlassesPayload payload,
  ) async {
    final int lifecycleGeneration = _lifecycleGeneration;
    if (_shouldDeferForVoiceStartup(payload)) return;
    if (!_isCurrentScreen(screen)) return;
    final int payloadGeneration = _beginPayloadUpdate();
    final WearStatusIconSnapshot snapshot = await refresh(
      expectedGeneration: lifecycleGeneration,
    );
    if (!_isCurrentOperation(lifecycleGeneration, payloadGeneration)) return;
    if (_shouldDeferForVoiceStartup(payload)) return;
    if (!_isCurrentScreen(screen)) return;
    final WearGlassesPayload next = _withSnapshot(payload, snapshot);
    _commitPayload(next, payloadGeneration);
    await _sendToProjection(next, lifecycleGeneration, payloadGeneration);
  }

  Future<void> sendFast(WearGlassesPayload payload) async {
    if (_shouldDeferForVoiceStartup(payload)) return;
    final int lifecycleGeneration = _lifecycleGeneration;
    final int payloadGeneration = _beginPayloadUpdate();
    final WearGlassesPayload next = _withSnapshot(payload, _snapshot);
    _commitPayload(next, payloadGeneration);
    await _sendToProjection(next, lifecycleGeneration, payloadGeneration);
  }

  Future<void> sendFastForScreen(
    WearScreenId screen,
    WearGlassesPayload payload,
  ) async {
    if (_shouldDeferForVoiceStartup(payload)) return;
    if (!_isCurrentScreen(screen)) return;
    final int lifecycleGeneration = _lifecycleGeneration;
    final int payloadGeneration = _beginPayloadUpdate();
    final WearGlassesPayload next = _withSnapshot(payload, _snapshot);
    _commitPayload(next, payloadGeneration);
    await _sendToProjection(next, lifecycleGeneration, payloadGeneration);
  }

  Future<void> sendTransientFast(WearGlassesPayload payload) async {
    if (_shouldDeferForVoiceStartup(payload)) return;
    final int lifecycleGeneration = _lifecycleGeneration;
    final int payloadGeneration = _payloadGeneration;
    final WearGlassesPayload next = _withSnapshot(payload, _snapshot);
    await _sendToProjection(next, lifecycleGeneration, payloadGeneration);
  }

  Future<void> showTransientFastForScreen(
    WearScreenId screen,
    WearGlassesPayload payload, {
    Duration duration = const Duration(seconds: 3),
  }) async {
    final int lifecycleGeneration = _lifecycleGeneration;
    if (_shouldDeferForVoiceStartup(payload)) return;
    if (!_isCurrentScreen(screen)) return;
    _transientTimer?.cancel();
    final WearGlassesPayload? restorePayload = _lastPayload;
    final int restoreGeneration = _payloadGeneration;
    await sendTransientFast(payload);
    if (lifecycleGeneration != _lifecycleGeneration) return;
    _transientTimer = Timer(duration, () {
      if (restorePayload == null ||
          restoreGeneration != _payloadGeneration ||
          !_isCurrentScreen(screen)) {
        return;
      }
      unawaited(sendFastForScreen(screen, restorePayload));
    });
  }

  Future<void> show(WearGlassesPayload payload) async {
    final int lifecycleGeneration = _lifecycleGeneration;
    if (_shouldDeferForVoiceStartup(payload)) return;
    final int payloadGeneration = _beginPayloadUpdate();
    final WearStatusIconSnapshot snapshot = await refresh(
      expectedGeneration: lifecycleGeneration,
    );
    if (!_isCurrentOperation(lifecycleGeneration, payloadGeneration)) return;
    if (_shouldDeferForVoiceStartup(payload)) return;
    final WearGlassesPayload next = _withSnapshot(payload, snapshot);
    _commitPayload(next, payloadGeneration);
    await _sendToProjection(next, lifecycleGeneration, payloadGeneration);
  }

  Future<void> refreshAndResend() async {
    final int lifecycleGeneration = _lifecycleGeneration;
    final WearGlassesPayload? payload = _lastPayload;
    final int payloadGeneration = _payloadGeneration;
    if (payload == null) {
      await refresh(expectedGeneration: lifecycleGeneration);
      return;
    }
    if (_voiceStartupActive) return;

    final WearStatusIconSnapshot previous = _snapshot;
    final WearStatusIconSnapshot next = await refresh(
      expectedGeneration: lifecycleGeneration,
    );
    if (!_isCurrentOperation(lifecycleGeneration, payloadGeneration)) return;
    if (previous.wifi == next.wifi &&
        previous.showPrinter == next.showPrinter &&
        previous.printerAvailable == next.printerAvailable) {
      return;
    }

    final WearGlassesPayload updated = _withSnapshot(payload, next);
    final int nextPayloadGeneration = _beginPayloadUpdate();
    _commitPayload(updated, nextPayloadGeneration);
    await _sendToProjection(
      updated,
      lifecycleGeneration,
      nextPayloadGeneration,
    );
  }

  WearGlassesPayload _withSnapshot(
    WearGlassesPayload payload,
    WearStatusIconSnapshot snapshot,
  ) {
    return payload.copyWithStatusIcons(
      showWifiIcon: payload.showWifiIcon,
      wifiAvailable: snapshot.wifi.isAvailable,
      wifiLevel: snapshot.wifi.level,
      showPrinterIcon: snapshot.showPrinter,
      printerAvailable: snapshot.printerAvailable,
    );
  }

  bool _isCurrentScreen(WearScreenId screen) {
    final WearScreenId Function()? currentScreen = _currentScreenForTesting;
    if (currentScreen != null) {
      return currentScreen() == screen;
    }
    return WearDependencies.I.wearFlowController.state.screen == screen;
  }

  int _beginPayloadUpdate() {
    _transientTimer?.cancel();
    _transientTimer = null;
    return ++_payloadGeneration;
  }

  void _commitPayload(WearGlassesPayload payload, int generation) {
    if (generation == _payloadGeneration) {
      _lastPayload = payload;
    }
  }

  bool _isCurrentOperation(int lifecycleGeneration, int payloadGeneration) {
    return lifecycleGeneration == _lifecycleGeneration &&
        payloadGeneration == _payloadGeneration;
  }

  Future<void> _sendToProjection(
    WearGlassesPayload payload,
    int lifecycleGeneration,
    int payloadGeneration,
  ) {
    if (!wearGlassesBridge.isEnabled) return Future<void>.value();
    final Future<void> next = _projectionOperation.then((_) async {
      if (!_isCurrentOperation(lifecycleGeneration, payloadGeneration)) return;
      try {
        if (_projectionVisible) {
          await wearGlassesBridge.update(payload).timeout(_projectionTimeout);
        } else {
          await wearGlassesBridge.show(payload).timeout(_projectionTimeout);
        }
        if (_isCurrentOperation(lifecycleGeneration, payloadGeneration)) {
          _projectionVisible = true;
        }
      } catch (error, stackTrace) {
        _projectionVisible = false;
        print(
          '[WearStatusIconReporter] projection send failed: '
          '$error\n$stackTrace',
        );
      }
    });
    _projectionOperation = next.catchError(
      (Object error, StackTrace stackTrace) {
        print(
          '[WearStatusIconReporter] projection queue failed: '
          '$error\n$stackTrace',
        );
      },
    );
    return _projectionOperation;
  }

  bool _shouldDeferForVoiceStartup(WearGlassesPayload payload) {
    return _voiceStartupActive && !_isVoiceStartupPayload(payload);
  }

  bool _isVoiceStartupPayload(WearGlassesPayload payload) {
    return payload.screenType == WearGlassesScreenType.status &&
        payload.phase == WearGlassesPhase.loading &&
        payload.title == 'Голосовое управление' &&
        payload.statusText == 'Запускаем голос...';
  }
}
