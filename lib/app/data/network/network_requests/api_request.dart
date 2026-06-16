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
        final Object? responseData = e.response?.data;
        if (responseData is Map<String, dynamic>) {
          final Object? error = responseData['error'];
          if (error is Map<String, dynamic>) {
            final Object? message = error['message'];
            if (message is String && message.isNotEmpty) {
              throw Exception(message);
            }
          }
          final Object? message = responseData['message'];
          if (message is String && message.isNotEmpty) {
            throw Exception(message);
          }
        }
        throw Exception('Network error: ${e.message}');
      }
      rethrow;
    }
  }
}
