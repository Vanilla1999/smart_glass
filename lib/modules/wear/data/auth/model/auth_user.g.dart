// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'auth_user.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$AuthUserImpl _$$AuthUserImplFromJson(Map<String, dynamic> json) =>
    _$AuthUserImpl(
      idUser: (json['id_user'] as num).toInt(),
      alias: json['alias'] as String,
      isActive: json['isactive'] as String,
      username: json['username'] as String,
      fullName: json['fullname'] as String,
      idEmpl: (json['id_empl'] as num).toInt(),
      lastName: json['lastname'] as String,
      name: json['name'] as String,
      fatherName: json['fathername'] as String,
      keycode: json['keycode'] as String,
      occType: json['occtype'] as String,
      occName: json['occname'] as String,
      divName: json['divname'] as String,
    );

Map<String, dynamic> _$$AuthUserImplToJson(_$AuthUserImpl instance) =>
    <String, dynamic>{
      'id_user': instance.idUser,
      'alias': instance.alias,
      'isactive': instance.isActive,
      'username': instance.username,
      'fullname': instance.fullName,
      'id_empl': instance.idEmpl,
      'lastname': instance.lastName,
      'name': instance.name,
      'fathername': instance.fatherName,
      'keycode': instance.keycode,
      'occtype': instance.occType,
      'occname': instance.occName,
      'divname': instance.divName,
    };
