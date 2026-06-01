import 'package:dio/dio.dart';
import 'package:smart_glasses/app/data/network/network_requests/api_request.dart';
import 'package:smart_glasses/modules/wear/data/auth/model/auth_user.dart';

class AuthDataSource extends ApiRequest {
  AuthDataSource(this._dio);

  final Dio _dio;

  Future<AuthUser> authenticate({required String badgeUuid}) async {
    const String exText = 'Не удалось аутентифицировать сотрудника';
    final Response<Map<String, dynamic>> response = await fetchRestRequest(
      request: () => _dio.post<Map<String, dynamic>>(
        'auth/login',
        data: <String, dynamic>{'badge_uuid': badgeUuid},
      ),
      location: 'AuthDataSource',
      apiMethod: 'auth/login',
    );

    final Map<String, dynamic>? body = response.data;
    final bool success = body?['success'] == true;
    if (!success) {
      throw Exception(exText);
    }

    final Map<String, dynamic>? data = body?['data'] as Map<String, dynamic>?;
    final Map<String, dynamic>? userJson =
        data?['user'] as Map<String, dynamic>?;

    if (userJson == null) {
      throw Exception(exText);
    }

    return AuthUser.fromJson(userJson);
  }
}
