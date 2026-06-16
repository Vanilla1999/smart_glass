import 'dart:convert';
import 'dart:developer';

import 'package:smart_glasses/modules/wear/data/auth/data_source/auth_data_source.dart';
import 'package:smart_glasses/modules/wear/data/auth/model/auth_user.dart';
import 'package:smart_glasses/modules/wear/domain/auth/model/authenticated_user.dart';

class AuthenticateUserUseCase {
  AuthenticateUserUseCase(this._authDataSource);

  final AuthDataSource _authDataSource;

  /// Аутентифицирует сотрудника по ШК и возвращает данные для UI.
  ///
  /// При ошибках аутентификации выбрасывает исключения с сообщением для UI.
  Future<AuthenticatedUser> call(String barcode) async {
    final String uuid = _getAuthUuid(barcode);
    log('barcode=$barcode', name: 'AuthenticateUserUseCase');
    log('uuid=$uuid', name: 'AuthenticateUserUseCase');
    final AuthUser user = await _authDataSource.authenticate(badgeUuid: uuid);
    return AuthenticatedUser(
      idUser: user.idUser,
      idEmployee: user.idEmpl,
      name: _formatShortName(
        lastName: user.lastName,
        firstName: user.name,
        fatherName: user.fatherName,
      ),
    );
  }

  /// Извлекает UUID из QR-кода.
  ///
  /// ШК сотрудника содержит несколько полей, плюс UUID там хранится
  /// не в формате, который ожидает сервер.
  String _getAuthUuid(String barcode) {
    // Пример содержимого:
    // {
    //    "uuid": "7032ea13-d572-4f38-82b7-d58dff896044",
    //    "kiscode": "CN0-119184",
    //    "version": 1
    // }
    try {
      final Map<String, dynamic> map =
          jsonDecode(barcode) as Map<String, dynamic>;
      final String rawUuid = map['uuid'] as String;
      return rawUuid.replaceAll('-', '').toUpperCase();
    } catch (e) {
      log('failed to parse badge barcode=$barcode error=$e',
          name: 'AuthenticateUserUseCase');
      throw Exception('Отсканирован неверный QR-код. '
          'Необходимо отсканировать QR-код сотрудника.');
    }
  }

  String _formatShortName({
    required String lastName,
    required String firstName,
    required String fatherName,
  }) {
    final String trimmedLastName = lastName.trim();
    final String firstInitial = _toInitial(firstName);
    final String fatherInitial = _toInitial(fatherName);

    return '$trimmedLastName $firstInitial$fatherInitial';
  }

  String _toInitial(String value) {
    final String trimmed = value.trim();
    if (trimmed.isEmpty) {
      return '';
    }
    return '${trimmed[0].toUpperCase()}.';
  }
}
