import 'dart:developer';

import 'package:dio/dio.dart';

abstract class ApiRequest {
  Future<T> fetchRestRequest<T>({
    required Future<T> Function() request,
    required String location,
    required String apiMethod,
  }) async {
    try {
      return await request();
    } catch (e, s) {
      log('$apiMethod\nException: $e\n$s', name: location);

      if (e is DioException) {
        throw Exception('Network error: ${e.message}');
      }
      rethrow;
    }
  }
}
