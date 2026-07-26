import 'dart:async';

import 'package:flutter/services.dart';
import 'package:smart_glasses/core/constants/app_constants.dart';

/// Service for managing MethodChannel communication with native code
class MethodChannelService {
  MethodChannelService._() {
    _appChannel.setMethodCallHandler(_handleAppMethodCall);
  }

  static final MethodChannelService _instance = MethodChannelService._();
  factory MethodChannelService() => _instance;

  final MethodChannel _appChannel =
      const MethodChannel(AppConstants.appChannelName);
  final MethodChannel _glassesChannel =
      const MethodChannel(AppConstants.glassesChannelName);
  final StreamController<bool> _audioCaptureSilencedController =
      StreamController<bool>.broadcast();
  final StreamController<Map<String, dynamic>> _audioInputDeviceController =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>>
      _voiceCaptureDiagnosticsController =
      StreamController<Map<String, dynamic>>.broadcast();

  Stream<bool> get audioCaptureSilencedStream =>
      _audioCaptureSilencedController.stream;
  Stream<Map<String, dynamic>> get audioInputDeviceStream =>
      _audioInputDeviceController.stream;
  Stream<Map<String, dynamic>> get voiceCaptureDiagnosticsStream =>
      _voiceCaptureDiagnosticsController.stream;

  Future<void> _handleAppMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'audioCaptureSilencedChanged':
        final bool? silenced = call.arguments as bool?;
        if (silenced != null && !_audioCaptureSilencedController.isClosed) {
          _audioCaptureSilencedController.add(silenced);
        }
      case 'audioInputDeviceChanged':
        final Map<dynamic, dynamic>? arguments = call.arguments as Map?;
        if (arguments != null && !_audioInputDeviceController.isClosed) {
          _audioInputDeviceController.add(arguments.cast<String, dynamic>());
        }
      case 'voiceCaptureDiagnostics':
        final Map<dynamic, dynamic>? arguments = call.arguments as Map?;
        if (arguments != null && !_voiceCaptureDiagnosticsController.isClosed) {
          _voiceCaptureDiagnosticsController
              .add(arguments.cast<String, dynamic>());
        }
      default:
        throw MissingPluginException(
            'Unknown app channel method: ${call.method}');
    }
  }

  /// Show glasses initialization screen
  Future<void> showGlassesInitialization() async {
    try {
      print('MethodChannelService: Showing glasses initialization screen');
      await _appChannel.invokeMethod('showGlassesInitialization');
    } catch (e) {
      print('Error showing glasses initialization: $e');
      rethrow;
    }
  }

  /// Navigate glasses to empty screen
  Future<void> navigateGlassesToEmpty() async {
    try {
      print('MethodChannelService: Navigating glasses to empty screen');
      await _appChannel.invokeMethod('navigateGlassesToEmpty');
    } catch (e) {
      print('Error navigating to empty screen: $e');
      rethrow;
    }
  }

  /// Update counter on glasses
  Future<void> updateCounter(int counter) async {
    try {
      await _appChannel.invokeMethod('updateCounter', counter);
    } catch (e) {
      print('Error updating counter: $e');
      rethrow;
    }
  }

  /// Update recognized text on glasses
  Future<void> updateRecognizedText(String text) async {
    try {
      print('MethodChannelService: Sending text to glasses: $text');
      await _appChannel.invokeMethod('updateRecognizedText', text);
      print('MethodChannelService: Text sent successfully');
    } catch (e) {
      print('Error updating recognized text: $e');
      rethrow;
    }
  }

  /// Show wear projection screen on glasses and send initial payload.
  Future<void> showWearGlasses(Map<String, dynamic> payload) async {
    try {
      await _appChannel.invokeMethod('showWearGlasses', payload);
    } catch (e) {
      print('Error showing wear glasses: $e');
      rethrow;
    }
  }

  /// Update current wear projection payload on glasses.
  Future<void> updateWearGlasses(Map<String, dynamic> payload) async {
    try {
      await _appChannel.invokeMethod('updateWearGlasses', payload);
    } catch (e) {
      print('Error updating wear glasses: $e');
      rethrow;
    }
  }

  /// Updates the voice availability overlay without replacing wear content.
  Future<void> updateWearVoiceOverlay({
    required bool visible,
    required String phase,
    required String reason,
    required int attempt,
    required int revision,
    String? message,
  }) async {
    try {
      await _appChannel
          .invokeMethod('updateWearVoiceOverlay', <String, dynamic>{
        'visible': visible,
        'version': 1,
        'revision': revision,
        'phase': phase,
        'reason': reason,
        'attempt': attempt,
        'message': message,
      });
    } catch (e) {
      print('Error updating wear voice overlay: $e');
      rethrow;
    }
  }

  /// Configures native silencing diagnostics for the active recorder capture.
  Future<void> updateVoiceCaptureMonitor({
    required bool active,
    required String source,
    required int captureId,
  }) async {
    try {
      await _appChannel
          .invokeMethod('updateVoiceCaptureMonitor', <String, dynamic>{
        'active': active,
        'source': source,
        'captureId': captureId,
      });
    } catch (e) {
      print('Error updating voice capture monitor: $e');
      rethrow;
    }
  }

  /// Hide wear projection screen on glasses.
  Future<void> hideWearGlasses() async {
    try {
      await _appChannel.invokeMethod('hideWearGlasses');
    } catch (e) {
      print('Error hiding wear glasses: $e');
      rethrow;
    }
  }

  /// Copy a content URI returned by the glasses into app-private storage.
  Future<String> copyPhotoToAppStorage(String uri) async {
    try {
      final String? path = await _appChannel.invokeMethod<String>(
        'copyPhotoToAppStorage',
        <String, String>{'uri': uri},
      );
      if (path == null || path.isEmpty) {
        throw PlatformException(
          code: 'EMPTY_PHOTO_PATH',
          message: 'Native photo copy returned an empty path',
        );
      }
      return path;
    } catch (e) {
      print('Error copying photo to app storage: $e');
      rethrow;
    }
  }

  /// Save logs to file
  Future<void> saveLogs() async {
    try {
      await _appChannel.invokeMethod('saveLogs');
    } catch (e) {
      print('Error saving logs: $e');
      rethrow;
    }
  }

  /// Clear logs
  Future<void> clearLogs() async {
    try {
      await _appChannel.invokeMethod('clearLogs');
    } catch (e) {
      print('Error clearing logs: $e');
      rethrow;
    }
  }

  /// Get initial counter value from glasses
  Future<int> getInitialCounter() async {
    try {
      final int result =
          await _glassesChannel.invokeMethod('getInitialCounter');
      return result;
    } catch (e) {
      print('Error getting initial counter: $e');
      return 0;
    }
  }

  /// Set method call handler for glasses channel
  void setGlassesMethodCallHandler(
      Future<dynamic> Function(MethodCall call) handler) {
    _glassesChannel.setMethodCallHandler(handler);
  }
}
