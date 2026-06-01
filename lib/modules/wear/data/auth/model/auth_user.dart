import 'package:freezed_annotation/freezed_annotation.dart';

part 'auth_user.freezed.dart';
part 'auth_user.g.dart';

@freezed
class AuthUser with _$AuthUser {
  const factory AuthUser({
    @JsonKey(name: 'id_user') required int idUser,
    @JsonKey(name: 'alias') required String alias,
    @JsonKey(name: 'isactive') required String isActive,
    @JsonKey(name: 'username') required String username,
    @JsonKey(name: 'fullname') required String fullName,
    @JsonKey(name: 'id_empl') required int idEmpl,
    @JsonKey(name: 'lastname') required String lastName,
    @JsonKey(name: 'name') required String name,
    @JsonKey(name: 'fathername') required String fatherName,
    @JsonKey(name: 'keycode') required String keycode,
    @JsonKey(name: 'occtype') required String occType,
    @JsonKey(name: 'occname') required String occName,
    @JsonKey(name: 'divname') required String divName,
  }) = _AuthUser;

  factory AuthUser.fromJson(Map<String, Object?> json) =>
      _$AuthUserFromJson(json);
}
