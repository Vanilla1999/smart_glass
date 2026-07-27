import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('keeps test products and imports the Danfi beverage catalog', () {
    final Map<String, dynamic> catalog = jsonDecode(
      File('assets/catalog/availability_catalog.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final List<Map<String, dynamic>> products =
        (catalog['products'] as List<dynamic>).cast<Map<String, dynamic>>();
    final List<Map<String, dynamic>> beverages = products
        .where((Map<String, dynamic> product) => product['groupId'] == 2)
        .toList(growable: false);

    expect(
        products.map((Map<String, dynamic> product) => product['id']).toSet(),
        hasLength(products.length));
    expect(beverages, hasLength(1063));
    expect(
      products.any(
        (Map<String, dynamic> product) => product['id'] == 9000000001,
      ),
      isTrue,
    );
    expect(
      beverages.every(
        (Map<String, dynamic> product) =>
            product['barcodes'].isNotEmpty &&
            product['price'] == 0 &&
            product['rest'] == 0,
      ),
      isTrue,
    );
  });
}
