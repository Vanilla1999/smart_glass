// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'barcode_product_info.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

/// @nodoc
mixin _$BarcodeProductInfo {
  /// Идентификатор товарной позиции.
  int get id => throw _privateConstructorUsedError;

  ///  Наименование товара.
  String get name => throw _privateConstructorUsedError;

  /// Вес из ШК, если применимо.
  double? get weight => throw _privateConstructorUsedError;

  /// Учетный остаток, крч количество.
  double? get articleRest => throw _privateConstructorUsedError;

  /// Create a copy of BarcodeProductInfo
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $BarcodeProductInfoCopyWith<BarcodeProductInfo> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $BarcodeProductInfoCopyWith<$Res> {
  factory $BarcodeProductInfoCopyWith(
          BarcodeProductInfo value, $Res Function(BarcodeProductInfo) then) =
      _$BarcodeProductInfoCopyWithImpl<$Res, BarcodeProductInfo>;
  @useResult
  $Res call({int id, String name, double? weight, double? articleRest});
}

/// @nodoc
class _$BarcodeProductInfoCopyWithImpl<$Res, $Val extends BarcodeProductInfo>
    implements $BarcodeProductInfoCopyWith<$Res> {
  _$BarcodeProductInfoCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of BarcodeProductInfo
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? name = null,
    Object? weight = freezed,
    Object? articleRest = freezed,
  }) {
    return _then(_value.copyWith(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as int,
      name: null == name
          ? _value.name
          : name // ignore: cast_nullable_to_non_nullable
              as String,
      weight: freezed == weight
          ? _value.weight
          : weight // ignore: cast_nullable_to_non_nullable
              as double?,
      articleRest: freezed == articleRest
          ? _value.articleRest
          : articleRest // ignore: cast_nullable_to_non_nullable
              as double?,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$BarcodeProductInfoImplCopyWith<$Res>
    implements $BarcodeProductInfoCopyWith<$Res> {
  factory _$$BarcodeProductInfoImplCopyWith(_$BarcodeProductInfoImpl value,
          $Res Function(_$BarcodeProductInfoImpl) then) =
      __$$BarcodeProductInfoImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({int id, String name, double? weight, double? articleRest});
}

/// @nodoc
class __$$BarcodeProductInfoImplCopyWithImpl<$Res>
    extends _$BarcodeProductInfoCopyWithImpl<$Res, _$BarcodeProductInfoImpl>
    implements _$$BarcodeProductInfoImplCopyWith<$Res> {
  __$$BarcodeProductInfoImplCopyWithImpl(_$BarcodeProductInfoImpl _value,
      $Res Function(_$BarcodeProductInfoImpl) _then)
      : super(_value, _then);

  /// Create a copy of BarcodeProductInfo
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? name = null,
    Object? weight = freezed,
    Object? articleRest = freezed,
  }) {
    return _then(_$BarcodeProductInfoImpl(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as int,
      name: null == name
          ? _value.name
          : name // ignore: cast_nullable_to_non_nullable
              as String,
      weight: freezed == weight
          ? _value.weight
          : weight // ignore: cast_nullable_to_non_nullable
              as double?,
      articleRest: freezed == articleRest
          ? _value.articleRest
          : articleRest // ignore: cast_nullable_to_non_nullable
              as double?,
    ));
  }
}

/// @nodoc

class _$BarcodeProductInfoImpl implements _BarcodeProductInfo {
  _$BarcodeProductInfoImpl(
      {required this.id, required this.name, this.weight, this.articleRest});

  /// Идентификатор товарной позиции.
  @override
  final int id;

  ///  Наименование товара.
  @override
  final String name;

  /// Вес из ШК, если применимо.
  @override
  final double? weight;

  /// Учетный остаток, крч количество.
  @override
  final double? articleRest;

  @override
  String toString() {
    return 'BarcodeProductInfo(id: $id, name: $name, weight: $weight, articleRest: $articleRest)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$BarcodeProductInfoImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.name, name) || other.name == name) &&
            (identical(other.weight, weight) || other.weight == weight) &&
            (identical(other.articleRest, articleRest) ||
                other.articleRest == articleRest));
  }

  @override
  int get hashCode => Object.hash(runtimeType, id, name, weight, articleRest);

  /// Create a copy of BarcodeProductInfo
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$BarcodeProductInfoImplCopyWith<_$BarcodeProductInfoImpl> get copyWith =>
      __$$BarcodeProductInfoImplCopyWithImpl<_$BarcodeProductInfoImpl>(
          this, _$identity);
}

abstract class _BarcodeProductInfo implements BarcodeProductInfo {
  factory _BarcodeProductInfo(
      {required final int id,
      required final String name,
      final double? weight,
      final double? articleRest}) = _$BarcodeProductInfoImpl;

  /// Идентификатор товарной позиции.
  @override
  int get id;

  ///  Наименование товара.
  @override
  String get name;

  /// Вес из ШК, если применимо.
  @override
  double? get weight;

  /// Учетный остаток, крч количество.
  @override
  double? get articleRest;

  /// Create a copy of BarcodeProductInfo
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$BarcodeProductInfoImplCopyWith<_$BarcodeProductInfoImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
