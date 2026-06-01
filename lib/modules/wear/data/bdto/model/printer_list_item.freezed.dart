// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'printer_list_item.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

/// @nodoc
mixin _$PrinterListItem {
  /// (`NAME`) Человекочитаемое имя принтера.
  String get name => throw _privateConstructorUsedError;

  /// (`ALIAS`) Алиас принтера.
  String get alias => throw _privateConstructorUsedError;

  /// (`KIND`) Тип принтера (A4 или мобильный/термо).
  PrinterKind get kind => throw _privateConstructorUsedError;

  /// (`SUBKIND`) Подтип принтера.
  PrinterSubkind get subkind => throw _privateConstructorUsedError;

  /// Create a copy of PrinterListItem
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $PrinterListItemCopyWith<PrinterListItem> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $PrinterListItemCopyWith<$Res> {
  factory $PrinterListItemCopyWith(
          PrinterListItem value, $Res Function(PrinterListItem) then) =
      _$PrinterListItemCopyWithImpl<$Res, PrinterListItem>;
  @useResult
  $Res call(
      {String name, String alias, PrinterKind kind, PrinterSubkind subkind});
}

/// @nodoc
class _$PrinterListItemCopyWithImpl<$Res, $Val extends PrinterListItem>
    implements $PrinterListItemCopyWith<$Res> {
  _$PrinterListItemCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of PrinterListItem
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? name = null,
    Object? alias = null,
    Object? kind = null,
    Object? subkind = null,
  }) {
    return _then(_value.copyWith(
      name: null == name
          ? _value.name
          : name // ignore: cast_nullable_to_non_nullable
              as String,
      alias: null == alias
          ? _value.alias
          : alias // ignore: cast_nullable_to_non_nullable
              as String,
      kind: null == kind
          ? _value.kind
          : kind // ignore: cast_nullable_to_non_nullable
              as PrinterKind,
      subkind: null == subkind
          ? _value.subkind
          : subkind // ignore: cast_nullable_to_non_nullable
              as PrinterSubkind,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$PrinterListItemImplCopyWith<$Res>
    implements $PrinterListItemCopyWith<$Res> {
  factory _$$PrinterListItemImplCopyWith(_$PrinterListItemImpl value,
          $Res Function(_$PrinterListItemImpl) then) =
      __$$PrinterListItemImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String name, String alias, PrinterKind kind, PrinterSubkind subkind});
}

/// @nodoc
class __$$PrinterListItemImplCopyWithImpl<$Res>
    extends _$PrinterListItemCopyWithImpl<$Res, _$PrinterListItemImpl>
    implements _$$PrinterListItemImplCopyWith<$Res> {
  __$$PrinterListItemImplCopyWithImpl(
      _$PrinterListItemImpl _value, $Res Function(_$PrinterListItemImpl) _then)
      : super(_value, _then);

  /// Create a copy of PrinterListItem
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? name = null,
    Object? alias = null,
    Object? kind = null,
    Object? subkind = null,
  }) {
    return _then(_$PrinterListItemImpl(
      name: null == name
          ? _value.name
          : name // ignore: cast_nullable_to_non_nullable
              as String,
      alias: null == alias
          ? _value.alias
          : alias // ignore: cast_nullable_to_non_nullable
              as String,
      kind: null == kind
          ? _value.kind
          : kind // ignore: cast_nullable_to_non_nullable
              as PrinterKind,
      subkind: null == subkind
          ? _value.subkind
          : subkind // ignore: cast_nullable_to_non_nullable
              as PrinterSubkind,
    ));
  }
}

/// @nodoc

class _$PrinterListItemImpl implements _PrinterListItem {
  _$PrinterListItemImpl(
      {required this.name,
      required this.alias,
      required this.kind,
      required this.subkind});

  /// (`NAME`) Человекочитаемое имя принтера.
  @override
  final String name;

  /// (`ALIAS`) Алиас принтера.
  @override
  final String alias;

  /// (`KIND`) Тип принтера (A4 или мобильный/термо).
  @override
  final PrinterKind kind;

  /// (`SUBKIND`) Подтип принтера.
  @override
  final PrinterSubkind subkind;

  @override
  String toString() {
    return 'PrinterListItem(name: $name, alias: $alias, kind: $kind, subkind: $subkind)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$PrinterListItemImpl &&
            (identical(other.name, name) || other.name == name) &&
            (identical(other.alias, alias) || other.alias == alias) &&
            (identical(other.kind, kind) || other.kind == kind) &&
            (identical(other.subkind, subkind) || other.subkind == subkind));
  }

  @override
  int get hashCode => Object.hash(runtimeType, name, alias, kind, subkind);

  /// Create a copy of PrinterListItem
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$PrinterListItemImplCopyWith<_$PrinterListItemImpl> get copyWith =>
      __$$PrinterListItemImplCopyWithImpl<_$PrinterListItemImpl>(
          this, _$identity);
}

abstract class _PrinterListItem implements PrinterListItem {
  factory _PrinterListItem(
      {required final String name,
      required final String alias,
      required final PrinterKind kind,
      required final PrinterSubkind subkind}) = _$PrinterListItemImpl;

  /// (`NAME`) Человекочитаемое имя принтера.
  @override
  String get name;

  /// (`ALIAS`) Алиас принтера.
  @override
  String get alias;

  /// (`KIND`) Тип принтера (A4 или мобильный/термо).
  @override
  PrinterKind get kind;

  /// (`SUBKIND`) Подтип принтера.
  @override
  PrinterSubkind get subkind;

  /// Create a copy of PrinterListItem
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$PrinterListItemImplCopyWith<_$PrinterListItemImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
