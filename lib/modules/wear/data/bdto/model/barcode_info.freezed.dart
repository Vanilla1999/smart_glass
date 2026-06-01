// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'barcode_info.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

/// @nodoc
mixin _$BarcodeInfo {
  /// (`MODE`) Тип ШК.
  BarcodeType get mode => throw _privateConstructorUsedError;

  /// (`ID`) Идентификатор товарной позиции при сканировании ШК товара
  /// или ценника. Для принтера всегда `null`.
  int? get entityId => throw _privateConstructorUsedError;

  /// (`MES`) Служебное сообщение. Не содержит значимых данных.
  String? get message => throw _privateConstructorUsedError;

  /// (`NAME`) Имя принтера или наименование товара.
  String? get name => throw _privateConstructorUsedError;

  /// (`WEIGHT`) Для ШК товара - вес из ШК. Если вес не найден (в режиме G) - `null`.
  double? get weight => throw _privateConstructorUsedError;

  /// (`ID_PLARTPRICE`) Для ШК ценника - ID прайслиста. Для остальных - `null`.
  int? get priceListId => throw _privateConstructorUsedError;

  /// (`ID_NOTART`) Для ШК ценника - ID ценника. Для остальных - `null`.
  int? get priceTagId => throw _privateConstructorUsedError;

  /// (`ARTREST`) Учетный остаток для ШК ценника или товара.
  double? get articleRest => throw _privateConstructorUsedError;

  /// (`ARTRESTLOT`) Партионный остаток для ШК ценника или товара.
  double? get articleRestLot => throw _privateConstructorUsedError;

  /// Create a copy of BarcodeInfo
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $BarcodeInfoCopyWith<BarcodeInfo> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $BarcodeInfoCopyWith<$Res> {
  factory $BarcodeInfoCopyWith(
          BarcodeInfo value, $Res Function(BarcodeInfo) then) =
      _$BarcodeInfoCopyWithImpl<$Res, BarcodeInfo>;
  @useResult
  $Res call(
      {BarcodeType mode,
      int? entityId,
      String? message,
      String? name,
      double? weight,
      int? priceListId,
      int? priceTagId,
      double? articleRest,
      double? articleRestLot});
}

/// @nodoc
class _$BarcodeInfoCopyWithImpl<$Res, $Val extends BarcodeInfo>
    implements $BarcodeInfoCopyWith<$Res> {
  _$BarcodeInfoCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of BarcodeInfo
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? mode = null,
    Object? entityId = freezed,
    Object? message = freezed,
    Object? name = freezed,
    Object? weight = freezed,
    Object? priceListId = freezed,
    Object? priceTagId = freezed,
    Object? articleRest = freezed,
    Object? articleRestLot = freezed,
  }) {
    return _then(_value.copyWith(
      mode: null == mode
          ? _value.mode
          : mode // ignore: cast_nullable_to_non_nullable
              as BarcodeType,
      entityId: freezed == entityId
          ? _value.entityId
          : entityId // ignore: cast_nullable_to_non_nullable
              as int?,
      message: freezed == message
          ? _value.message
          : message // ignore: cast_nullable_to_non_nullable
              as String?,
      name: freezed == name
          ? _value.name
          : name // ignore: cast_nullable_to_non_nullable
              as String?,
      weight: freezed == weight
          ? _value.weight
          : weight // ignore: cast_nullable_to_non_nullable
              as double?,
      priceListId: freezed == priceListId
          ? _value.priceListId
          : priceListId // ignore: cast_nullable_to_non_nullable
              as int?,
      priceTagId: freezed == priceTagId
          ? _value.priceTagId
          : priceTagId // ignore: cast_nullable_to_non_nullable
              as int?,
      articleRest: freezed == articleRest
          ? _value.articleRest
          : articleRest // ignore: cast_nullable_to_non_nullable
              as double?,
      articleRestLot: freezed == articleRestLot
          ? _value.articleRestLot
          : articleRestLot // ignore: cast_nullable_to_non_nullable
              as double?,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$BarcodeInfoImplCopyWith<$Res>
    implements $BarcodeInfoCopyWith<$Res> {
  factory _$$BarcodeInfoImplCopyWith(
          _$BarcodeInfoImpl value, $Res Function(_$BarcodeInfoImpl) then) =
      __$$BarcodeInfoImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {BarcodeType mode,
      int? entityId,
      String? message,
      String? name,
      double? weight,
      int? priceListId,
      int? priceTagId,
      double? articleRest,
      double? articleRestLot});
}

/// @nodoc
class __$$BarcodeInfoImplCopyWithImpl<$Res>
    extends _$BarcodeInfoCopyWithImpl<$Res, _$BarcodeInfoImpl>
    implements _$$BarcodeInfoImplCopyWith<$Res> {
  __$$BarcodeInfoImplCopyWithImpl(
      _$BarcodeInfoImpl _value, $Res Function(_$BarcodeInfoImpl) _then)
      : super(_value, _then);

  /// Create a copy of BarcodeInfo
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? mode = null,
    Object? entityId = freezed,
    Object? message = freezed,
    Object? name = freezed,
    Object? weight = freezed,
    Object? priceListId = freezed,
    Object? priceTagId = freezed,
    Object? articleRest = freezed,
    Object? articleRestLot = freezed,
  }) {
    return _then(_$BarcodeInfoImpl(
      mode: null == mode
          ? _value.mode
          : mode // ignore: cast_nullable_to_non_nullable
              as BarcodeType,
      entityId: freezed == entityId
          ? _value.entityId
          : entityId // ignore: cast_nullable_to_non_nullable
              as int?,
      message: freezed == message
          ? _value.message
          : message // ignore: cast_nullable_to_non_nullable
              as String?,
      name: freezed == name
          ? _value.name
          : name // ignore: cast_nullable_to_non_nullable
              as String?,
      weight: freezed == weight
          ? _value.weight
          : weight // ignore: cast_nullable_to_non_nullable
              as double?,
      priceListId: freezed == priceListId
          ? _value.priceListId
          : priceListId // ignore: cast_nullable_to_non_nullable
              as int?,
      priceTagId: freezed == priceTagId
          ? _value.priceTagId
          : priceTagId // ignore: cast_nullable_to_non_nullable
              as int?,
      articleRest: freezed == articleRest
          ? _value.articleRest
          : articleRest // ignore: cast_nullable_to_non_nullable
              as double?,
      articleRestLot: freezed == articleRestLot
          ? _value.articleRestLot
          : articleRestLot // ignore: cast_nullable_to_non_nullable
              as double?,
    ));
  }
}

/// @nodoc

class _$BarcodeInfoImpl implements _BarcodeInfo {
  _$BarcodeInfoImpl(
      {required this.mode,
      this.entityId,
      this.message,
      this.name,
      this.weight,
      this.priceListId,
      this.priceTagId,
      this.articleRest,
      this.articleRestLot});

  /// (`MODE`) Тип ШК.
  @override
  final BarcodeType mode;

  /// (`ID`) Идентификатор товарной позиции при сканировании ШК товара
  /// или ценника. Для принтера всегда `null`.
  @override
  final int? entityId;

  /// (`MES`) Служебное сообщение. Не содержит значимых данных.
  @override
  final String? message;

  /// (`NAME`) Имя принтера или наименование товара.
  @override
  final String? name;

  /// (`WEIGHT`) Для ШК товара - вес из ШК. Если вес не найден (в режиме G) - `null`.
  @override
  final double? weight;

  /// (`ID_PLARTPRICE`) Для ШК ценника - ID прайслиста. Для остальных - `null`.
  @override
  final int? priceListId;

  /// (`ID_NOTART`) Для ШК ценника - ID ценника. Для остальных - `null`.
  @override
  final int? priceTagId;

  /// (`ARTREST`) Учетный остаток для ШК ценника или товара.
  @override
  final double? articleRest;

  /// (`ARTRESTLOT`) Партионный остаток для ШК ценника или товара.
  @override
  final double? articleRestLot;

  @override
  String toString() {
    return 'BarcodeInfo(mode: $mode, entityId: $entityId, message: $message, name: $name, weight: $weight, priceListId: $priceListId, priceTagId: $priceTagId, articleRest: $articleRest, articleRestLot: $articleRestLot)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$BarcodeInfoImpl &&
            (identical(other.mode, mode) || other.mode == mode) &&
            (identical(other.entityId, entityId) ||
                other.entityId == entityId) &&
            (identical(other.message, message) || other.message == message) &&
            (identical(other.name, name) || other.name == name) &&
            (identical(other.weight, weight) || other.weight == weight) &&
            (identical(other.priceListId, priceListId) ||
                other.priceListId == priceListId) &&
            (identical(other.priceTagId, priceTagId) ||
                other.priceTagId == priceTagId) &&
            (identical(other.articleRest, articleRest) ||
                other.articleRest == articleRest) &&
            (identical(other.articleRestLot, articleRestLot) ||
                other.articleRestLot == articleRestLot));
  }

  @override
  int get hashCode => Object.hash(runtimeType, mode, entityId, message, name,
      weight, priceListId, priceTagId, articleRest, articleRestLot);

  /// Create a copy of BarcodeInfo
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$BarcodeInfoImplCopyWith<_$BarcodeInfoImpl> get copyWith =>
      __$$BarcodeInfoImplCopyWithImpl<_$BarcodeInfoImpl>(this, _$identity);
}

abstract class _BarcodeInfo implements BarcodeInfo {
  factory _BarcodeInfo(
      {required final BarcodeType mode,
      final int? entityId,
      final String? message,
      final String? name,
      final double? weight,
      final int? priceListId,
      final int? priceTagId,
      final double? articleRest,
      final double? articleRestLot}) = _$BarcodeInfoImpl;

  /// (`MODE`) Тип ШК.
  @override
  BarcodeType get mode;

  /// (`ID`) Идентификатор товарной позиции при сканировании ШК товара
  /// или ценника. Для принтера всегда `null`.
  @override
  int? get entityId;

  /// (`MES`) Служебное сообщение. Не содержит значимых данных.
  @override
  String? get message;

  /// (`NAME`) Имя принтера или наименование товара.
  @override
  String? get name;

  /// (`WEIGHT`) Для ШК товара - вес из ШК. Если вес не найден (в режиме G) - `null`.
  @override
  double? get weight;

  /// (`ID_PLARTPRICE`) Для ШК ценника - ID прайслиста. Для остальных - `null`.
  @override
  int? get priceListId;

  /// (`ID_NOTART`) Для ШК ценника - ID ценника. Для остальных - `null`.
  @override
  int? get priceTagId;

  /// (`ARTREST`) Учетный остаток для ШК ценника или товара.
  @override
  double? get articleRest;

  /// (`ARTRESTLOT`) Партионный остаток для ШК ценника или товара.
  @override
  double? get articleRestLot;

  /// Create a copy of BarcodeInfo
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$BarcodeInfoImplCopyWith<_$BarcodeInfoImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
