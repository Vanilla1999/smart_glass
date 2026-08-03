import 'package:multi_scanner/src/bluetooth/bt_device.dart';

class BattaryState {
  final BTDevice device;
  final String battary;

  const BattaryState({
    required this.device,
    required this.battary,
  });

  BattaryState.fromJson(Map<String, dynamic> json)
      : device = BTDevice.fromJson(json['device']),
        battary = json['battary'];
}
