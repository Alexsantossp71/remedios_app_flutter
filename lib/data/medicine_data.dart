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

  /// Resolve um código de barras (EAN/UPC) para um medicamento do catálogo.
  ///
  /// Busca linear de propósito: ~25 mil itens com listas curtas de EAN
  /// percorrem em milissegundos e não justificam manter um índice em
  /// memória ao lado do autocomplete.
  static Future<Medicine?> findByEan(String ean) async {
    final digits = ean.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return null;
    final medicines = await load();
    for (final medicine in medicines) {
      if (medicine.eans.contains(digits)) return medicine;
    }
    return null;
  }

  /// Melhor entrada do catálogo para um nome lido por OCR na receita.
  ///
  /// Casamento ESTRICTO de propósito: só EAN, nome/alias exato ou prefixo
  /// (rank ≤ 4). "Contém" (rank 6) fica de fora — OCR estragado demais
  /// merece conferência humana, não o palpite mais parecido; é o mesmo
  /// contrato da conferência da receita: sugerir nunca é salvar.
  static Medicine? bestMatch(Iterable<Medicine> medicines, String query) {
    final normalizedQuery = normalizeMedicineText(query);
    if (normalizedQuery.isEmpty) return null;
    Medicine? best;
    var bestRank = 1 << 30;
    for (final medicine in medicines) {
      final rank = medicine.matchRank(normalizedQuery);
      if (rank >= 0 && rank < bestRank) {
        best = medicine;
        bestRank = rank;
        if (bestRank == 0) break; // EAN exato não tem como melhorar
      }
    }
    if (best == null || bestRank > 4) return null;
    return best;
  }
}
