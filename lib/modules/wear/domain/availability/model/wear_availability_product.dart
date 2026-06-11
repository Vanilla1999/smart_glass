class WearAvailabilityProduct {
  const WearAvailabilityProduct({
    required this.id,
    required this.groupId,
    required this.name,
    required this.code,
    required this.barcodes,
    required this.priceTagBarcodes,
    required this.price,
    required this.rest,
    required this.checkPrice,
    required this.photoControl,
    required this.unpackaged,
    required this.priceTagActual,
    this.loyaltyPrice,
  });

  factory WearAvailabilityProduct.fromJson(Map<String, dynamic> json) {
    return WearAvailabilityProduct(
      id: _asInt(json['id']),
      groupId: _asInt(json['groupId']),
      name: _asString(json['name']),
      code: _asString(json['code']),
      barcodes: _asStringList(json['barcodes']),
      priceTagBarcodes: _asStringList(json['priceTagBarcodes']),
      price: _asDouble(json['price']),
      loyaltyPrice:
          json['loyaltyPrice'] == null ? null : _asDouble(json['loyaltyPrice']),
      rest: _asDouble(json['rest']),
      checkPrice: json['checkPrice'] == true,
      photoControl: json['photoControl'] == true,
      unpackaged: json['unpackaged'] == true,
      priceTagActual: json['priceTagActual'] == true,
    );
  }

  final int id;
  final int groupId;
  final String name;
  final String code;
  final List<String> barcodes;
  final List<String> priceTagBarcodes;
  final double price;
  final double? loyaltyPrice;
  final double rest;
  final bool checkPrice;
  final bool photoControl;
  final bool unpackaged;
  final bool priceTagActual;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'groupId': groupId,
      'name': name,
      'code': code,
      'barcodes': barcodes,
      'priceTagBarcodes': priceTagBarcodes,
      'price': price,
      'loyaltyPrice': loyaltyPrice,
      'rest': rest,
      'checkPrice': checkPrice,
      'photoControl': photoControl,
      'unpackaged': unpackaged,
      'priceTagActual': priceTagActual,
    };
  }

  WearAvailabilityProduct copyWith({
    int? groupId,
    String? name,
    String? code,
    List<String>? barcodes,
    List<String>? priceTagBarcodes,
    double? price,
    double? loyaltyPrice,
    double? rest,
    bool? checkPrice,
    bool? photoControl,
    bool? unpackaged,
    bool? priceTagActual,
  }) {
    return WearAvailabilityProduct(
      id: id,
      groupId: groupId ?? this.groupId,
      name: name ?? this.name,
      code: code ?? this.code,
      barcodes: barcodes ?? this.barcodes,
      priceTagBarcodes: priceTagBarcodes ?? this.priceTagBarcodes,
      price: price ?? this.price,
      loyaltyPrice: loyaltyPrice ?? this.loyaltyPrice,
      rest: rest ?? this.rest,
      checkPrice: checkPrice ?? this.checkPrice,
      photoControl: photoControl ?? this.photoControl,
      unpackaged: unpackaged ?? this.unpackaged,
      priceTagActual: priceTagActual ?? this.priceTagActual,
    );
  }

  bool matchesProductBarcode(String barcode) {
    final String normalized = barcode.trim();
    return code == normalized || barcodes.contains(normalized);
  }

  bool matchesPriceTagBarcode(String barcode) {
    return priceTagBarcodes.contains(barcode.trim());
  }

  static int _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) {
      final int? parsed = int.tryParse(value);
      if (parsed != null) return parsed;
    }
    throw Exception('Некорректный ID товара');
  }

  static double _asDouble(Object? value) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    if (value is String) {
      final double? parsed = double.tryParse(value.replaceAll(',', '.'));
      if (parsed != null) return parsed;
    }
    throw Exception('Некорректное значение товара');
  }

  static String _asString(Object? value) {
    if (value == null) return '';
    if (value is String) return value;
    return value.toString();
  }

  static List<String> _asStringList(Object? value) {
    if (value is! List) return const <String>[];
    return value
        .map(_asString)
        .where((String item) => item.trim().isNotEmpty)
        .toList(growable: false);
  }
}
