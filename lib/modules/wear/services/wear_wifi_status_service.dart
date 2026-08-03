import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:smart_glasses/modules/wear/config/wear_mock_config.dart';
import 'package:wifi_info_plugin_plus/wifi_info_plugin_plus.dart';

class WearWifiStatus {
  const WearWifiStatus({
    required this.isAvailable,
    required this.level,
  });

  final bool isAvailable;
  final int level;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is WearWifiStatus &&
            other.isAvailable == isAvailable &&
            other.level == level;
  }

  @override
  int get hashCode => Object.hash(isAvailable, level);
}

class WearWifiStatusService {
  const WearWifiStatusService();

  static WearWifiStatus? _lastKnownStatus;

  Future<WearWifiStatus> getStatus() async {
    try {
      if (WearMockConfig.isEnabled) {
        return const WearWifiStatus(isAvailable: true, level: 3);
      }

      final AppLifecycleState? lifecycleState =
          WidgetsBinding.instance.lifecycleState;
      if (lifecycleState != null &&
          lifecycleState != AppLifecycleState.resumed) {
        return _lastKnownStatus ??
            const WearWifiStatus(isAvailable: true, level: 1);
      }

      final bool canReadWifiDetails = await _ensureWifiDetailsPermission();
      if (!canReadWifiDetails) {
        return const WearWifiStatus(isAvailable: true, level: 1);
      }

      final WifiInfoWrapper? details = await WifiInfoPlugin.wifiDetails;
      if (details == null) {
        const WearWifiStatus status =
            WearWifiStatus(isAvailable: false, level: 0);
        _lastKnownStatus = status;
        return status;
      }

      final String connectionType = details.connectionType.toLowerCase().trim();
      final String ssid = details.ssid.trim();
      final String ipAddress = details.ipAddress.trim();
      final int networkId = details.networkId;
      final int? signalStrength = _asInt(details.signalStrength);
      final bool isWifi = connectionType.contains('wifi');
      final bool hasKnownNetwork = ssid.isNotEmpty &&
          ssid != '<unknown ssid>' &&
          ssid.toLowerCase() != 'unknown';
      final bool hasIp = ipAddress.isNotEmpty && ipAddress != '0.0.0.0';
      final bool hasNetworkId = networkId >= 0;
      final bool hasSignal = signalStrength != null && signalStrength != 0;
      final bool isAvailable =
          isWifi || hasKnownNetwork || hasIp || hasNetworkId || hasSignal;

      final WearWifiStatus status = WearWifiStatus(
        isAvailable: isAvailable,
        level: isAvailable ? _signalToLevel(signalStrength) : 0,
      );
      _lastKnownStatus = status;
      return status;
    } on PlatformException catch (error, stackTrace) {
      print('[WearWifiStatusService] platform error: $error\n$stackTrace');
      return _lastKnownStatus ??
          const WearWifiStatus(isAvailable: true, level: 1);
    } catch (error, stackTrace) {
      print('[WearWifiStatusService] error: $error\n$stackTrace');
      return _lastKnownStatus ??
          const WearWifiStatus(isAvailable: true, level: 1);
    }
  }

  int _signalToLevel(int? signalStrength) {
    if (signalStrength == null) return 3;

    // wifi_info_plugin_plus on Android returns WifiManager.calculateSignalLevel(
    // rssi, 10), so the usual value is 0..9, not percent. The previous
    // percent thresholds made all normal positive values show as one division.
    if (signalStrength >= 0 && signalStrength <= 9) {
      if (signalStrength >= 7) return 3;
      if (signalStrength >= 4) return 2;
      return 1;
    }

    // Some implementations may return signal as percent.
    if (signalStrength > 9) {
      if (signalStrength >= 67) return 3;
      if (signalStrength >= 34) return 2;
      return 1;
    }

    // Android RSSI is commonly reported in dBm: about -30 excellent, -90 weak.
    if (signalStrength >= -55) return 3;
    if (signalStrength >= -70) return 2;
    return 1;
  }

  int? _asInt(Object? value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse(value.toString());
  }

  Future<bool> _ensureWifiDetailsPermission() async {
    final ServiceStatus serviceStatus =
        await Permission.locationWhenInUse.serviceStatus;
    if (!serviceStatus.isEnabled) {
      return false;
    }

    final PermissionStatus status = await Permission.locationWhenInUse.status;
    if (status.isGranted || status.isLimited) {
      return true;
    }
    if (status.isPermanentlyDenied || status.isRestricted) {
      return false;
    }

    final PermissionStatus requested =
        await Permission.locationWhenInUse.request();
    return requested.isGranted || requested.isLimited;
  }
}
