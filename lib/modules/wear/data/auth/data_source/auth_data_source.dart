import 'dart:developer';

import 'package:dio/dio.dart';
import 'package:smart_glasses/app/data/network/network_requests/api_request.dart';
import 'package:smart_glasses/modules/wear/data/auth/model/auth_user.dart';

class AuthDataSource extends ApiRequest {
  AuthDataSource(this._dio);

  final Dio _dio;

  Future<AuthUser> authenticate({required String badgeUuid}) async {
    const String exText = 'Не удалось аутентифицировать сотрудника';
    log('POST auth/login badge_uuid=$badgeUuid', name: 'AuthDataSource');
    final Response<Map<String, dynamic>> response = await fetchRestRequest(
      request: () => _dio.post<Map<String, dynamic>>(
        'auth/login',
        data: <String, dynamic>{'badge_uuid': badgeUuid},
      ),
      location: 'AuthDataSource',
      apiMethod: 'auth/login',
    );

    log('status=${response.statusCode} body=${response.data}',
        name: 'AuthDataSource');

    final Map<String, dynamic>? body = response.data;
    final bool success = body?['success'] == true;
    if (!success) {
      final Object? error = body?['error'];
      if (error is Map<String, dynamic>) {
        final Object? message = error['message'];
        if (message is String && message.isNotEmpty) {
          throw Exception(message);
        }
      }
      throw Exception(exText);
    }

    final Map<String, dynamic>? data = body?['data'] as Map<String, dynamic>?;
    final Map<String, dynamic>? userJson =
        data?['user'] as Map<String, dynamic>?;

    if (userJson == null) {
      log('missing data.user in response body=$body', name: 'AuthDataSource');
      throw Exception(exText);
    }

    try {
      return AuthUser.fromJson(userJson);
    } catch (error, stackTrace) {
      log(
        'failed to parse AuthUser userJson=$userJson error=$error',
        name: 'AuthDataSource',
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }
}
