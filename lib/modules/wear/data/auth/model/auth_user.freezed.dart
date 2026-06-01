// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'auth_user.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

AuthUser _$AuthUserFromJson(Map<String, dynamic> json) {
  return _AuthUser.fromJson(json);
}

/// @nodoc
mixin _$AuthUser {
  @JsonKey(name: 'id_user')
  int get idUser => throw _privateConstructorUsedError;
  @JsonKey(name: 'alias')
  String get alias => throw _privateConstructorUsedError;
  @JsonKey(name: 'isactive')
  String get isActive => throw _privateConstructorUsedError;
  @JsonKey(name: 'username')
  String get username => throw _privateConstructorUsedError;
  @JsonKey(name: 'fullname')
  String get fullName => throw _privateConstructorUsedError;
  @JsonKey(name: 'id_empl')
  int get idEmpl => throw _privateConstructorUsedError;
  @JsonKey(name: 'lastname')
  String get lastName => throw _privateConstructorUsedError;
  @JsonKey(name: 'name')
  String get name => throw _privateConstructorUsedError;
  @JsonKey(name: 'fathername')
  String get fatherName => throw _privateConstructorUsedError;
  @JsonKey(name: 'keycode')
  String get keycode => throw _privateConstructorUsedError;
  @JsonKey(name: 'occtype')
  String get occType => throw _privateConstructorUsedError;
  @JsonKey(name: 'occname')
  String get occName => throw _privateConstructorUsedError;
  @JsonKey(name: 'divname')
  String get divName => throw _privateConstructorUsedError;

  /// Serializes this AuthUser to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of AuthUser
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $AuthUserCopyWith<AuthUser> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $AuthUserCopyWith<$Res> {
  factory $AuthUserCopyWith(AuthUser value, $Res Function(AuthUser) then) =
      _$AuthUserCopyWithImpl<$Res, AuthUser>;
  @useResult
  $Res call(
      {@JsonKey(name: 'id_user') int idUser,
      @JsonKey(name: 'alias') String alias,
      @JsonKey(name: 'isactive') String isActive,
      @JsonKey(name: 'username') String username,
      @JsonKey(name: 'fullname') String fullName,
      @JsonKey(name: 'id_empl') int idEmpl,
      @JsonKey(name: 'lastname') String lastName,
      @JsonKey(name: 'name') String name,
      @JsonKey(name: 'fathername') String fatherName,
      @JsonKey(name: 'keycode') String keycode,
      @JsonKey(name: 'occtype') String occType,
      @JsonKey(name: 'occname') String occName,
      @JsonKey(name: 'divname') String divName});
}

/// @nodoc
class _$AuthUserCopyWithImpl<$Res, $Val extends AuthUser>
    implements $AuthUserCopyWith<$Res> {
  _$AuthUserCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of AuthUser
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? idUser = null,
    Object? alias = null,
    Object? isActive = null,
    Object? username = null,
    Object? fullName = null,
    Object? idEmpl = null,
    Object? lastName = null,
    Object? name = null,
    Object? fatherName = null,
    Object? keycode = null,
    Object? occType = null,
    Object? occName = null,
    Object? divName = null,
  }) {
    return _then(_value.copyWith(
      idUser: null == idUser
          ? _value.idUser
          : idUser // ignore: cast_nullable_to_non_nullable
              as int,
      alias: null == alias
          ? _value.alias
          : alias // ignore: cast_nullable_to_non_nullable
              as String,
      isActive: null == isActive
          ? _value.isActive
          : isActive // ignore: cast_nullable_to_non_nullable
              as String,
      username: null == username
          ? _value.username
          : username // ignore: cast_nullable_to_non_nullable
              as String,
      fullName: null == fullName
          ? _value.fullName
          : fullName // ignore: cast_nullable_to_non_nullable
              as String,
      idEmpl: null == idEmpl
          ? _value.idEmpl
          : idEmpl // ignore: cast_nullable_to_non_nullable
              as int,
      lastName: null == lastName
          ? _value.lastName
          : lastName // ignore: cast_nullable_to_non_nullable
              as String,
      name: null == name
          ? _value.name
          : name // ignore: cast_nullable_to_non_nullable
              as String,
      fatherName: null == fatherName
          ? _value.fatherName
          : fatherName // ignore: cast_nullable_to_non_nullable
              as String,
      keycode: null == keycode
          ? _value.keycode
          : keycode // ignore: cast_nullable_to_non_nullable
              as String,
      occType: null == occType
          ? _value.occType
          : occType // ignore: cast_nullable_to_non_nullable
              as String,
      occName: null == occName
          ? _value.occName
          : occName // ignore: cast_nullable_to_non_nullable
              as String,
      divName: null == divName
          ? _value.divName
          : divName // ignore: cast_nullable_to_non_nullable
              as String,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$AuthUserImplCopyWith<$Res>
    implements $AuthUserCopyWith<$Res> {
  factory _$$AuthUserImplCopyWith(
          _$AuthUserImpl value, $Res Function(_$AuthUserImpl) then) =
      __$$AuthUserImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {@JsonKey(name: 'id_user') int idUser,
      @JsonKey(name: 'alias') String alias,
      @JsonKey(name: 'isactive') String isActive,
      @JsonKey(name: 'username') String username,
      @JsonKey(name: 'fullname') String fullName,
      @JsonKey(name: 'id_empl') int idEmpl,
      @JsonKey(name: 'lastname') String lastName,
      @JsonKey(name: 'name') String name,
      @JsonKey(name: 'fathername') String fatherName,
      @JsonKey(name: 'keycode') String keycode,
      @JsonKey(name: 'occtype') String occType,
      @JsonKey(name: 'occname') String occName,
      @JsonKey(name: 'divname') String divName});
}

/// @nodoc
class __$$AuthUserImplCopyWithImpl<$Res>
    extends _$AuthUserCopyWithImpl<$Res, _$AuthUserImpl>
    implements _$$AuthUserImplCopyWith<$Res> {
  __$$AuthUserImplCopyWithImpl(
      _$AuthUserImpl _value, $Res Function(_$AuthUserImpl) _then)
      : super(_value, _then);

  /// Create a copy of AuthUser
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? idUser = null,
    Object? alias = null,
    Object? isActive = null,
    Object? username = null,
    Object? fullName = null,
    Object? idEmpl = null,
    Object? lastName = null,
    Object? name = null,
    Object? fatherName = null,
    Object? keycode = null,
    Object? occType = null,
    Object? occName = null,
    Object? divName = null,
  }) {
    return _then(_$AuthUserImpl(
      idUser: null == idUser
          ? _value.idUser
          : idUser // ignore: cast_nullable_to_non_nullable
              as int,
      alias: null == alias
          ? _value.alias
          : alias // ignore: cast_nullable_to_non_nullable
              as String,
      isActive: null == isActive
          ? _value.isActive
          : isActive // ignore: cast_nullable_to_non_nullable
              as String,
      username: null == username
          ? _value.username
          : username // ignore: cast_nullable_to_non_nullable
              as String,
      fullName: null == fullName
          ? _value.fullName
          : fullName // ignore: cast_nullable_to_non_nullable
              as String,
      idEmpl: null == idEmpl
          ? _value.idEmpl
          : idEmpl // ignore: cast_nullable_to_non_nullable
              as int,
      lastName: null == lastName
          ? _value.lastName
          : lastName // ignore: cast_nullable_to_non_nullable
              as String,
      name: null == name
          ? _value.name
          : name // ignore: cast_nullable_to_non_nullable
              as String,
      fatherName: null == fatherName
          ? _value.fatherName
          : fatherName // ignore: cast_nullable_to_non_nullable
              as String,
      keycode: null == keycode
          ? _value.keycode
          : keycode // ignore: cast_nullable_to_non_nullable
              as String,
      occType: null == occType
          ? _value.occType
          : occType // ignore: cast_nullable_to_non_nullable
              as String,
      occName: null == occName
          ? _value.occName
          : occName // ignore: cast_nullable_to_non_nullable
              as String,
      divName: null == divName
          ? _value.divName
          : divName // ignore: cast_nullable_to_non_nullable
              as String,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$AuthUserImpl implements _AuthUser {
  const _$AuthUserImpl(
      {@JsonKey(name: 'id_user') required this.idUser,
      @JsonKey(name: 'alias') required this.alias,
      @JsonKey(name: 'isactive') required this.isActive,
      @JsonKey(name: 'username') required this.username,
      @JsonKey(name: 'fullname') required this.fullName,
      @JsonKey(name: 'id_empl') required this.idEmpl,
      @JsonKey(name: 'lastname') required this.lastName,
      @JsonKey(name: 'name') required this.name,
      @JsonKey(name: 'fathername') required this.fatherName,
      @JsonKey(name: 'keycode') required this.keycode,
      @JsonKey(name: 'occtype') required this.occType,
      @JsonKey(name: 'occname') required this.occName,
      @JsonKey(name: 'divname') required this.divName});

  factory _$AuthUserImpl.fromJson(Map<String, dynamic> json) =>
      _$$AuthUserImplFromJson(json);

  @override
  @JsonKey(name: 'id_user')
  final int idUser;
  @override
  @JsonKey(name: 'alias')
  final String alias;
  @override
  @JsonKey(name: 'isactive')
  final String isActive;
  @override
  @JsonKey(name: 'username')
  final String username;
  @override
  @JsonKey(name: 'fullname')
  final String fullName;
  @override
  @JsonKey(name: 'id_empl')
  final int idEmpl;
  @override
  @JsonKey(name: 'lastname')
  final String lastName;
  @override
  @JsonKey(name: 'name')
  final String name;
  @override
  @JsonKey(name: 'fathername')
  final String fatherName;
  @override
  @JsonKey(name: 'keycode')
  final String keycode;
  @override
  @JsonKey(name: 'occtype')
  final String occType;
  @override
  @JsonKey(name: 'occname')
  final String occName;
  @override
  @JsonKey(name: 'divname')
  final String divName;

  @override
  String toString() {
    return 'AuthUser(idUser: $idUser, alias: $alias, isActive: $isActive, username: $username, fullName: $fullName, idEmpl: $idEmpl, lastName: $lastName, name: $name, fatherName: $fatherName, keycode: $keycode, occType: $occType, occName: $occName, divName: $divName)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$AuthUserImpl &&
            (identical(other.idUser, idUser) || other.idUser == idUser) &&
            (identical(other.alias, alias) || other.alias == alias) &&
            (identical(other.isActive, isActive) ||
                other.isActive == isActive) &&
            (identical(other.username, username) ||
                other.username == username) &&
            (identical(other.fullName, fullName) ||
                other.fullName == fullName) &&
            (identical(other.idEmpl, idEmpl) || other.idEmpl == idEmpl) &&
            (identical(other.lastName, lastName) ||
                other.lastName == lastName) &&
            (identical(other.name, name) || other.name == name) &&
            (identical(other.fatherName, fatherName) ||
                other.fatherName == fatherName) &&
            (identical(other.keycode, keycode) || other.keycode == keycode) &&
            (identical(other.occType, occType) || other.occType == occType) &&
            (identical(other.occName, occName) || other.occName == occName) &&
            (identical(other.divName, divName) || other.divName == divName));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      idUser,
      alias,
      isActive,
      username,
      fullName,
      idEmpl,
      lastName,
      name,
      fatherName,
      keycode,
      occType,
      occName,
      divName);

  /// Create a copy of AuthUser
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$AuthUserImplCopyWith<_$AuthUserImpl> get copyWith =>
      __$$AuthUserImplCopyWithImpl<_$AuthUserImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$AuthUserImplToJson(
      this,
    );
  }
}

abstract class _AuthUser implements AuthUser {
  const factory _AuthUser(
          {@JsonKey(name: 'id_user') required final int idUser,
          @JsonKey(name: 'alias') required final String alias,
          @JsonKey(name: 'isactive') required final String isActive,
          @JsonKey(name: 'username') required final String username,
          @JsonKey(name: 'fullname') required final String fullName,
          @JsonKey(name: 'id_empl') required final int idEmpl,
          @JsonKey(name: 'lastname') required final String lastName,
          @JsonKey(name: 'name') required final String name,
          @JsonKey(name: 'fathername') required final String fatherName,
          @JsonKey(name: 'keycode') required final String keycode,
          @JsonKey(name: 'occtype') required final String occType,
          @JsonKey(name: 'occname') required final String occName,
          @JsonKey(name: 'divname') required final String divName}) =
      _$AuthUserImpl;

  factory _AuthUser.fromJson(Map<String, dynamic> json) =
      _$AuthUserImpl.fromJson;

  @override
  @JsonKey(name: 'id_user')
  int get idUser;
  @override
  @JsonKey(name: 'alias')
  String get alias;
  @override
  @JsonKey(name: 'isactive')
  String get isActive;
  @override
  @JsonKey(name: 'username')
  String get username;
  @override
  @JsonKey(name: 'fullname')
  String get fullName;
  @override
  @JsonKey(name: 'id_empl')
  int get idEmpl;
  @override
  @JsonKey(name: 'lastname')
  String get lastName;
  @override
  @JsonKey(name: 'name')
  String get name;
  @override
  @JsonKey(name: 'fathername')
  String get fatherName;
  @override
  @JsonKey(name: 'keycode')
  String get keycode;
  @override
  @JsonKey(name: 'occtype')
  String get occType;
  @override
  @JsonKey(name: 'occname')
  String get occName;
  @override
  @JsonKey(name: 'divname')
  String get divName;

  /// Create a copy of AuthUser
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$AuthUserImplCopyWith<_$AuthUserImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
