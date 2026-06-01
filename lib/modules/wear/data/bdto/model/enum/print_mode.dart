// ignore_for_file: sort_constructors_first

/// Режим печати для PPRINT_PRINTADDART.
enum PrintMode {
  /// (`1`) Мгновенная печать.
  instant('1'),

  /// (`0`) Отложенная печать.
  queued('0');

  final String dbValue;

  const PrintMode(this.dbValue);
}
