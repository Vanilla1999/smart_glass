// ignore_for_file: sort_constructors_first

/// Тип выбора принтера, возвращаемый PPRINT_PRINTERSORT.
enum PrinterSelectionType {
  /// (`0`) На объекте существует единственный принтер А4, выбирать не нужно.
  defaultPrinter(0),

  /// (`1`) Принтер определяется сканированием штрихкода.
  scanBarcode(1),

  /// (`2`) Принтер выбирается из списка.
  selectFromList(2);

  final int code;

  const PrinterSelectionType(this.code);

  static PrinterSelectionType fromCode(int? code) {
    switch (code) {
      case 0:
        return PrinterSelectionType.defaultPrinter;
      case 1:
        return PrinterSelectionType.scanBarcode;
      case 2:
        return PrinterSelectionType.selectFromList;
      default:
        throw Exception('Неизвестный тип выбора принтера: $code');
    }
  }
}
