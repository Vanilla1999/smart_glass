// ignore_for_file: sort_constructors_first

/// Тип принтера (мобильность) для PPRINT_PRINTADDART и PPRINT_GETTASK.
enum PrinterMobilityType {
  /// (`O`) А4 принтер (стационарный).
  office('O'),

  /// (`M`) Мобильный принтер.
  mobile('M'),

  /// (`X`) Режим отложенной печати с неизвестным принтером.
  deferredUnknown('X');

  final String dbValue;

  const PrinterMobilityType(this.dbValue);
}
