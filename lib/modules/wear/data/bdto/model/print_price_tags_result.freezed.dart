// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'print_price_tags_result.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

/// @nodoc
mixin _$PrintPriceTagsResult {
  /// (`RES_CODE`) Код результата.
  int get resultCode => throw _privateConstructorUsedError;

  /// (`RES_TEXT`) Текст ошибки, если `RES_CODE = -1`.
  String get message => throw _privateConstructorUsedError;

  /// Create a copy of PrintPriceTagsResult
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $PrintPriceTagsResultCopyWith<PrintPriceTagsResult> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $PrintPriceTagsResultCopyWith<$Res> {
  factory $PrintPriceTagsResultCopyWith(PrintPriceTagsResult value,
          $Res Function(PrintPriceTagsResult) then) =
      _$PrintPriceTagsResultCopyWithImpl<$Res, PrintPriceTagsResult>;
  @useResult
  $Res call({int resultCode, String message});
}

/// @nodoc
class _$PrintPriceTagsResultCopyWithImpl<$Res,
        $Val extends PrintPriceTagsResult>
    implements $PrintPriceTagsResultCopyWith<$Res> {
  _$PrintPriceTagsResultCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of PrintPriceTagsResult
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? resultCode = null,
    Object? message = null,
  }) {
    return _then(_value.copyWith(
      resultCode: null == resultCode
          ? _value.resultCode
          : resultCode // ignore: cast_nullable_to_non_nullable
              as int,
      message: null == message
          ? _value.message
          : message // ignore: cast_nullable_to_non_nullable
              as String,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$PrintPriceTagsResultImplCopyWith<$Res>
    implements $PrintPriceTagsResultCopyWith<$Res> {
  factory _$$PrintPriceTagsResultImplCopyWith(_$PrintPriceTagsResultImpl value,
          $Res Function(_$PrintPriceTagsResultImpl) then) =
      __$$PrintPriceTagsResultImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({int resultCode, String message});
}

/// @nodoc
class __$$PrintPriceTagsResultImplCopyWithImpl<$Res>
    extends _$PrintPriceTagsResultCopyWithImpl<$Res, _$PrintPriceTagsResultImpl>
    implements _$$PrintPriceTagsResultImplCopyWith<$Res> {
  __$$PrintPriceTagsResultImplCopyWithImpl(_$PrintPriceTagsResultImpl _value,
      $Res Function(_$PrintPriceTagsResultImpl) _then)
      : super(_value, _then);

  /// Create a copy of PrintPriceTagsResult
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? resultCode = null,
    Object? message = null,
  }) {
    return _then(_$PrintPriceTagsResultImpl(
      resultCode: null == resultCode
          ? _value.resultCode
          : resultCode // ignore: cast_nullable_to_non_nullable
              as int,
      message: null == message
          ? _value.message
          : message // ignore: cast_nullable_to_non_nullable
              as String,
    ));
  }
}

/// @nodoc

class _$PrintPriceTagsResultImpl implements _PrintPriceTagsResult {
  _$PrintPriceTagsResultImpl({required this.resultCode, required this.message});

  /// (`RES_CODE`) Код результата.
  @override
  final int resultCode;

  /// (`RES_TEXT`) Текст ошибки, если `RES_CODE = -1`.
  @override
  final String message;

  @override
  String toString() {
    return 'PrintPriceTagsResult(resultCode: $resultCode, message: $message)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$PrintPriceTagsResultImpl &&
            (identical(other.resultCode, resultCode) ||
                other.resultCode == resultCode) &&
            (identical(other.message, message) || other.message == message));
  }

  @override
  int get hashCode => Object.hash(runtimeType, resultCode, message);

  /// Create a copy of PrintPriceTagsResult
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$PrintPriceTagsResultImplCopyWith<_$PrintPriceTagsResultImpl>
      get copyWith =>
          __$$PrintPriceTagsResultImplCopyWithImpl<_$PrintPriceTagsResultImpl>(
              this, _$identity);
}

abstract class _PrintPriceTagsResult implements PrintPriceTagsResult {
  factory _PrintPriceTagsResult(
      {required final int resultCode,
      required final String message}) = _$PrintPriceTagsResultImpl;

  /// (`RES_CODE`) Код результата.
  @override
  int get resultCode;

  /// (`RES_TEXT`) Текст ошибки, если `RES_CODE = -1`.
  @override
  String get message;

  /// Create a copy of PrintPriceTagsResult
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$PrintPriceTagsResultImplCopyWith<_$PrintPriceTagsResultImpl>
      get copyWith => throw _privateConstructorUsedError;
}
