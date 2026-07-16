import 'dart:io';

import 'package:multi_scanner/multi_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_glasses/core/services/method_channel_service.dart';

class WearPhotoStore {
  WearPhotoStore({
    MovfastGlassController? controller,
    MethodChannelService? methodChannelService,
    Future<String> Function()? takePhoto,
    Future<void> Function(String uri)? deletePhoto,
    Future<String> Function(String uri)? copyPhotoToAppStorage,
  })  : _controller = controller ?? MovfastGlassController(),
        _methodChannelService = methodChannelService ?? MethodChannelService(),
        _takePhoto = takePhoto,
        _deletePhoto = deletePhoto,
        _copyPhotoToAppStorage = copyPhotoToAppStorage;

  static const String _latestPhotoPathKey = 'wear_latest_photo_path';

  final MovfastGlassController _controller;
  final MethodChannelService _methodChannelService;
  final Future<String> Function()? _takePhoto;
  final Future<void> Function(String uri)? _deletePhoto;
  final Future<String> Function(String uri)? _copyPhotoToAppStorage;

  Future<String> captureLatestPhoto() async {
    final String uri = await (_takePhoto?.call() ?? _controller.takePhoto());
    final String path = await (_copyPhotoToAppStorage?.call(uri) ??
        _methodChannelService.copyPhotoToAppStorage(uri));
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_latestPhotoPathKey, path);
    try {
      await (_deletePhoto?.call(uri) ?? _controller.deletePhoto(uri));
    } catch (error, stackTrace) {
      print(
          '[WearPhotoStore] source photo cleanup failed: $error\n$stackTrace');
    }
    return path;
  }

  Future<File?> latestPhoto() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? path = prefs.getString(_latestPhotoPathKey);
    if (path == null || path.isEmpty) return null;
    final File file = File(path);
    if (await file.exists()) return file;
    await prefs.remove(_latestPhotoPathKey);
    return null;
  }
}
