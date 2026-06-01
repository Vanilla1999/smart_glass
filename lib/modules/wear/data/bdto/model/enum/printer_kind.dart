// ignore_for_file: sort_constructors_first

/// Тип принтера, используемый в фильтрах и списках.
enum PrinterKind {
  /// (`O`) А4 принтер.
  office('O'),

  /// (`M`) Мобильный или термопринтер.
  mobile('M');

  final String dbValue;

  const PrinterKind(this.dbValue);

  static PrinterKind fromDbValue(String? value) {
    switch (value) {
      case 'O':
        return PrinterKind.office;
      case 'M':
        return PrinterKind.mobile;
      default:
        throw Exception('Неизвестный тип принтера: $value');
    }
  }
}
