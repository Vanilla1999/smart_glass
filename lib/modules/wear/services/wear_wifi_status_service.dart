import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
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

  Future<WearWifiStatus> getStatus() async {
    try {
      final bool canReadWifiDetails = await _ensureWifiDetailsPermission();
      if (!canReadWifiDetails) {
        return const WearWifiStatus(isAvailable: false, level: 0);
      }

      final WifiInfoWrapper? details = await WifiInfoPlugin.wifiDetails;
      if (details == null) {
        return const WearWifiStatus(isAvailable: false, level: 0);
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

      return WearWifiStatus(
        isAvailable: isAvailable,
        level: isAvailable ? _signalToLevel(signalStrength) : 0,
      );
    } on PlatformException {
      return const WearWifiStatus(isAvailable: false, level: 0);
    } catch (_) {
      return const WearWifiStatus(isAvailable: false, level: 0);
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
