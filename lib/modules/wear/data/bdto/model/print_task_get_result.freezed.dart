// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'print_task_get_result.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

/// @nodoc
mixin _$PrintGetTaskResult {
  /// (`ID_SHTASK`) Идентификатор задания печати.
  int get taskId => throw _privateConstructorUsedError;

  /// Create a copy of PrintGetTaskResult
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $PrintGetTaskResultCopyWith<PrintGetTaskResult> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $PrintGetTaskResultCopyWith<$Res> {
  factory $PrintGetTaskResultCopyWith(
          PrintGetTaskResult value, $Res Function(PrintGetTaskResult) then) =
      _$PrintGetTaskResultCopyWithImpl<$Res, PrintGetTaskResult>;
  @useResult
  $Res call({int taskId});
}

/// @nodoc
class _$PrintGetTaskResultCopyWithImpl<$Res, $Val extends PrintGetTaskResult>
    implements $PrintGetTaskResultCopyWith<$Res> {
  _$PrintGetTaskResultCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of PrintGetTaskResult
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? taskId = null,
  }) {
    return _then(_value.copyWith(
      taskId: null == taskId
          ? _value.taskId
          : taskId // ignore: cast_nullable_to_non_nullable
              as int,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$PrintGetTaskResultImplCopyWith<$Res>
    implements $PrintGetTaskResultCopyWith<$Res> {
  factory _$$PrintGetTaskResultImplCopyWith(_$PrintGetTaskResultImpl value,
          $Res Function(_$PrintGetTaskResultImpl) then) =
      __$$PrintGetTaskResultImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({int taskId});
}

/// @nodoc
class __$$PrintGetTaskResultImplCopyWithImpl<$Res>
    extends _$PrintGetTaskResultCopyWithImpl<$Res, _$PrintGetTaskResultImpl>
    implements _$$PrintGetTaskResultImplCopyWith<$Res> {
  __$$PrintGetTaskResultImplCopyWithImpl(_$PrintGetTaskResultImpl _value,
      $Res Function(_$PrintGetTaskResultImpl) _then)
      : super(_value, _then);

  /// Create a copy of PrintGetTaskResult
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? taskId = null,
  }) {
    return _then(_$PrintGetTaskResultImpl(
      taskId: null == taskId
          ? _value.taskId
          : taskId // ignore: cast_nullable_to_non_nullable
              as int,
    ));
  }
}

/// @nodoc

class _$PrintGetTaskResultImpl implements _PrintGetTaskResult {
  _$PrintGetTaskResultImpl({required this.taskId});

  /// (`ID_SHTASK`) Идентификатор задания печати.
  @override
  final int taskId;

  @override
  String toString() {
    return 'PrintGetTaskResult(taskId: $taskId)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$PrintGetTaskResultImpl &&
            (identical(other.taskId, taskId) || other.taskId == taskId));
  }

  @override
  int get hashCode => Object.hash(runtimeType, taskId);

  /// Create a copy of PrintGetTaskResult
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$PrintGetTaskResultImplCopyWith<_$PrintGetTaskResultImpl> get copyWith =>
      __$$PrintGetTaskResultImplCopyWithImpl<_$PrintGetTaskResultImpl>(
          this, _$identity);
}

abstract class _PrintGetTaskResult implements PrintGetTaskResult {
  factory _PrintGetTaskResult({required final int taskId}) =
      _$PrintGetTaskResultImpl;

  /// (`ID_SHTASK`) Идентификатор задания печати.
  @override
  int get taskId;

  /// Create a copy of PrintGetTaskResult
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$PrintGetTaskResultImplCopyWith<_$PrintGetTaskResultImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
