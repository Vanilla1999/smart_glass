import 'dart:async';

import 'package:smart_glasses/modules/wear/domain/service/voice_command/wear_voice_command_event.dart';

import 'package:flutter/foundation.dart';

import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/config/wear_dependencies.dart';
import 'package:smart_glasses/modules/wear/services/wear_printer_status_service.dart';
import 'package:smart_glasses/modules/wear/services/wear_wifi_status_service.dart';

class WearStatusIconSnapshot {
  const WearStatusIconSnapshot({
    required this.wifi,
    required this.showPrinter,
    required this.printerAvailable,
    this.voiceCommandsEnabled = true,
  });

  final WearWifiStatus wifi;
  final bool showPrinter;
  final bool printerAvailable;
  final bool voiceCommandsEnabled;
}

class WearStatusIconReporter {
  WearStatusIconReporter._();

  static final WearStatusIconReporter I = WearStatusIconReporter._();
  final WearWifiStatusService _wifiStatusService =
      const WearWifiStatusService();
  final WearPrinterStatusService _printerStatusService =
      const WearPrinterStatusService();

  WearStatusIconSnapshot _snapshot = const WearStatusIconSnapshot(
    wifi: WearWifiStatus(isAvailable: false, level: 3),
    showPrinter: false,
    printerAvailable: false,
    voiceCommandsEnabled: true,
  );
  Timer? _timer;
  int _lifecycleGeneration = 0;
  int _voiceStartupGeneration = 0;
  bool _wasWifiAvailable = true;
  bool _wasPrinterAvailable = true;
  bool _voiceStartupActive = false;
  final ValueNotifier<bool> _voiceCommandsEnabled = ValueNotifier<bool>(true);
  WearScreenId Function()? _currentScreenForTesting;
  Future<WearStatusIconSnapshot> Function()? _refreshForTesting;
  Future<void> Function(WearWifiStatus status)? _connectivityObserver;

  WearStatusIconSnapshot get snapshot => _snapshot;
  void beginPerformanceTrace(WearVoiceCommandEvent _) {}

  ValueListenable<bool> get voiceCommandsEnabled => _voiceCommandsEnabled;

  void setConnectivityObserver(
    Future<void> Function(WearWifiStatus status)? observer,
  ) {
    _connectivityObserver = observer;
  }

  void setVoiceCommandsEnabled(bool enabled) {
    if (_voiceCommandsEnabled.value == enabled) return;
    _voiceCommandsEnabled.value = enabled;
    unawaited(refreshAndResend());
  }

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
    _voiceCommandsEnabled.value = true;
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

  Future<void> stop({bool hideProjection = true}) async {
    _lifecycleGeneration++;
    _timer?.cancel();
    _timer = null;
    _voiceStartupActive = false;
    _wasWifiAvailable = true;
    _wasPrinterAvailable = true;
    _voiceCommandsEnabled.value = true;
  }

  Future<WearStatusIconSnapshot> refresh({int? expectedGeneration}) async {
    final Future<WearStatusIconSnapshot> Function()? refreshForTesting =
        _refreshForTesting;
    final WearStatusIconSnapshot next;
    if (refreshForTesting != null) {
      next = await refreshForTesting();
    } else {
      final WearWifiStatus wifi = await _wifiStatusService.getStatus();
      final connectivityObserver = _connectivityObserver;
      if (connectivityObserver != null) {
        unawaited(connectivityObserver(wifi));
      }
      final authority = WearDependencies.I.authority;
      final bool showPrinter = authority.features.printer.selection != null;
      final bool printerAvailable = showPrinter &&
          authority.isAuthorized &&
          await _printerStatusService.isSelectedPrinterAvailable();
      next = WearStatusIconSnapshot(
        wifi: wifi,
        showPrinter: showPrinter,
        printerAvailable: printerAvailable,
        voiceCommandsEnabled: _voiceCommandsEnabled.value,
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

  Future<void> refreshAndResend() async {
    final int lifecycleGeneration = _lifecycleGeneration;
    if (_voiceStartupActive) return;
    await refresh(expectedGeneration: lifecycleGeneration);
  }
}
