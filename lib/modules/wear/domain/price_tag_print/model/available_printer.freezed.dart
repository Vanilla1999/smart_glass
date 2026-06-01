// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'available_printer.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

/// @nodoc
mixin _$AvailablePrinter {
  /// Название принтера, например "p630022mobile_1"
  String get name => throw _privateConstructorUsedError;

  /// Номер принтера, например "1"
  String get number => throw _privateConstructorUsedError;

  /// Create a copy of AvailablePrinter
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $AvailablePrinterCopyWith<AvailablePrinter> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $AvailablePrinterCopyWith<$Res> {
  factory $AvailablePrinterCopyWith(
          AvailablePrinter value, $Res Function(AvailablePrinter) then) =
      _$AvailablePrinterCopyWithImpl<$Res, AvailablePrinter>;
  @useResult
  $Res call({String name, String number});
}

/// @nodoc
class _$AvailablePrinterCopyWithImpl<$Res, $Val extends AvailablePrinter>
    implements $AvailablePrinterCopyWith<$Res> {
  _$AvailablePrinterCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of AvailablePrinter
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? name = null,
    Object? number = null,
  }) {
    return _then(_value.copyWith(
      name: null == name
          ? _value.name
          : name // ignore: cast_nullable_to_non_nullable
              as String,
      number: null == number
          ? _value.number
          : number // ignore: cast_nullable_to_non_nullable
              as String,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$AvailablePrinterImplCopyWith<$Res>
    implements $AvailablePrinterCopyWith<$Res> {
  factory _$$AvailablePrinterImplCopyWith(_$AvailablePrinterImpl value,
          $Res Function(_$AvailablePrinterImpl) then) =
      __$$AvailablePrinterImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({String name, String number});
}

/// @nodoc
class __$$AvailablePrinterImplCopyWithImpl<$Res>
    extends _$AvailablePrinterCopyWithImpl<$Res, _$AvailablePrinterImpl>
    implements _$$AvailablePrinterImplCopyWith<$Res> {
  __$$AvailablePrinterImplCopyWithImpl(_$AvailablePrinterImpl _value,
      $Res Function(_$AvailablePrinterImpl) _then)
      : super(_value, _then);

  /// Create a copy of AvailablePrinter
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? name = null,
    Object? number = null,
  }) {
    return _then(_$AvailablePrinterImpl(
      name: null == name
          ? _value.name
          : name // ignore: cast_nullable_to_non_nullable
              as String,
      number: null == number
          ? _value.number
          : number // ignore: cast_nullable_to_non_nullable
              as String,
    ));
  }
}

/// @nodoc

class _$AvailablePrinterImpl implements _AvailablePrinter {
  _$AvailablePrinterImpl({required this.name, required this.number});

  /// Название принтера, например "p630022mobile_1"
  @override
  final String name;

  /// Номер принтера, например "1"
  @override
  final String number;

  @override
  String toString() {
    return 'AvailablePrinter(name: $name, number: $number)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$AvailablePrinterImpl &&
            (identical(other.name, name) || other.name == name) &&
            (identical(other.number, number) || other.number == number));
  }

  @override
  int get hashCode => Object.hash(runtimeType, name, number);

  /// Create a copy of AvailablePrinter
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$AvailablePrinterImplCopyWith<_$AvailablePrinterImpl> get copyWith =>
      __$$AvailablePrinterImplCopyWithImpl<_$AvailablePrinterImpl>(
          this, _$identity);
}

abstract class _AvailablePrinter implements AvailablePrinter {
  factory _AvailablePrinter(
      {required final String name,
      required final String number}) = _$AvailablePrinterImpl;

  /// Название принтера, например "p630022mobile_1"
  @override
  String get name;

  /// Номер принтера, например "1"
  @override
  String get number;

  /// Create a copy of AvailablePrinter
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$AvailablePrinterImplCopyWith<_$AvailablePrinterImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
