import 'dart:async';

import 'package:smart_glasses/modules/wear/config/wear_session.dart';
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

  WearStatusIconSnapshot get snapshot => _snapshot;

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
    final bool printerAvailable =
        showPrinter && await _printerStatusService.isSelectedPrinterAvailable();
    _snapshot = WearStatusIconSnapshot(
      wifi: wifi,
      showPrinter: showPrinter,
      printerAvailable: printerAvailable,
    );
    return _snapshot;
  }

  Future<void> send(WearGlassesPayload payload) async {
    final WearStatusIconSnapshot snapshot = await refresh();
    final WearGlassesPayload next = _withSnapshot(payload, snapshot);
    _lastPayload = next;
    await wearGlassesBridge.update(next);
  }

  Future<void> sendFast(WearGlassesPayload payload) async {
    final WearGlassesPayload next = _withSnapshot(payload, _snapshot);
    _lastPayload = next;
    await wearGlassesBridge.update(next);
  }

  Future<void> show(WearGlassesPayload payload) async {
    final WearStatusIconSnapshot snapshot = await refresh();
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
}
