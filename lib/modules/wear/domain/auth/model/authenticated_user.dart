import 'package:freezed_annotation/freezed_annotation.dart';

part 'authenticated_user.freezed.dart';

@freezed
class AuthenticatedUser with _$AuthenticatedUser {
  factory AuthenticatedUser({
    required int idUser,
    required int idEmployee,
    required String name,
  }) = _AuthenticatedUser;
}
