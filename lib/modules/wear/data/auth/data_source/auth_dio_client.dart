import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class AuthDioClient {
  Future<Dio> create() async {
    final String host = _requireEnv('AUTH_SERVICE_HOST');
    final String portValue = _requireEnv('AUTH_SERVICE_PORT');
    final int port = int.tryParse(portValue) ??
        (throw StateError(
            'AUTH_SERVICE_PORT не валидное значение: $portValue'));

    final Uri baseUri = Uri(
      scheme: 'https',
      host: host,
      port: port,
      path: 'api/v1/',
    );

    final BaseOptions options = BaseOptions(
      baseUrl: baseUri.toString(),
      connectTimeout: const Duration(seconds: 300),
      receiveTimeout: const Duration(seconds: 300),
      sendTimeout: const Duration(seconds: 300),
      responseType: ResponseType.json,
    );

    final Dio dio = Dio(options);

    dio.httpClientAdapter = IOHttpClientAdapter()
      ..createHttpClient = () {
        final HttpClient httpClient = HttpClient(
          context: SecurityContext.defaultContext,
        );

        _applyProxyFromEnv(httpClient);

        httpClient.badCertificateCallback =
            (X509Certificate cert, String host, int port) {
          return true;
        };
        return httpClient;
      };

    return dio;
  }

  String _requireEnv(String key) {
    final String? value = dotenv.env[key];
    if (value == null || value.isEmpty) {
      throw StateError('$key не задан в энвах');
    }
    return value;
  }

  void _applyProxyFromEnv(HttpClient httpClient) {
    final String? host = dotenv.env['DIO_PROXY_HOST'];
    final String? portValue = dotenv.env['DIO_PROXY_PORT'];
    if (host == null ||
        host.isEmpty ||
        portValue == null ||
        portValue.isEmpty) {
      return;
    }

    final int? port = int.tryParse(portValue);
    if (port == null || port <= 0) {
      throw StateError('невалидный $portValue');
    }

    httpClient.findProxy = (Uri uri) => 'PROXY $host:$port';
  }
}
