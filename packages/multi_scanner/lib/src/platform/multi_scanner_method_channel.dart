import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:multi_scanner/barcode_settings_config.dart';
import 'package:multi_scanner/src/bluetooth/battary_state.dart';
import 'package:multi_scanner/src/bluetooth/bt_device.dart';
import 'package:multi_scanner/src/global_multi_scanner.dart';
import 'package:multi_scanner/src/platform/multi_scanner_platform_interface.dart';

/// An implementation of [MultiScannerPlatform] that uses method channels.
class MethodChannelMultiScanner extends MultiScannerPlatform {
  /// EventChannel для получния баркода из native
  @visibleForTesting
  EventChannel eventChannel =
      const EventChannel('tander/multi_scanner_plugin/event_barcode');
  @visibleForTesting
  EventChannel eventSinkServiceConnections = const EventChannel(
      'tander/multi_scanner_plugin/eventSinkServiceConnections');
  @visibleForTesting
  EventChannel eventScannerDisabled =
      const EventChannel('tander/multi_scanner_plugin/event_scanner_disabled');

  /// MethodChannel использующийся для получения доступа к функциям SDK
  @visibleForTesting
  MethodChannel methodChannel =
      const MethodChannel('tander/multi_scanner_plugin/channel');

  /// Регистрируем получение баркода через SDK сканеров.
  @override
  Future<void> registerListenerScan(
      Set<GlobalMultiScannerDelegate> listDelegate) async {
    eventChannel.receiveBroadcastStream().listen(
      (data) {
        debugPrint('Barcode: $data');
        var barcode = _Barcode.fromJson(jsonDecode(data));
        for (var d in listDelegate) {
          d.onEvent(barcode.barcode);
        }
      },
    );
  }

  /// Если flag = false выключается фонарик.
  @override
  Future<void> switchHoneywellLight(bool flag) async {
    methodChannel.invokeMethod(
      'switchHoneywellLight',
      <String, bool>{
        'flag': flag,
      },
    );
  }

  /// Возвращает true, когда фонарик включен.
  @override
  Future<bool> getHoneywellLight() async {
    return await methodChannel.invokeMethod('getHoneywellLight');
  }

  @override
  Future<void> setFlashlight(int state) async {
    return methodChannel.invokeMethod(
      'setFlashlight',
      <String, int>{
        'state': state,
      },
    );
  }

  @override
  Future<int> getFlashlightState() async {
    return await methodChannel.invokeMethod('getFlashlightState');
  }

  @override
  Future<String> takePhoto() async {
    final uri = await methodChannel.invokeMethod<String>('takePhoto');

    if (uri == null || uri.isEmpty) {
      throw PlatformException(
        code: 'EMPTY_PHOTO_URI',
        message: 'Native photo capture returned an empty URI',
      );
    }

    return uri;
  }

  @override
  Future<void> deletePhoto(String uri) {
    return methodChannel.invokeMethod<void>(
      'deletePhoto',
      <String, String>{
        'uri': uri,
      },
    );
  }

  @override
  Future<void> changeRhkHoneywell(bool flag) {
    return methodChannel.invokeMethod(
      'changeRhkHoneywell',
      <String, bool>{
        'flag': flag,
      },
    );
  }

  @override
  Future<void> initUserScannerSettings(BarcodeSettingsConfig settings) async {
    return methodChannel.invokeMethod(
        'setUserScanSettings', {'settings': settings.toJson().toString()});
  }

  @override
  Future<void> setDefaultSettings() async {
    return methodChannel.invokeMethod('setDefaultSettings');
  }

  @override
  Future<void> setRecomendedSettings() async {
    return methodChannel.invokeMethod('setRecomendedSettings');
  }

  @override
  Future<void> goToCOMMode() async {
    return methodChannel.invokeMethod('goToCOMMode');
  }

  @override
  Future<void> goToHIDMode() async {
    return methodChannel.invokeMethod('goToHIDMode');
  }

  @override
  Future<void> wakeUpOnScanButton() async {
    return methodChannel.invokeMethod('wakeUpOnScanButton');
  }

  @override
  Future<String?> scanBarcodeByCamera() async {
    return methodChannel.invokeMethod('scanBarcodeByCamera');
  }

  @override
  Future<void> init() async {
    return methodChannel.invokeMethod('init');
  }

  @override
  Future<void> prepareForWear() {
    return methodChannel.invokeMethod<void>('prepareForWear');
  }

  @override
  Future<void> pauseForWear() {
    return methodChannel.invokeMethod<void>('pauseForWear');
  }

  @visibleForTesting
  final StreamController<MethodCall> methodStream =
      StreamController.broadcast();

  @override
  Stream<List<BTDevice>> get streamOnBTFound async* {
    yield* methodStream.stream
        .where((m) => m.method == "onBtFound")
        .map((event) => _methodCallToBTDevice(event));
  }

  @override
  Stream<bool> get isServiceConnected => eventSinkServiceConnections
      .receiveBroadcastStream()
      .where((json) => json != null)
      .map<bool>((dynamic json) => json);

  final StreamController<String> _barcodeStreamController =
      StreamController.broadcast();

  @override
  Stream<String> get barcodeStream =>
      _barcodeStreamController.stream.asBroadcastStream();

  final StreamController<BTDevice?> _connectionStateStreamController =
      StreamController.broadcast();
  final StreamController<BTDevice?> _isBoundingStreamStreamController =
      StreamController.broadcast();

  BTDevice? _currentConnectionBT = null;

  BTDevice? _currentIsBoundingBT = null;

  @override
  Stream<BTDevice?> get connectionStateStream =>
      _connectionStateStreamController.stream.asBroadcastStream();

  @override
  Stream<BTDevice?> get isBoundingStream =>
      _isBoundingStreamStreamController.stream.asBroadcastStream();

  @override
  BTDevice? get currentConnectionBT => _currentConnectionBT;

  @override
  BTDevice? get currentIsBoundingBT => _currentIsBoundingBT;

  final StreamController<List<BattaryState>> _battaryStreamController =
      StreamController.broadcast();

  @override
  Stream<List<BattaryState>> get battaryStream =>
      _battaryStreamController.stream.asBroadcastStream();

  @override
  Stream<List<BTDevice>> get streamOnBTBound async* {
    yield* methodStream.stream
        .where((m) => m.method == "onBtBound")
        .map((event) => _methodCallToBTDevice(event));
  }

  List<BTDevice> _methodCallToBTDevice(MethodCall methodCall) {
    try {
      var listBTDevices =
          _BTDevices.fromJson(jsonDecode(methodCall.arguments)).btDevices;
      if (listBTDevices.isNotEmpty) {
        return List<BTDevice>.from(
            listBTDevices.map((model) => BTDevice.fromJson(model)));
      } else {
        return List.empty();
      }
    } catch (e) {
      return List.empty();
    }
  }

  List<BattaryState> _battaryStateMap(MethodCall methodCall) {
    try {
      var listBTDevices =
          _BattaryStateList.fromJson(jsonDecode(methodCall.arguments))
              .battaryState;
      if (listBTDevices.isNotEmpty) {
        return List<BattaryState>.from(
            listBTDevices.map((model) => BattaryState.fromJson(model)));
      } else {
        return List.empty();
      }
    } catch (e) {
      return List.empty();
    }
  }

  @override
  Future<void> startDiscovery() async {
    methodChannel.invokeMethod('startDiscovery');
  }

  @override
  Future<void> cancelDiscovery() async {
    methodChannel.invokeMethod('cancelDiscovery');
  }

  @override
  Future<void> showBluetoothDialog() async {
    return methodChannel.invokeMethod('showBluetoothDialog');
  }

  @override
  Future<void> initBluetooth() async {
    methodChannel.setMethodCallHandler((call) async {
      if ((call.method != "battaryState") || call.method != "barcode") {
        methodStream.add(call);
      }
      if (call.method == "battaryState") {
        var battaryStates = _battaryStateMap(call);
        _battaryStreamController.add(battaryStates);
      }
      if (call.method == "barcode") {
        _barcodeStreamController.add(call.arguments);
      }
      if (call.method == "connectedState") {
        if (call.arguments == null) {
          _currentConnectionBT = null;
          _connectionStateStreamController.add(null);
          return;
        }
        var device = BTDevice.fromJson(jsonDecode(call.arguments));
        _currentConnectionBT = device;
        _connectionStateStreamController.add(device);
      }
      if (call.method == "isBoundingDevice") {
        if (call.arguments == null) {
          _currentIsBoundingBT = null;
          _isBoundingStreamStreamController.add(null);
          return;
        }
        var device = BTDevice.fromJson(jsonDecode(call.arguments));
        _currentIsBoundingBT = device;
        _isBoundingStreamStreamController.add(device);
      }
    });
    await methodChannel.invokeMethod('initBluetooth');
  }

  @override
  Future<void> stopWork() async {
    methodChannel.invokeMethod('stopWork');
  }

  @override
  Future<void> startWork() async {
    methodChannel.invokeMethod('startWork');
  }

  @override
  Future<void> release() async {
    await methodChannel.invokeMethod<void>('release');
  }

  @override
  Future<void> releaseBluetooth() async {
    methodChannel.invokeMethod('releaseBluetooth');
  }

  @override
  Future<void> createBond(String deviceName, String deviceMacAdress) async {
    methodChannel.invokeMethod(
      'createBond',
      <String, String>{
        'deviceName': deviceName,
        'macAdress': deviceMacAdress,
      },
    );
  }

  @override
  Future<void> removeBound(String deviceName, String deviceMacAdress) async {
    await methodChannel.invokeMethod(
      'removeBound',
      <String, String>{
        'deviceName': deviceName,
        'macAdress': deviceMacAdress,
      },
    );
  }

  @override
  Future<void> connect(String deviceName, String deviceMacAdress) async {
    methodChannel.invokeMethod(
      'connectToBT',
      <String, String>{
        'deviceName': deviceName,
        'macAdress': deviceMacAdress,
      },
    );
  }

  @override
  Future<void> clearBTList() async {
    methodChannel.invokeMethod('clearBTList');
  }

  @override
  Future<bool> isDefaultHorizontal() async {
    final result = await methodChannel.invokeMethod<bool>(
      'isDefaultHorizontal',
    );
    return result as bool;
  }

  @override
  Future<bool> isNeedBT() async {
    final result = await methodChannel.invokeMethod<bool>(
      'isNeedBT',
    );
    return result as bool;
  }

  @override
  Future<bool> isNotNeedCamera() async {
    final result = await methodChannel.invokeMethod<bool>(
      'isNotNeedCamera',
    );
    return result as bool;
  }

  @override
  Future<bool> isPCH() async {
    final result = await methodChannel.invokeMethod<bool>(
      'isPCH',
    );
    return result as bool;
  }

  @override
  Future<bool> isServiceConnectedState() async {
    final result = await methodChannel.invokeMethod<bool>(
      'isServiceConnected',
    );
    return result as bool;
  }

  @override
  Future<void> disableScanner() async {
    return methodChannel.invokeMethod('disableScanner');
  }

  @override
  Future<void> enableScanner() async {
    return methodChannel.invokeMethod('enableScanner');
  }

  @override
  Stream<bool> get scannerDisabled => eventScannerDisabled
      .receiveBroadcastStream()
      .map((dynamic v) => v as bool);

  @override
  Future<bool> needDefaultExpandKeyboard() async {
    final result = await methodChannel.invokeMethod<bool>(
      'needDefaultExpandKeyboard',
    );
    return result as bool;
  }
}

class _BTDevices {
  final Iterable btDevices;

  _BTDevices({required this.btDevices});

  _BTDevices.fromJson(Map<String, dynamic> json) : btDevices = json['devices'];
}

class _BattaryStateList {
  final Iterable battaryState;

  _BattaryStateList({required this.battaryState});

  _BattaryStateList.fromJson(Map<String, dynamic> json)
      : battaryState = json['states'];
}

class _Barcode {
  const _Barcode(this.tsd, this.barcode);

  final String tsd;
  final String barcode;

  _Barcode.fromJson(Map<String, dynamic> json)
      : tsd = json['tsd'],
        barcode = json['barcode'];
}
