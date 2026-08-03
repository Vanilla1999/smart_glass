import 'package:multi_scanner/barcode_settings_config.dart';
import 'package:multi_scanner/multi_scanner.dart';
import 'package:multi_scanner/src/barcode_enum.dart';
import 'package:multi_scanner/src/bluetooth/bt_device.dart';
import 'package:multi_scanner/src/global_multi_scanner.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'multi_scanner_method_channel.dart';

abstract class MultiScannerPlatform extends PlatformInterface {
  /// Constructs a MultiScannerPlatform.
  MultiScannerPlatform() : super(token: _token);

  static final Object _token = Object();

  static MultiScannerPlatform _instance = MethodChannelMultiScanner();

  /// The default instance of [MultiScannerPlatform] to use.
  ///
  /// Defaults to [MethodChannelMultiScanner].
  static MultiScannerPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [MultiScannerPlatform] when
  /// they register themselves.
  static set instance(MultiScannerPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  /// Регистрируем получение баркода через SDK сканеров.
  Future<void> registerListenerScan(
      Set<GlobalMultiScannerDelegate> listDelegate) {
    throw UnimplementedError(
        'registerListenerScan() has not been implemented.');
  }

  /// Если flag = false выключается фонарик.
  Future<void> switchHoneywellLight(bool flag) {
    throw UnimplementedError(
        'switchHoneywellLight() has not been implemented.');
  }

  Future<void> initUserScannerSettings(BarcodeSettingsConfig settings) {
    throw UnimplementedError(
        'initUserScannerSettings() has not been implemented.');
  }

  Future<void> setDefaultSettings() {
    throw UnimplementedError('setDefaultSettings() has not been implemented.');
  }

  Future<void> setRecomendedSettings() {
    throw UnimplementedError(
        'setRecomendedSettings() has not been implemented.');
  }

  Future<void> goToCOMMode() {
    throw UnimplementedError('goToCOMMode() has not been implemented.');
  }

  Future<void> goToHIDMode() {
    throw UnimplementedError('goToHIDMode() has not been implemented.');
  }

  /// Возвращает true, когда фонарик включен.
  Future<bool> getHoneywellLight() {
    throw UnimplementedError('getHoneywellLight() has not been implemented.');
  }

  Future<void> setFlashlight(int state) {
    throw UnimplementedError('setFlashlight() has not been implemented.');
  }

  Future<int> getFlashlightState() {
    throw UnimplementedError('getFlashlightState() has not been implemented.');
  }

  Future<String> takePhoto() {
    throw UnimplementedError('takePhoto() has not been implemented.');
  }

  Future<void> deletePhoto(String uri) {
    throw UnimplementedError('deletePhoto() has not been implemented.');
  }

  /// Выход из спящего режима на клавиши сканирования
  Future<void> wakeUpOnScanButton() {
    throw UnimplementedError('wakeUpOnScanButton() has not been implemented.');
  }

  /// смена флага rhk
  Future<void> changeRhkHoneywell(bool flag) {
    throw UnimplementedError('changeRhkHoneywell() has not been implemented.');
  }

  Future<String?> scanBarcodeByCamera() {
    throw UnimplementedError('scanBarcodeByCamera() has not been implemented.');
  }

  Future<void> init() {
    throw UnimplementedError('init() has not been implemented.');
  }

  Future<void> prepareForWear() {
    throw UnimplementedError('prepareForWear() has not been implemented.');
  }

  Future<void> pauseForWear() {
    throw UnimplementedError('pauseForWear() has not been implemented.');
  }

  Stream<List<BTDevice>> get streamOnBTBound async* {
    throw UnimplementedError('streamOnBTBound() has not been implemented.');
  }

  Stream<List<BTDevice>> get streamOnBTFound async* {
    throw UnimplementedError('streamOnBTFound() has not been implemented.');
  }

  Stream<List<BattaryState>> get battaryStream async* {
    throw UnimplementedError('battaryStream() has not been implemented.');
  }

  Stream<BTDevice?> get connectionStateStream async* {
    throw UnimplementedError(
        'connectionStateStream() has not been implemented.');
  }

  Stream<BTDevice?> get isBoundingStream async* {
    throw UnimplementedError('isBoundingStream() has not been implemented.');
  }

  BTDevice? get currentConnectionBT {
    throw UnimplementedError('currentConnectionBT() has not been implemented.');
  }

  BTDevice? get currentIsBoundingBT {
    throw UnimplementedError('currentIsBoundingBT() has not been implemented.');
  }

  Stream<String> get barcodeStream async* {
    throw UnimplementedError('barcodeStream() has not been implemented.');
  }

  Stream<bool> get isServiceConnected async* {
    throw UnimplementedError('isServiceConnected() has not been implemented.');
  }

  Future<void> startDiscovery() {
    throw UnimplementedError('startDiscovery() has not been implemented.');
  }

  Future<void> cancelDiscovery() {
    throw UnimplementedError('cancelDiscovery() has not been implemented.');
  }

  Future<void> showBluetoothDialog() {
    throw UnimplementedError('showBluetoothDialog() has not been implemented.');
  }

  Future<void> initBluetooth() {
    throw UnimplementedError('init() has not been implemented.');
  }

  Future<void> stopWork() {
    throw UnimplementedError('stopWork() has not been implemented.');
  }

  Future<void> startWork() {
    throw UnimplementedError('startWork() has not been implemented.');
  }

  Future<void> release() {
    throw UnimplementedError('release() has not been implemented.');
  }

  Future<void> releaseBluetooth() {
    throw UnimplementedError('releaseBluetooth() has not been implemented.');
  }

  Future<void> createBond(String deviceName, String deviceMacAdress) {
    throw UnimplementedError('createBond() has not been implemented.');
  }

  Future<void> removeBound(String deviceName, String deviceMacAdress) {
    throw UnimplementedError('removeBound() has not been implemented.');
  }

  Future<void> connect(String deviceName, String deviceMacAdress) {
    throw UnimplementedError('connect() has not been implemented.');
  }

  Future<void> clearBTList() {
    throw UnimplementedError('clearBTList() has not been implemented.');
  }

  Future<bool> isDefaultHorizontal() {
    throw UnimplementedError('clearBTList() has not been implemented.');
  }

  Future<bool> isNeedBT() {
    throw UnimplementedError('clearBTList() has not been implemented.');
  }

  Future<bool> isNotNeedCamera() {
    throw UnimplementedError('clearBTList() has not been implemented.');
  }

  Future<bool> isPCH() {
    throw UnimplementedError('clearBTList() has not been implemented.');
  }

  Future<bool> isServiceConnectedState() {
    throw UnimplementedError('clearBTList() has not been implemented.');
  }

  Future<void> disableScanner() {
    throw UnimplementedError('disableScanner() has not been implemented.');
  }

  Future<void> enableScanner() {
    throw UnimplementedError('enableScanner() has not been implemented.');
  }

  Stream<bool> get scannerDisabled {
    throw UnimplementedError('scannerDisabled has not been implemented.');
  }

  Future<bool> needDefaultExpandKeyboard() {
    throw UnimplementedError(
        'needDefaultExpandKeyboard() has not been implemented.');
  }
}
