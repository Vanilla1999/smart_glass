// ignore_for_file: sort_constructors_first

/// Тип штрихкода, возвращаемый PPRINT_INFO_BARCODE2.
enum BarcodeType {
  /// (`PRINTER`) ШК принтера.
  printer('PRINTER'),

  /// (`PRICE`) ШК ценника.
  price('PRICE'),

  /// (`ART`) ШК товара.
  article('ART');

  final String dbValue;

  const BarcodeType(this.dbValue);

  static BarcodeType fromDbValue(String? value) {
    switch (value) {
      case 'PRINTER':
        return BarcodeType.printer;
      case 'PRICE':
        return BarcodeType.price;
      case 'ART':
        return BarcodeType.article;
      default:
        throw Exception('Неизвестный ШК: $value');
    }
  }
}
