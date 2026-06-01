// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'print_add_art_result.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

/// @nodoc
mixin _$PrintAddArtResult {
  /// (`MES`) Сообщение для отображения в интерфейсе.
  String get message => throw _privateConstructorUsedError;

  /// (`RESCODE`) Код результата.
  int get resultCode => throw _privateConstructorUsedError;

  /// (`PRINTQUANT`) Количество печатаемых ценников.
  int get printQuantity => throw _privateConstructorUsedError;

  /// (`ISACTION`) Признак акционности.
  PriceTagActionFlag get actionFlag => throw _privateConstructorUsedError;

  /// (`R_IDSHTASK`) Идентификатор задания печати.
  int get taskId => throw _privateConstructorUsedError;

  /// Create a copy of PrintAddArtResult
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $PrintAddArtResultCopyWith<PrintAddArtResult> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $PrintAddArtResultCopyWith<$Res> {
  factory $PrintAddArtResultCopyWith(
          PrintAddArtResult value, $Res Function(PrintAddArtResult) then) =
      _$PrintAddArtResultCopyWithImpl<$Res, PrintAddArtResult>;
  @useResult
  $Res call(
      {String message,
      int resultCode,
      int printQuantity,
      PriceTagActionFlag actionFlag,
      int taskId});
}

/// @nodoc
class _$PrintAddArtResultCopyWithImpl<$Res, $Val extends PrintAddArtResult>
    implements $PrintAddArtResultCopyWith<$Res> {
  _$PrintAddArtResultCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of PrintAddArtResult
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? message = null,
    Object? resultCode = null,
    Object? printQuantity = null,
    Object? actionFlag = null,
    Object? taskId = null,
  }) {
    return _then(_value.copyWith(
      message: null == message
          ? _value.message
          : message // ignore: cast_nullable_to_non_nullable
              as String,
      resultCode: null == resultCode
          ? _value.resultCode
          : resultCode // ignore: cast_nullable_to_non_nullable
              as int,
      printQuantity: null == printQuantity
          ? _value.printQuantity
          : printQuantity // ignore: cast_nullable_to_non_nullable
              as int,
      actionFlag: null == actionFlag
          ? _value.actionFlag
          : actionFlag // ignore: cast_nullable_to_non_nullable
              as PriceTagActionFlag,
      taskId: null == taskId
          ? _value.taskId
          : taskId // ignore: cast_nullable_to_non_nullable
              as int,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$PrintAddArtResultImplCopyWith<$Res>
    implements $PrintAddArtResultCopyWith<$Res> {
  factory _$$PrintAddArtResultImplCopyWith(_$PrintAddArtResultImpl value,
          $Res Function(_$PrintAddArtResultImpl) then) =
      __$$PrintAddArtResultImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String message,
      int resultCode,
      int printQuantity,
      PriceTagActionFlag actionFlag,
      int taskId});
}

/// @nodoc
class __$$PrintAddArtResultImplCopyWithImpl<$Res>
    extends _$PrintAddArtResultCopyWithImpl<$Res, _$PrintAddArtResultImpl>
    implements _$$PrintAddArtResultImplCopyWith<$Res> {
  __$$PrintAddArtResultImplCopyWithImpl(_$PrintAddArtResultImpl _value,
      $Res Function(_$PrintAddArtResultImpl) _then)
      : super(_value, _then);

  /// Create a copy of PrintAddArtResult
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? message = null,
    Object? resultCode = null,
    Object? printQuantity = null,
    Object? actionFlag = null,
    Object? taskId = null,
  }) {
    return _then(_$PrintAddArtResultImpl(
      message: null == message
          ? _value.message
          : message // ignore: cast_nullable_to_non_nullable
              as String,
      resultCode: null == resultCode
          ? _value.resultCode
          : resultCode // ignore: cast_nullable_to_non_nullable
              as int,
      printQuantity: null == printQuantity
          ? _value.printQuantity
          : printQuantity // ignore: cast_nullable_to_non_nullable
              as int,
      actionFlag: null == actionFlag
          ? _value.actionFlag
          : actionFlag // ignore: cast_nullable_to_non_nullable
              as PriceTagActionFlag,
      taskId: null == taskId
          ? _value.taskId
          : taskId // ignore: cast_nullable_to_non_nullable
              as int,
    ));
  }
}

/// @nodoc

class _$PrintAddArtResultImpl implements _PrintAddArtResult {
  _$PrintAddArtResultImpl(
      {required this.message,
      required this.resultCode,
      required this.printQuantity,
      required this.actionFlag,
      required this.taskId});

  /// (`MES`) Сообщение для отображения в интерфейсе.
  @override
  final String message;

  /// (`RESCODE`) Код результата.
  @override
  final int resultCode;

  /// (`PRINTQUANT`) Количество печатаемых ценников.
  @override
  final int printQuantity;

  /// (`ISACTION`) Признак акционности.
  @override
  final PriceTagActionFlag actionFlag;

  /// (`R_IDSHTASK`) Идентификатор задания печати.
  @override
  final int taskId;

  @override
  String toString() {
    return 'PrintAddArtResult(message: $message, resultCode: $resultCode, printQuantity: $printQuantity, actionFlag: $actionFlag, taskId: $taskId)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$PrintAddArtResultImpl &&
            (identical(other.message, message) || other.message == message) &&
            (identical(other.resultCode, resultCode) ||
                other.resultCode == resultCode) &&
            (identical(other.printQuantity, printQuantity) ||
                other.printQuantity == printQuantity) &&
            (identical(other.actionFlag, actionFlag) ||
                other.actionFlag == actionFlag) &&
            (identical(other.taskId, taskId) || other.taskId == taskId));
  }

  @override
  int get hashCode => Object.hash(
      runtimeType, message, resultCode, printQuantity, actionFlag, taskId);

  /// Create a copy of PrintAddArtResult
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$PrintAddArtResultImplCopyWith<_$PrintAddArtResultImpl> get copyWith =>
      __$$PrintAddArtResultImplCopyWithImpl<_$PrintAddArtResultImpl>(
          this, _$identity);
}

abstract class _PrintAddArtResult implements PrintAddArtResult {
  factory _PrintAddArtResult(
      {required final String message,
      required final int resultCode,
      required final int printQuantity,
      required final PriceTagActionFlag actionFlag,
      required final int taskId}) = _$PrintAddArtResultImpl;

  /// (`MES`) Сообщение для отображения в интерфейсе.
  @override
  String get message;

  /// (`RESCODE`) Код результата.
  @override
  int get resultCode;

  /// (`PRINTQUANT`) Количество печатаемых ценников.
  @override
  int get printQuantity;

  /// (`ISACTION`) Признак акционности.
  @override
  PriceTagActionFlag get actionFlag;

  /// (`R_IDSHTASK`) Идентификатор задания печати.
  @override
  int get taskId;

  /// Create a copy of PrintAddArtResult
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$PrintAddArtResultImplCopyWith<_$PrintAddArtResultImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
