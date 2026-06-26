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
  bool _wasWifiAvailable = true;
  bool _wasPrinterAvailable = true;
  bool _voiceStartupActive = false;
  WearScreenId Function()? _currentScreenForTesting;

  WearStatusIconSnapshot get snapshot => _snapshot;
  WearGlassesPayload? get lastPayload => _lastPayload;

  void debugSetCurrentScreenProviderForTesting(
    WearScreenId Function()? currentScreen,
  ) {
    _currentScreenForTesting = currentScreen;
  }

  void beginVoiceStartup() {
    _voiceStartupActive = true;
  }

  void endVoiceStartup() {
    _voiceStartupActive = false;
  }

  void start() {
    _timer ??= Timer.periodic(
      const Duration(seconds: 2),
      (_) => refreshAndResend(),
    );
    unawaited(refreshAndResend());
  }

  Future<WearStatusIconSnapshot> refresh() async {
    final WearWifiStatus wifi = await _wifiStatusService.getStatus();
    final bool showPrinter = WearSession.hasPrinterSelection;
    final bool printerAvailable = showPrinter &&
        WearSession.isAuthorized &&
        await _printerStatusService.isSelectedPrinterAvailable();
    _snapshot = WearStatusIconSnapshot(
      wifi: wifi,
      showPrinter: showPrinter,
      printerAvailable: printerAvailable,
    );
    _openSettingsIfNeeded(_snapshot);
    return _snapshot;
  }

  void _openSettingsIfNeeded(WearStatusIconSnapshot snapshot) {
    final WearScreenId current =
        WearDependencies.I.wearFlowController.state.screen;
    final bool onWifiSettingsScreen = current == WearScreenId.wifiSettings;
    final bool onPrinterSettingsScreen =
        current == WearScreenId.printerSettings;

    if (!snapshot.wifi.isAvailable &&
        _wasWifiAvailable &&
        !onWifiSettingsScreen) {
      unawaited(
        WearDependencies.I.wearFlowController.requestNavigation(
          WearScreenId.wifiSettings,
        ),
      );
    }

    if (snapshot.showPrinter &&
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
    if (_shouldDeferForVoiceStartup(payload)) return;
    final WearStatusIconSnapshot snapshot = await refresh();
    if (_shouldDeferForVoiceStartup(payload)) return;
    final WearGlassesPayload next = _withSnapshot(payload, snapshot);
    _lastPayload = next;
    await wearGlassesBridge.update(next);
  }

  Future<void> sendForScreen(
    WearScreenId screen,
    WearGlassesPayload payload,
  ) async {
    if (_shouldDeferForVoiceStartup(payload)) return;
    if (!_isCurrentScreen(screen)) return;
    final WearStatusIconSnapshot snapshot = await refresh();
    if (_shouldDeferForVoiceStartup(payload)) return;
    if (!_isCurrentScreen(screen)) return;
    final WearGlassesPayload next = _withSnapshot(payload, snapshot);
    _lastPayload = next;
    await wearGlassesBridge.update(next);
  }

  Future<void> sendFast(WearGlassesPayload payload) async {
    if (_shouldDeferForVoiceStartup(payload)) return;
    final WearGlassesPayload next = _withSnapshot(payload, _snapshot);
    _lastPayload = next;
    await wearGlassesBridge.update(next);
  }

  Future<void> sendFastForScreen(
    WearScreenId screen,
    WearGlassesPayload payload,
  ) async {
    if (_shouldDeferForVoiceStartup(payload)) return;
    if (!_isCurrentScreen(screen)) return;
    final WearGlassesPayload next = _withSnapshot(payload, _snapshot);
    _lastPayload = next;
    await wearGlassesBridge.update(next);
  }

  Future<void> sendTransientFast(WearGlassesPayload payload) async {
    if (_shouldDeferForVoiceStartup(payload)) return;
    final WearGlassesPayload next = _withSnapshot(payload, _snapshot);
    await wearGlassesBridge.update(next);
  }

  Future<void> show(WearGlassesPayload payload) async {
    if (_shouldDeferForVoiceStartup(payload)) return;
    final WearStatusIconSnapshot snapshot = await refresh();
    if (_shouldDeferForVoiceStartup(payload)) return;
    final WearGlassesPayload next = _withSnapshot(payload, snapshot);
    _lastPayload = next;
    await wearGlassesBridge.show(next);
  }

  Future<void> refreshAndResend() async {
    final WearGlassesPayload? payload = _lastPayload;
    if (payload == null) {
      await refresh();
      return;
    }
    if (_voiceStartupActive) return;

    final WearStatusIconSnapshot previous = _snapshot;
    final WearStatusIconSnapshot next = await refresh();
    if (previous.wifi == next.wifi &&
        previous.showPrinter == next.showPrinter &&
        previous.printerAvailable == next.printerAvailable) {
      return;
    }

    final WearGlassesPayload updated = _withSnapshot(payload, next);
    _lastPayload = updated;
    await wearGlassesBridge.update(updated);
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
