import 'dart:convert';

import 'package:flutter/services.dart';

import '../models/medicine.dart';

class MedicineData {
  static Future<List<Medicine>>? _catalogFuture;

  static Future<List<Medicine>> load() {
    return _catalogFuture ??= _loadCatalog();
  }

  static Future<List<Medicine>> _loadCatalog() async {
    final json =
        await rootBundle.loadString('assets/data/medicine_catalog.json');
    final catalog = jsonDecode(json) as Map<String, dynamic>;
    final items = catalog['items'] as List<dynamic>;
    return items
        .map((item) => Medicine.fromJson(item as Map<String, dynamic>))
        .toList(growable: false);
  }

  static List<Medicine> search(
    Iterable<Medicine> medicines,
    String query, {
    int limit = 20,
  }) {
    final normalizedQuery = normalizeMedicineText(query);
    if (normalizedQuery.isEmpty || limit <= 0) return const [];

    final matches = List.generate(7, (_) => <Medicine>[]);
    for (final medicine in medicines) {
      final rank = medicine.matchRank(normalizedQuery);
      if (rank >= 0 && matches[rank].length < limit) {
        matches[rank].add(medicine);
      }
    }

    return matches.expand((group) => group).take(limit).toList(growable: false);
  }
}
