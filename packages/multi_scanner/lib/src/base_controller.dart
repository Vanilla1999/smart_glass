import 'dart:async';

import 'package:multi_scanner/barcode_settings_config.dart';
import 'package:multi_scanner/src/platform/multi_scanner_platform_interface.dart';

class BaseController {
  static MultiScannerPlatform get _platform {
    return MultiScannerPlatform.instance;
  }

  StreamController<bool>? _streamController;
  StreamController<bool>? _scannerDisabledController;

  Future<bool> get isConnected => _platform.isServiceConnectedState();

  /// передаем настройки сканера пользователя, если не передадим - будут дефолтные.
  Future<void> initUserScannerSettings(BarcodeSettingsConfig settings) =>
      _platform.initUserScannerSettings(settings);

  Future<void> setDefaultSettings() => _platform.setDefaultSettings();

  Future<void> setRecomendedSettings() => _platform.setRecomendedSettings();

  Future<void> init() => _platform.init();

  Future<void> prepareForWear() => _platform.prepareForWear();

  Future<void> pauseForWear() => _platform.pauseForWear();

  Future<void> release() => _platform.release();

  Future<String?> scanBarcodeByCamera() => _platform.scanBarcodeByCamera();

  Stream<bool> get isServiceConnected {
    if (_streamController == null) {
      _streamController = StreamController<bool>.broadcast();

      _initController<bool>(
        _streamController!,
        _platform.isServiceConnected.map((value) {
          return value;
        }),
        onCancel: () => _streamController = null,
      );
    }

    return _streamController!.stream;
  }

  Future<void> disableScanner() => _platform.disableScanner();

  Future<void> enableScanner() => _platform.enableScanner();

  Stream<bool> get scannerDisabled {
    if (_scannerDisabledController == null) {
      _scannerDisabledController = StreamController<bool>.broadcast();

      _initController<bool>(
        _scannerDisabledController!,
        _platform.scannerDisabled,
        onCancel: () => _scannerDisabledController = null,
      );
    }

    return _scannerDisabledController!.stream;
  }

  Future<bool> isDefaultHorizontal() => _platform.isDefaultHorizontal();

  Future<bool> isNeedBT() => _platform.isNeedBT();

  Future<bool> isNotNeedCamera() => _platform.isNotNeedCamera();

  Future<bool> isPCH() => _platform.isPCH();

  void _initController<T>(
    StreamController<T> controller,
    Stream<T> stream, {
    required void Function() onCancel,
  }) {
    final subscription = stream.listen(
      controller.add,
      onError: controller.addError,
    );

    controller.onCancel = () async {
      await subscription.cancel();
      await controller.close();
      onCancel();
    };
  }
}
