import 'package:flutter/services.dart';
import 'package:multi_scanner/src/bluetooth/battary_state.dart';
import 'package:multi_scanner/src/bluetooth/bt_device.dart';
import 'package:multi_scanner/src/platform/multi_scanner_method_channel.dart';
import 'package:multi_scanner/src/platform/multi_scanner_platform_interface.dart';

class MultiScannerBluetooth {
  ///Singleton MultiScannerController
  factory MultiScannerBluetooth() {
    _singleton ??= MultiScannerBluetooth._();
    return _singleton!;
  }

  MultiScannerBluetooth._();

  static MultiScannerBluetooth? _singleton;

  Stream<List<BTDevice>> streamOnBTFound =
      MultiScannerPlatform.instance.streamOnBTFound.asBroadcastStream();

  Stream<List<BTDevice>> streamOnBTBound =
      MultiScannerPlatform.instance.streamOnBTBound.asBroadcastStream();

  Stream<String> barcodeStream =
      MultiScannerPlatform.instance.barcodeStream.asBroadcastStream();

  Stream<List<BattaryState>> battaryStream =
      MultiScannerPlatform.instance.battaryStream.asBroadcastStream();

  Stream<BTDevice?> connectionStream =
      MultiScannerPlatform.instance.connectionStateStream.asBroadcastStream();
  Stream<BTDevice?> isBoundingStream =
      MultiScannerPlatform.instance.isBoundingStream.asBroadcastStream();

  BTDevice? currentConnectionBT =
      MultiScannerPlatform.instance.currentConnectionBT;
  BTDevice? currentIsBoundingBT =
      MultiScannerPlatform.instance.currentIsBoundingBT;

  Future<void> startDiscovery() async {
    MultiScannerPlatform.instance.startDiscovery();
  }

  Future<void> cancelDiscovery() async {
    MultiScannerPlatform.instance.cancelDiscovery();
  }

  Future<void> showBluetoothDialog() async {
    MultiScannerPlatform.instance.showBluetoothDialog();
  }

  Future<void> init() async {
    await MultiScannerPlatform.instance.initBluetooth();
  }

  Future<void> stopWork() async {
    MultiScannerPlatform.instance.stopWork();
  }

  Future<void> startWork() async {
    MultiScannerPlatform.instance.startWork();
  }

  Future<void> createBond(String deviceName, String deviceMacAdress) async {
    MultiScannerPlatform.instance.createBond(deviceName, deviceMacAdress);
  }

  Future<void> removeBound(String deviceName, String deviceMacAdress) async {
    MultiScannerPlatform.instance.removeBound(deviceName, deviceMacAdress);
  }

  Future<void> connect(String deviceName, String deviceMacAdress) async {
    MultiScannerPlatform.instance.connect(deviceName, deviceMacAdress);
  }

  Future<void> clearBTList() async {
    MultiScannerPlatform.instance.clearBTList();
  }
}
