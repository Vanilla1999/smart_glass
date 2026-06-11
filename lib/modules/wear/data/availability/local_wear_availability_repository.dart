import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_glasses/modules/wear/domain/availability/model/wear_availability_group.dart';
import 'package:smart_glasses/modules/wear/domain/availability/model/wear_availability_product.dart';
import 'package:smart_glasses/modules/wear/domain/availability/repository/wear_availability_repository.dart';

class LocalWearAvailabilityRepository implements WearAvailabilityRepository {
  LocalWearAvailabilityRepository({
    this.assetPath = 'assets/catalog/availability_catalog.json',
  });

  static const int scannedGroupId = 900001;
  static const String scannedGroupName = 'Сканированная полка';
  static const String _scannedProductsKey =
      'wear_availability_scanned_products';

  final String assetPath;
  final Set<int> _completedProductIds = <int>{};

  _WearAvailabilityCatalog? _cache;
  List<WearAvailabilityProduct>? _scannedProductsCache;

  @override
  Future<List<WearAvailabilityGroup>> getGroups() async {
    final _WearAvailabilityCatalog catalog = await _loadCatalog();
    final List<WearAvailabilityProduct> products = await _loadProducts(catalog);
    final Map<int, WearAvailabilityGroup> groups = <int, WearAvailabilityGroup>{
      for (final WearAvailabilityGroup group in catalog.groups) group.id: group,
    };
    if (products.any(
      (WearAvailabilityProduct product) => product.groupId == scannedGroupId,
    )) {
      groups.putIfAbsent(
        scannedGroupId,
        () => const WearAvailabilityGroup(
          id: scannedGroupId,
          name: scannedGroupName,
          counter: 0,
        ),
      );
    }
    return groups.values
        .map(
          (WearAvailabilityGroup group) => group.copyWith(
            counter: products
                .where(
                  (WearAvailabilityProduct product) =>
                      product.groupId == group.id &&
                      !_completedProductIds.contains(product.id),
                )
                .length,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<List<WearAvailabilityProduct>> getProductsByGroup(int groupId) async {
    final _WearAvailabilityCatalog catalog = await _loadCatalog();
    final List<WearAvailabilityProduct> products = await _loadProducts(catalog);
    return products
        .where(
          (WearAvailabilityProduct product) =>
              product.groupId == groupId &&
              !_completedProductIds.contains(product.id),
        )
        .toList(growable: false);
  }

  @override
  Future<List<WearAvailabilityProduct>> findProductsByBarcode(
    String barcode,
  ) async {
    final String normalized = barcode.trim();
    final _WearAvailabilityCatalog catalog = await _loadCatalog();
    final List<WearAvailabilityProduct> products = await _loadProducts(catalog);
    return products
        .where(
          (WearAvailabilityProduct product) =>
              !_completedProductIds.contains(product.id) &&
              (product.matchesProductBarcode(normalized) ||
                  product.matchesPriceTagBarcode(normalized)),
        )
        .toList(growable: false);
  }

  @override
  Future<WearAvailabilityProduct> upsertScannedProduct({
    required int articleId,
    required String name,
    required String barcode,
    double? rest,
  }) async {
    final String normalizedBarcode = barcode.trim();
    if (normalizedBarcode.isEmpty) {
      throw Exception('Пустой ШК');
    }

    final _WearAvailabilityCatalog catalog = await _loadCatalog();
    final WearAvailabilityProduct? catalogProduct = _findCatalogProduct(
      catalog.products,
      articleId: articleId,
      barcode: normalizedBarcode,
    );
    final WearAvailabilityProduct product = (catalogProduct ??
            WearAvailabilityProduct(
              id: articleId,
              groupId: scannedGroupId,
              name: name.trim().isEmpty ? 'Товар $articleId' : name.trim(),
              code: articleId.toString(),
              barcodes: const <String>[],
              priceTagBarcodes: const <String>[],
              price: 0,
              rest: rest ?? 0,
              checkPrice: true,
              photoControl: false,
              unpackaged: false,
              priceTagActual: true,
            ))
        .copyWith(
      groupId: scannedGroupId,
      name: name.trim().isEmpty ? null : name.trim(),
      barcodes: _mergeBarcode(catalogProduct?.barcodes, normalizedBarcode),
      priceTagBarcodes: _mergeBarcode(
        catalogProduct?.priceTagBarcodes,
        normalizedBarcode,
      ),
      rest: rest,
    );

    final List<WearAvailabilityProduct> scannedProducts =
        List<WearAvailabilityProduct>.of(await _loadScannedProducts());
    final int existingIndex = scannedProducts.indexWhere(
      (WearAvailabilityProduct item) => item.id == product.id,
    );
    if (existingIndex >= 0) {
      scannedProducts[existingIndex] = product;
    } else {
      scannedProducts.add(product);
    }
    await _saveScannedProducts(scannedProducts);
    _completedProductIds.remove(product.id);
    return product;
  }

  @override
  Future<void> resetScannedProducts() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove(_scannedProductsKey);
    _scannedProductsCache = <WearAvailabilityProduct>[];
  }

  @override
  Future<void> completeProduct(int productId) async {
    _completedProductIds.add(productId);
  }

  @override
  Future<void> resetCompletedProducts() async {
    _completedProductIds.clear();
  }

  Future<List<WearAvailabilityProduct>> _loadProducts(
    _WearAvailabilityCatalog catalog,
  ) async {
    final List<WearAvailabilityProduct> scannedProducts =
        await _loadScannedProducts();
    if (scannedProducts.isEmpty) {
      return catalog.products;
    }
    final Map<int, WearAvailabilityProduct> products =
        <int, WearAvailabilityProduct>{
      for (final WearAvailabilityProduct product in catalog.products)
        product.id: product,
    };
    for (final WearAvailabilityProduct product in scannedProducts) {
      products[product.id] = product;
    }
    return products.values.toList(growable: false);
  }

  Future<List<WearAvailabilityProduct>> _loadScannedProducts() async {
    final List<WearAvailabilityProduct>? cached = _scannedProductsCache;
    if (cached != null) return cached;

    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? rawJson = prefs.getString(_scannedProductsKey);
    if (rawJson == null || rawJson.trim().isEmpty) {
      _scannedProductsCache = <WearAvailabilityProduct>[];
      return _scannedProductsCache!;
    }
    final List<WearAvailabilityProduct> products =
        (jsonDecode(rawJson) as List<dynamic>? ?? const <dynamic>[])
            .whereType<Map<String, dynamic>>()
            .map(WearAvailabilityProduct.fromJson)
            .toList(growable: false);
    _scannedProductsCache = products;
    return products;
  }

  Future<void> _saveScannedProducts(
    List<WearAvailabilityProduct> products,
  ) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _scannedProductsKey,
      jsonEncode(
        products
            .map((WearAvailabilityProduct product) => product.toJson())
            .toList(growable: false),
      ),
    );
    _scannedProductsCache = products;
  }

  Future<_WearAvailabilityCatalog> _loadCatalog() async {
    final _WearAvailabilityCatalog? cached = _cache;
    if (cached != null) return cached;

    final String rawJson = await rootBundle.loadString(assetPath);
    final Map<String, dynamic> json =
        jsonDecode(rawJson) as Map<String, dynamic>;
    final List<WearAvailabilityProduct> products =
        (json['products'] as List<dynamic>? ?? const <dynamic>[])
            .whereType<Map<String, dynamic>>()
            .map(WearAvailabilityProduct.fromJson)
            .toList(growable: false);
    final List<WearAvailabilityGroup> groups =
        (json['groups'] as List<dynamic>? ?? const <dynamic>[])
            .whereType<Map<String, dynamic>>()
            .map(
              (Map<String, dynamic> group) => WearAvailabilityGroup.fromJson(
                group,
                counter: products
                    .where(
                      (WearAvailabilityProduct product) =>
                          product.groupId == _asInt(group['id']),
                    )
                    .length,
              ),
            )
            .toList(growable: false);

    final _WearAvailabilityCatalog catalog = _WearAvailabilityCatalog(
      groups: groups,
      products: products,
    );
    _cache = catalog;
    return catalog;
  }

  List<String> _mergeBarcode(List<String>? source, String barcode) {
    final Set<String> values = <String>{
      ...?source,
      barcode,
    }..removeWhere((String value) => value.trim().isEmpty);
    return values.toList(growable: false);
  }

  WearAvailabilityProduct? _findCatalogProduct(
    List<WearAvailabilityProduct> products, {
    required int articleId,
    required String barcode,
  }) {
    for (final WearAvailabilityProduct product in products) {
      if (product.id == articleId || product.matchesProductBarcode(barcode)) {
        return product;
      }
    }
    return null;
  }

  int _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) {
      final int? parsed = int.tryParse(value);
      if (parsed != null) return parsed;
    }
    throw Exception('Некорректный ID группы');
  }
}

class _WearAvailabilityCatalog {
  const _WearAvailabilityCatalog({
    required this.groups,
    required this.products,
  });

  final List<WearAvailabilityGroup> groups;
  final List<WearAvailabilityProduct> products;
}
