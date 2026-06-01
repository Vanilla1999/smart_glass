// ignore_for_file: sort_constructors_first

import 'package:freezed_annotation/freezed_annotation.dart';

/// Признак акционности ценника, возвращаемый PPRINT_PRINTADDART и
/// используемый как фильтр в PPRINT_PRINT.
@JsonEnum(valueField: 'dbValue')
enum PriceTagActionFlag {
  /// (`1`) Акционный ценник.
  action('1'),

  /// (`0`) Обычный ценник.
  regular('0');

  final String dbValue;

  const PriceTagActionFlag(this.dbValue);

  static PriceTagActionFlag fromDbValue(String? value) {
    switch (value) {
      case '1':
        return PriceTagActionFlag.action;
      case '0':
        return PriceTagActionFlag.regular;
      default:
        throw Exception('Неизвестный признак акционности ценника: $value');
    }
  }
}
