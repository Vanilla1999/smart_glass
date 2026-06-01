// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'printer_selection_result.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

/// @nodoc
mixin _$PrinterSelectionResult {
  /// (`RES_CODE`) Тип выбора принтера для текущего объекта.
  PrinterSelectionType get selectionType => throw _privateConstructorUsedError;

  /// (`RES`) Человекочитаемое описание.
  String get message => throw _privateConstructorUsedError;

  /// Create a copy of PrinterSelectionResult
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $PrinterSelectionResultCopyWith<PrinterSelectionResult> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $PrinterSelectionResultCopyWith<$Res> {
  factory $PrinterSelectionResultCopyWith(PrinterSelectionResult value,
          $Res Function(PrinterSelectionResult) then) =
      _$PrinterSelectionResultCopyWithImpl<$Res, PrinterSelectionResult>;
  @useResult
  $Res call({PrinterSelectionType selectionType, String message});
}

/// @nodoc
class _$PrinterSelectionResultCopyWithImpl<$Res,
        $Val extends PrinterSelectionResult>
    implements $PrinterSelectionResultCopyWith<$Res> {
  _$PrinterSelectionResultCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of PrinterSelectionResult
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? selectionType = null,
    Object? message = null,
  }) {
    return _then(_value.copyWith(
      selectionType: null == selectionType
          ? _value.selectionType
          : selectionType // ignore: cast_nullable_to_non_nullable
              as PrinterSelectionType,
      message: null == message
          ? _value.message
          : message // ignore: cast_nullable_to_non_nullable
              as String,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$PrinterSelectionResultImplCopyWith<$Res>
    implements $PrinterSelectionResultCopyWith<$Res> {
  factory _$$PrinterSelectionResultImplCopyWith(
          _$PrinterSelectionResultImpl value,
          $Res Function(_$PrinterSelectionResultImpl) then) =
      __$$PrinterSelectionResultImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({PrinterSelectionType selectionType, String message});
}

/// @nodoc
class __$$PrinterSelectionResultImplCopyWithImpl<$Res>
    extends _$PrinterSelectionResultCopyWithImpl<$Res,
        _$PrinterSelectionResultImpl>
    implements _$$PrinterSelectionResultImplCopyWith<$Res> {
  __$$PrinterSelectionResultImplCopyWithImpl(
      _$PrinterSelectionResultImpl _value,
      $Res Function(_$PrinterSelectionResultImpl) _then)
      : super(_value, _then);

  /// Create a copy of PrinterSelectionResult
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? selectionType = null,
    Object? message = null,
  }) {
    return _then(_$PrinterSelectionResultImpl(
      selectionType: null == selectionType
          ? _value.selectionType
          : selectionType // ignore: cast_nullable_to_non_nullable
              as PrinterSelectionType,
      message: null == message
          ? _value.message
          : message // ignore: cast_nullable_to_non_nullable
              as String,
    ));
  }
}

/// @nodoc

class _$PrinterSelectionResultImpl implements _PrinterSelectionResult {
  _$PrinterSelectionResultImpl(
      {required this.selectionType, required this.message});

  /// (`RES_CODE`) Тип выбора принтера для текущего объекта.
  @override
  final PrinterSelectionType selectionType;

  /// (`RES`) Человекочитаемое описание.
  @override
  final String message;

  @override
  String toString() {
    return 'PrinterSelectionResult(selectionType: $selectionType, message: $message)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$PrinterSelectionResultImpl &&
            (identical(other.selectionType, selectionType) ||
                other.selectionType == selectionType) &&
            (identical(other.message, message) || other.message == message));
  }

  @override
  int get hashCode => Object.hash(runtimeType, selectionType, message);

  /// Create a copy of PrinterSelectionResult
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$PrinterSelectionResultImplCopyWith<_$PrinterSelectionResultImpl>
      get copyWith => __$$PrinterSelectionResultImplCopyWithImpl<
          _$PrinterSelectionResultImpl>(this, _$identity);
}

abstract class _PrinterSelectionResult implements PrinterSelectionResult {
  factory _PrinterSelectionResult(
      {required final PrinterSelectionType selectionType,
      required final String message}) = _$PrinterSelectionResultImpl;

  /// (`RES_CODE`) Тип выбора принтера для текущего объекта.
  @override
  PrinterSelectionType get selectionType;

  /// (`RES`) Человекочитаемое описание.
  @override
  String get message;

  /// Create a copy of PrinterSelectionResult
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$PrinterSelectionResultImplCopyWith<_$PrinterSelectionResultImpl>
      get copyWith => throw _privateConstructorUsedError;
}
