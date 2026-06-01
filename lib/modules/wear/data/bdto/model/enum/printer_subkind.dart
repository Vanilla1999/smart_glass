// ignore_for_file: sort_constructors_first

/// Подтип принтера из списка PPRINT_PRINTERLIST.
enum PrinterSubkind {
  /// (`0`) Обычный переносной принтер.
  /// Для принтеров А4 [PrinterKind.office] всегда возвращается это значение.
  portable('0'),

  /// (`T`) Стационарный термопринтер.
  stationaryThermal('T'),

  /// (`UNKNOWN`) Неизвестный подтип принтера.
  unknown('UNKNOWN');

  final String dbValue;

  const PrinterSubkind(this.dbValue);

  static PrinterSubkind fromDbValue(String? value) {
    switch (value) {
      case '0':
        return PrinterSubkind.portable;
      case 'T':
        return PrinterSubkind.stationaryThermal;
      default:
        throw Exception('Неизвестный подтип принтера: $value');
    }
  }
}
