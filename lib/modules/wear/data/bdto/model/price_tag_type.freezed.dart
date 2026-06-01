// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'price_tag_type.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

/// @nodoc
mixin _$PriceTagType {
  /// (`RID_REPORT`) Идентификатор отчета.
  int get reportId => throw _privateConstructorUsedError;

  /// (`RCAPTION`) Человекочитаемое наименование формата.
  String get caption => throw _privateConstructorUsedError;

  /// (`RSCHEME`) Код формата.
  String get scheme => throw _privateConstructorUsedError;

  /// (`RSORTER`) Поле сортировки.
  int get sortOrder => throw _privateConstructorUsedError;

  /// Create a copy of PriceTagType
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $PriceTagTypeCopyWith<PriceTagType> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $PriceTagTypeCopyWith<$Res> {
  factory $PriceTagTypeCopyWith(
          PriceTagType value, $Res Function(PriceTagType) then) =
      _$PriceTagTypeCopyWithImpl<$Res, PriceTagType>;
  @useResult
  $Res call({int reportId, String caption, String scheme, int sortOrder});
}

/// @nodoc
class _$PriceTagTypeCopyWithImpl<$Res, $Val extends PriceTagType>
    implements $PriceTagTypeCopyWith<$Res> {
  _$PriceTagTypeCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of PriceTagType
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? reportId = null,
    Object? caption = null,
    Object? scheme = null,
    Object? sortOrder = null,
  }) {
    return _then(_value.copyWith(
      reportId: null == reportId
          ? _value.reportId
          : reportId // ignore: cast_nullable_to_non_nullable
              as int,
      caption: null == caption
          ? _value.caption
          : caption // ignore: cast_nullable_to_non_nullable
              as String,
      scheme: null == scheme
          ? _value.scheme
          : scheme // ignore: cast_nullable_to_non_nullable
              as String,
      sortOrder: null == sortOrder
          ? _value.sortOrder
          : sortOrder // ignore: cast_nullable_to_non_nullable
              as int,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$PriceTagTypeImplCopyWith<$Res>
    implements $PriceTagTypeCopyWith<$Res> {
  factory _$$PriceTagTypeImplCopyWith(
          _$PriceTagTypeImpl value, $Res Function(_$PriceTagTypeImpl) then) =
      __$$PriceTagTypeImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({int reportId, String caption, String scheme, int sortOrder});
}

/// @nodoc
class __$$PriceTagTypeImplCopyWithImpl<$Res>
    extends _$PriceTagTypeCopyWithImpl<$Res, _$PriceTagTypeImpl>
    implements _$$PriceTagTypeImplCopyWith<$Res> {
  __$$PriceTagTypeImplCopyWithImpl(
      _$PriceTagTypeImpl _value, $Res Function(_$PriceTagTypeImpl) _then)
      : super(_value, _then);

  /// Create a copy of PriceTagType
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? reportId = null,
    Object? caption = null,
    Object? scheme = null,
    Object? sortOrder = null,
  }) {
    return _then(_$PriceTagTypeImpl(
      reportId: null == reportId
          ? _value.reportId
          : reportId // ignore: cast_nullable_to_non_nullable
              as int,
      caption: null == caption
          ? _value.caption
          : caption // ignore: cast_nullable_to_non_nullable
              as String,
      scheme: null == scheme
          ? _value.scheme
          : scheme // ignore: cast_nullable_to_non_nullable
              as String,
      sortOrder: null == sortOrder
          ? _value.sortOrder
          : sortOrder // ignore: cast_nullable_to_non_nullable
              as int,
    ));
  }
}

/// @nodoc

class _$PriceTagTypeImpl implements _PriceTagType {
  _$PriceTagTypeImpl(
      {required this.reportId,
      required this.caption,
      required this.scheme,
      required this.sortOrder});

  /// (`RID_REPORT`) Идентификатор отчета.
  @override
  final int reportId;

  /// (`RCAPTION`) Человекочитаемое наименование формата.
  @override
  final String caption;

  /// (`RSCHEME`) Код формата.
  @override
  final String scheme;

  /// (`RSORTER`) Поле сортировки.
  @override
  final int sortOrder;

  @override
  String toString() {
    return 'PriceTagType(reportId: $reportId, caption: $caption, scheme: $scheme, sortOrder: $sortOrder)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$PriceTagTypeImpl &&
            (identical(other.reportId, reportId) ||
                other.reportId == reportId) &&
            (identical(other.caption, caption) || other.caption == caption) &&
            (identical(other.scheme, scheme) || other.scheme == scheme) &&
            (identical(other.sortOrder, sortOrder) ||
                other.sortOrder == sortOrder));
  }

  @override
  int get hashCode =>
      Object.hash(runtimeType, reportId, caption, scheme, sortOrder);

  /// Create a copy of PriceTagType
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$PriceTagTypeImplCopyWith<_$PriceTagTypeImpl> get copyWith =>
      __$$PriceTagTypeImplCopyWithImpl<_$PriceTagTypeImpl>(this, _$identity);
}

abstract class _PriceTagType implements PriceTagType {
  factory _PriceTagType(
      {required final int reportId,
      required final String caption,
      required final String scheme,
      required final int sortOrder}) = _$PriceTagTypeImpl;

  /// (`RID_REPORT`) Идентификатор отчета.
  @override
  int get reportId;

  /// (`RCAPTION`) Человекочитаемое наименование формата.
  @override
  String get caption;

  /// (`RSCHEME`) Код формата.
  @override
  String get scheme;

  /// (`RSORTER`) Поле сортировки.
  @override
  int get sortOrder;

  /// Create a copy of PriceTagType
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$PriceTagTypeImplCopyWith<_$PriceTagTypeImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
