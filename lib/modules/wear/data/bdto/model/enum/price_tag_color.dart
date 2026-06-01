// ignore_for_file: sort_constructors_first

/// Цвет ценника, возвращаемый по `R_COLOR` из `PPRINT_CENNIK2`.
enum PriceTagColor {
  /// Белый (неакционный) ценник.
  white,

  /// Жетлый (акционный) ценник.
  yellow;

  static PriceTagColor fromDbValue(int? value) {
    if (value == 1) {
      return PriceTagColor.yellow;
    }
    return PriceTagColor.white;
  }
}
